#!/usr/bin/env python3
"""omarchy-gp: a small Material-style panel for the official GlobalProtect client.

It never modifies the official install. State comes from the tunnel interface
and the `globalprotect` CLI; connect and disconnect go through the official
agent. The official window (PanGPUI) is always available as a fallback.

Usage:
  omarchy-gp              show or hide the panel
  omarchy-gp connect      connect with the saved account
  omarchy-gp disconnect   disconnect
  omarchy-gp traffic      open the traffic window
  omarchy-gp account      open the account window
  omarchy-gp status       print waybar JSON and exit
"""
import ipaddress
import json
import os
import pty
import re
import select
import shutil
import signal
import socket
import subprocess
import sys
import threading
import time
from pathlib import Path

APP = "omarchy-gp"
VERSION = "0.1.0"
HERE = Path(__file__).resolve().parent
GP_DIR = "/opt/paloaltonetworks/globalprotect"
GP_HOME = Path.home() / ".GlobalProtect"
CONFIG = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / APP / "config.json"
IFACE = "gpd0"            # the interface currently carrying the VPN (updated as we look)
OFFICIAL_IFACE = "gpd0"
OC_IFACE = "gpoc0"         # tunnel made by the built-in (openconnect) engine
HELPER = "/usr/local/libexec/omarchy-gp-helper"
OC_PIDFILE = Path("/run/omarchy-gp-openconnect.pid")
OC_LOG = Path("/run/omarchy-gp-openconnect.log")
CONNECT_TIMEOUT = 75
SERVICE_LOG = Path(GP_DIR) / "PanGPS.log"
PANEL_WIDTH = 320
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
HOST = re.compile(r"[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?")
DEVNULL = subprocess.DEVNULL


def run(cmd, timeout=15):
    try:
        out = subprocess.run(cmd, stdin=DEVNULL, capture_output=True, text=True, timeout=timeout).stdout
    except (subprocess.SubprocessError, OSError):
        return ""
    return ANSI.sub("", out)


def quiet(cmd):
    try:
        subprocess.run(cmd, stdin=DEVNULL, stdout=DEVNULL, stderr=DEVNULL, timeout=10)
    except (subprocess.SubprocessError, OSError):
        pass


def iface_state():
    """(is_up, ipv4) for whichever tunnel interface is up."""
    global IFACE
    for line in run(["ip", "-br", "a"], 5).splitlines():
        parts = line.split()
        if len(parts) < 2 or parts[0] not in (OC_IFACE, OFFICIAL_IFACE):
            continue
        # tun devices report UNKNOWN rather than UP once they carry an address
        if parts[1] == "UP" or (parts[0] == OC_IFACE and parts[1] == "UNKNOWN" and len(parts) > 2):
            IFACE = parts[0]
            return True, (parts[2].split("/")[0] if len(parts) > 2 else "")
    return False, ""


def vpn_engine():
    """'openconnect' when its helper is set up (or forced in config), else 'official'."""
    choice = load_config().get("engine", "auto")
    if choice in ("openconnect", "official"):
        return choice
    return "openconnect" if shutil.which("openconnect") else "official"


def helper_ready():
    return os.access(HELPER, os.X_OK)


def keyring(action, portal, username, secret=None):
    """Store or look up the VPN password in the system keyring (never on disk in plain text)."""
    if not shutil.which("secret-tool"):
        return ""
    attrs = ["service", APP, "account", f"{username}@{portal}"]
    try:
        if action == "store":
            subprocess.run(["secret-tool", "store", "--label", f"VPN password ({username}@{portal})"] + attrs,
                           input=secret, text=True, stdout=DEVNULL, stderr=DEVNULL, timeout=20)
            return ""
        out = subprocess.run(["secret-tool", "lookup"] + attrs, stdin=DEVNULL, capture_output=True,
                             text=True, timeout=20)
        return out.stdout.rstrip("\n") if out.returncode == 0 else ""
    except (subprocess.SubprocessError, OSError):
        return ""


def ui_running():
    return subprocess.run(["pgrep", "-x", "PanGPUI"], stdout=DEVNULL).returncode == 0


def counter(name):
    try:
        return int(Path(f"/sys/class/net/{IFACE}/statistics/{name}").read_text())
    except (OSError, ValueError):
        return 0


def human_bytes(n):
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1000 or unit == "GB":
            return f"{n:.0f} {unit}" if unit in ("B", "KB") or n >= 100 else f"{n:.1f} {unit}"
        n /= 1000


def human_time(s):
    s = int(s)
    if s < 60:
        return f"{s} s"
    if s < 3600:
        return f"{s // 60} min"
    return f"{s // 3600} h {s % 3600 // 60} min"


def log_size():
    try:
        return SERVICE_LOG.stat().st_size
    except OSError:
        return 0


def log_since(offset):
    """Text the VPN service has logged since `offset` (handles log rotation)."""
    try:
        with open(SERVICE_LOG, "rb") as f:
            if SERVICE_LOG.stat().st_size >= offset:
                f.seek(offset)
            return f.read().decode(errors="ignore")
    except OSError:
        return ""


def load_config():
    try:
        cfg = json.loads(CONFIG.read_text())
        return cfg if isinstance(cfg, dict) else {}
    except (OSError, ValueError):
        return {}


def save_config(portal, username):
    """Remember the portal and username. The password is never written here."""
    try:
        CONFIG.parent.mkdir(parents=True, exist_ok=True)
        cfg = load_config()
        cfg.update(portal=portal, username=username)
        CONFIG.write_text(json.dumps(cfg, indent=2) + "\n")
    except OSError:
        pass


def official_account():
    """(portal, username) last used by the official client, if any."""
    try:
        xml = (GP_HOME / "pangpa.xml").read_text()
    except OSError:
        return "", ""
    portal = re.search(r"<LastUrl>([A-Za-z0-9.-]+)</LastUrl>", xml)
    portal = portal.group(1) if portal else ""
    user = re.search(r"<Settings\\" + re.escape(portal) + r">.*?<username>([^<]+)</username>", xml, re.S) if portal else None
    return portal, (user.group(1) if user else "")


def account():
    cfg = load_config()
    o_portal, o_user = official_account()
    return cfg.get("portal") or o_portal, cfg.get("username") or o_user


def route_table():
    """IPv4 routes as (network, device), longest prefix first."""
    routes = []
    try:
        for r in json.loads(run(["ip", "-j", "-4", "route", "show"], 5) or "[]"):
            dst = "0.0.0.0/0" if r.get("dst") == "default" else r.get("dst", "")
            try:
                routes.append((ipaddress.ip_network(dst, strict=False), r.get("dev", "")))
            except ValueError:
                pass
    except ValueError:
        pass
    routes.sort(key=lambda x: x[0].prefixlen, reverse=True)
    return routes


def via_vpn(ip, routes):
    try:
        addr = ipaddress.ip_address(ip)
    except ValueError:
        return False
    if addr.version != 4:
        return False
    for net, dev in routes:
        if addr in net:
            return dev == IFACE
    return False


PEER = re.compile(r"^\[?(?:::ffff:)?([0-9a-fA-F:.]+)\]?:(\d+)$")


def live_connections():
    """Established TCP connections grouped by app and destination."""
    routes = route_table()
    groups, vpn_n, direct_n = {}, 0, 0
    for line in run(["ss", "-HtnpiO", "state", "established"], 8).splitlines():
        tok = line.split()
        if len(tok) < 4:
            continue
        m = PEER.match(tok[3])
        if not m:
            continue
        ip = m.group(1)
        try:
            if ipaddress.ip_address(ip).is_loopback:
                continue
        except ValueError:
            continue
        app = re.search(r'users:\(\("([^"]+)"', line)
        sent = re.search(r"bytes_sent:(\d+)", line)
        recv = re.search(r"bytes_received:(\d+)", line)
        vpn = via_vpn(ip, routes)
        vpn_n, direct_n = vpn_n + vpn, direct_n + (not vpn)
        g = groups.setdefault((app.group(1) if app else "Other", ip, vpn), [0, 0])
        g[0] += (int(sent.group(1)) if sent else 0) + (int(recv.group(1)) if recv else 0)
        g[1] += 1
    rows = [
        {"app": a, "dest": ip, "vpn": vpn, "data": human_bytes(b), "count": c}
        for (a, ip, vpn), (b, c) in groups.items()
    ]
    # A stable order, so rows do not jump around as byte counts change.
    rows.sort(key=lambda r: (not r["vpn"], r["app"].lower(), r["dest"]))
    return rows[:300], vpn_n, direct_n


def dns_cache():
    """Read the local resolver cache: ({ip: site name}, lookups_went_via_vpn).

    This only reads what the machine already looked up. It sends no queries, so
    it cannot reveal anything new to any DNS server.
    """
    names, alias, via_vpn_scope, scope = {}, {}, False, ""
    # Never let this raise an admin prompt: go through the root helper when it
    # supports it, otherwise ask without prompting (which may return nothing).
    text = run(["sudo", "-n", HELPER, "names"], 5) if helper_ready() else ""
    if "Scope " not in text:
        text = run(["resolvectl", "--no-ask-password", "show-cache"], 5)
    for line in text.splitlines():
        if line.startswith("Scope "):
            m = re.search(r"ifname=(\S+)", line)
            scope = m.group(1) if m else ""
            continue
        f = line.split()
        if len(f) < 4 or f[1] != "IN":
            continue
        host = f[0].rstrip(".")
        if f[2] in ("A", "AAAA"):
            names[f[3]] = host
            via_vpn_scope = via_vpn_scope or scope == IFACE
        elif f[2] == "CNAME":
            alias[f[3].rstrip(".")] = host
    for ip, host in names.items():  # walk CNAME chains back to the name that was asked for
        for _ in range(8):
            if host not in alias:
                break
            host = alias[host]
        names[ip] = host
    return names, via_vpn_scope


def waybar_status():
    up, ip = iface_state()
    portal, _ = account()
    state = "connected" if up else "disconnected"
    tip = f"GlobalProtect: connected\n{portal}\n{ip}" if up else "GlobalProtect: not connected"
    print(json.dumps({"text": "VPN", "alt": state, "class": state, "tooltip": tip}))
    return 0


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "toggle"
    if cmd in ("-h", "--help", "help"):
        print(__doc__.strip())
        return 0
    if cmd in ("-V", "--version"):
        print(APP, VERSION)
        return 0
    if cmd == "status":
        return waybar_status()
    if cmd not in ("toggle", "connect", "disconnect", "traffic", "account"):
        print(f"{APP}: unknown command '{cmd}'. Try: {APP} --help", file=sys.stderr)
        return 2
    return run_panel(cmd)


def run_panel(cmd):
    from PySide6.QtCore import Property, QObject, QUrl, Signal, Slot
    from PySide6.QtGui import QDesktopServices, QFont, QFontDatabase, QGuiApplication
    from PySide6.QtNetwork import QLocalServer, QLocalSocket
    from PySide6.QtQml import QQmlApplicationEngine

    class Backend(QObject):
        changed = Signal()
        trafficChanged = Signal()
        siteChecked = Signal(str, bool)
        toggleRequested = Signal()
        accountNeeded = Signal()
        windowRequested = Signal(str)
        copied = Signal()

        def __init__(self):
            super().__init__()
            portal, username = account()
            self._d = {"state": "disconnected", "portal": portal, "username": username, "gateway": "",
                       "ip": "", "uptime": "", "down": "0 B", "up": "0 B", "error": "", "needsSetup": False}
            self._t = {"connections": [], "vpnCount": 0, "directCount": 0, "dns": "", "ready": False,
                       "dnsViaVpn": False}
            self._busy = None      # None | "connecting" | "disconnecting"
            self._cancel = False
            self._error = ""
            self._uptime = None    # (seconds, monotonic stamp)
            self._details_at = 0.0
            self._was_up = None
            self._traffic_on = False
            self._names = {}
            self._asked = set()
            self._lock = threading.Lock()
            threading.Thread(target=self._loop, args=(self._refresh, 2), daemon=True).start()
            threading.Thread(target=self._loop, args=(self._refresh_traffic, 2), daemon=True).start()

        # ---- properties -------------------------------------------------
        state = Property(str, lambda s: s._d["state"], notify=changed)
        portal = Property(str, lambda s: s._d["portal"], notify=changed)
        username = Property(str, lambda s: s._d["username"], notify=changed)
        gateway = Property(str, lambda s: s._d["gateway"], notify=changed)
        ip = Property(str, lambda s: s._d["ip"], notify=changed)
        uptime = Property(str, lambda s: s._d["uptime"], notify=changed)
        down = Property(str, lambda s: s._d["down"], notify=changed)
        up = Property(str, lambda s: s._d["up"], notify=changed)
        error = Property(str, lambda s: s._d["error"], notify=changed)
        needsSetup = Property(bool, lambda s: s._d["needsSetup"], notify=changed)
        connections = Property("QVariantList", lambda s: s._t["connections"], notify=trafficChanged)
        vpnCount = Property(int, lambda s: s._t["vpnCount"], notify=trafficChanged)
        directCount = Property(int, lambda s: s._t["directCount"], notify=trafficChanged)
        dns = Property(str, lambda s: s._t["dns"], notify=trafficChanged)
        dnsViaVpn = Property(bool, lambda s: s._t["dnsViaVpn"], notify=trafficChanged)
        trafficReady = Property(bool, lambda s: s._t["ready"], notify=trafficChanged)

        # ---- polling ----------------------------------------------------
        @staticmethod
        def _loop(fn, every):
            while True:
                try:
                    fn()
                except Exception as exc:  # keep the panel alive whatever happens
                    print("refresh failed:", exc, file=sys.stderr)
                time.sleep(every)

        def _refresh(self):
            with self._lock:
                up, ip = iface_state()
                d = dict(self._d)
                d["portal"], d["username"] = account()
                if up:
                    self._error = ""
                    d["ip"] = ip
                    d["down"], d["up"] = human_bytes(counter("rx_bytes")), human_bytes(counter("tx_bytes"))
                    now = time.monotonic()
                    if IFACE == OC_IFACE:
                        try:
                            self._uptime = (time.time() - OC_PIDFILE.stat().st_mtime, now)
                        except OSError:
                            pass
                        d["gateway"] = d["portal"]
                    elif not self._busy and now - self._details_at > 15 and not ui_running():
                        self._details_at = now
                        det = run(["globalprotect", "show", "--details"], 6)
                        m = re.search(r"Uptime\(sec\):\s*(\d+)", det)
                        g = re.search(r"Gateway Name:\s*(\S+)", det)
                        if m:
                            self._uptime = (int(m.group(1)), now)
                        if g:
                            d["gateway"] = g.group(1)
                    d["uptime"] = human_time(self._uptime[0] + now - self._uptime[1]) if self._uptime else ""
                else:
                    self._uptime, self._details_at = None, 0.0
                    d["ip"], d["uptime"], d["gateway"] = "", "", ""
                if self._was_up and not up and not self._busy:
                    quiet(["notify-send", "-a", "GlobalProtect", "-t", "6000", "VPN disconnected",
                           "The tunnel went down. Open the panel to reconnect."])
                if not self._busy:
                    self._was_up = up
                if self._busy:
                    d["state"] = self._busy
                elif up:
                    d["state"] = "connected"
                else:
                    d["state"] = "error" if self._error else "disconnected"
                d["error"] = self._error
                d["needsSetup"] = vpn_engine() == "openconnect" and not helper_ready()
                if d != self._d:
                    self._d = d
                    self.changed.emit()

        def _refresh_traffic(self):
            if not self._traffic_on:
                return
            rows, vpn_n, direct_n = live_connections()
            names, dns_via_vpn = dns_cache()
            if len(self._names) > 5000:
                self._names.clear()
            self._names.update(names)  # cache entries expire; remember them while we run
            for r in rows:
                r["name"] = self._names.get(r["dest"], "")
                if not r["name"] and r["vpn"]:
                    self._name_internal(r["dest"])
            # Destination first: VPN rows on top, then named sites, then bare addresses.
            rows.sort(key=lambda r: (not r["vpn"], not r["name"], r["name"] or r["dest"], r["app"].lower()))
            dns = run(["resolvectl", "dns", IFACE], 5).split(":", 1)
            t = {"connections": rows, "vpnCount": vpn_n, "directCount": direct_n, "ready": True,
                 "dns": dns[1].strip() if iface_state()[0] and len(dns) > 1 else "",
                 "dnsViaVpn": dns_via_vpn}
            if t != self._t:
                self._t = t
                self.trafficChanged.emit()

        def _name_internal(self, ip):
            """Reverse-look-up an address that already goes through the VPN. The
            question goes to the organisation's DNS, which sees that traffic anyway.
            Addresses that go straight to the internet are never looked up."""
            if ip in self._asked:
                return
            self._asked.add(ip)

            def work():
                try:
                    self._names[ip] = socket.gethostbyaddr(ip)[0].rstrip(".")
                except OSError:
                    pass
            threading.Thread(target=work, daemon=True).start()

        # ---- official client helpers -----------------------------------
        def _kill_ui(self):
            subprocess.run(["pkill", "-x", "PanGPUI"], stdout=DEVNULL)
            for _ in range(10):
                if not ui_running():
                    return
                time.sleep(0.5)
            subprocess.run(["pkill", "-9", "-x", "PanGPUI"], stdout=DEVNULL)
            time.sleep(1)

        def _start_ui(self):
            env = dict(os.environ, QT_QPA_PLATFORM="wayland")
            try:
                subprocess.Popen(["./PanGPUI"], cwd=GP_DIR, env=env, stdin=DEVNULL, stdout=DEVNULL,
                                 stderr=DEVNULL, start_new_session=True)
            except OSError:
                pass

        def _tend_ui(self, seen):
            """While the official client finishes a connection: keep its windows on
            a hidden workspace, and dismiss its agreement page, which otherwise
            blocks the connection until someone closes it."""
            if not shutil.which("hyprctl"):
                return
            try:
                clients = json.loads(run(["hyprctl", "clients", "-j"], 5) or "[]")
            except ValueError:
                return
            now = time.monotonic()
            for c in clients:
                if c.get("class") != "PanGPUI":
                    continue
                addr = c.get("address", "")
                if c.get("workspace", {}).get("name") != "special:gpbg":
                    quiet(["hyprctl", "dispatch", "movetoworkspacesilent", f"special:gpbg,address:{addr}"])
                if c.get("title", "").startswith("Welcome to GlobalProtect"):
                    if now - seen.setdefault(addr, now) > 1.5:  # give the page a moment to load
                        quiet(["hyprctl", "dispatch", "closewindow", f"address:{addr}"])

        # ---- connect ----------------------------------------------------
        def _do_connect(self, portal, username, password):
            """Ask the agent to connect, answer its sign-in prompts, then let the
            official UI (hidden) finish the gateway step, which it only does with
            its own UI attached."""
            proc = master = None
            try:
                if iface_state()[0]:
                    return
                if vpn_engine() == "openconnect":
                    self._connect_openconnect(portal, username, password)
                    return
                if not shutil.which("globalprotect"):
                    self._error = "The official GlobalProtect client is not installed."
                    return
                if not portal:
                    self._error = "No portal is set. Add your account in Settings."
                    self.accountNeeded.emit()
                    return
                self._kill_ui()
                log_at, nudge_at, seen_windows = log_size(), 0.0, {}
                master, slave = pty.openpty()
                args = ["globalprotect", "connect", "--portal", portal]
                if username:
                    args += ["--username", username]
                proc = subprocess.Popen(args, stdin=slave, stdout=slave, stderr=slave, start_new_session=True)
                os.close(slave)

                text, seen = "", 0
                prompted = pass_sent = ui_started = False
                pass_at, t0 = 0.0, time.monotonic()
                while time.monotonic() - t0 < CONNECT_TIMEOUT and not self._cancel:
                    if iface_state()[0]:
                        break
                    if not ui_started:
                        ready, _, _ = select.select([master], [], [], 0.5)
                        if ready:
                            try:
                                text += ANSI.sub("", os.read(master, 4096).decode(errors="ignore"))
                            except OSError:
                                pass
                        fresh = text[seen:]
                        if pass_sent and re.search(r"authentication failed|invalid (username|password)", fresh, re.I):
                            self._error = "Sign-in was rejected. Check the username and password."
                            self.accountNeeded.emit()
                            return
                        if re.search(r"username[^\n]*:\s*$", fresh, re.I):
                            prompted, seen = True, len(text)
                            os.write(master, (username + "\n").encode())
                        elif re.search(r"password[^\n]*:\s*$", fresh, re.I):
                            prompted, seen = True, len(text)
                            if not password or pass_sent:
                                self._error = ("Sign-in was rejected. Check the username and password."
                                               if pass_sent else "This portal needs your password. Add it in Settings.")
                                self.accountNeeded.emit()
                                return
                            os.write(master, (password + "\n").encode())
                            pass_sent, pass_at = True, time.monotonic()
                        # Portal sign-in takes around ten seconds. Only once it is
                        # done can the official UI finish the gateway step.
                        signed_in = "portal status is Connected" in log_since(log_at)
                        waiting_on_us = prompted and not pass_sent
                        if signed_in or (not waiting_on_us and time.monotonic() - max(t0, pass_at) > 25):
                            self._stop(proc)
                            self._start_ui()
                            ui_started = True
                    else:
                        if time.monotonic() - nudge_at > 5:
                            nudge_at = time.monotonic()
                            quiet(["globalprotect", "launch-ui"])
                        self._tend_ui(seen_windows)
                        time.sleep(0.5)

                if self._cancel:
                    self._kill_ui()
                    run(["globalprotect", "disconnect"], 30)
                elif iface_state()[0]:
                    save_config(portal, username)
                    time.sleep(3)
                    self._kill_ui()  # the tunnel is held by the service, not the window
                else:
                    self._error = f"The VPN did not come up within {CONNECT_TIMEOUT} seconds."
                    self._kill_ui()
            except OSError as exc:
                self._error = f"Could not start the GlobalProtect client ({exc.strerror})."
            finally:
                self._stop(proc)
                if master is not None:
                    try:
                        os.close(master)
                    except OSError:
                        pass
                self._busy = None
                self._refresh()

        def _connect_openconnect(self, portal, username, password):
            """Built-in engine: sign in unprivileged, then hand the session to the
            root helper to bring the tunnel up. No official client involved."""
            typed = bool(password)
            if not helper_ready():
                self._error = "One-time setup is needed before the first connect."
                return
            if not portal or not username:
                self._error = "Add your account in Settings first."
                self.accountNeeded.emit()
                return
            password = password or keyring("lookup", portal, username)
            if not password:
                self._error = "Sign in once in Settings, Account. After that it is one click."
                self.accountNeeded.emit()
                return
            try:
                auth = subprocess.run(
                    ["openconnect", "--protocol=gp", "--authenticate", "--non-inter",
                     "--user", username, "--passwd-on-stdin", portal],
                    input=password + "\n", capture_output=True, text=True, timeout=45)
            except subprocess.TimeoutExpired:
                self._error = "The portal did not answer in time. Check your internet connection."
                return
            except OSError:
                self._error = "openconnect is not installed."
                return
            got = dict(re.findall(r"^([A-Z_]+)='?([^'\n]*)'?$", auth.stdout, re.M))
            if auth.returncode != 0 or not got.get("COOKIE"):
                err = auth.stderr.strip().splitlines()
                if re.search(r"auth|login|password|credential|invalid", auth.stderr, re.I):
                    self._error = "Sign-in was rejected. Check the username and password."
                    self.accountNeeded.emit()
                else:
                    self._error = "Could not reach the portal. " + (err[-1][:120] if err else "")
                return
            if typed:
                keyring("store", portal, username, password)
            save_config(portal, username)
            if self._cancel:
                return
            session = "\n".join([got.get("CONNECT_URL") or "https://" + got.get("HOST", portal),
                                 got.get("FINGERPRINT", ""), got.get("RESOLVE", ""), got["COOKIE"]]) + "\n"
            try:
                up = subprocess.run(["sudo", "-n", HELPER, "up"], input=session, capture_output=True,
                                    text=True, timeout=45)
            except (subprocess.SubprocessError, OSError):
                up = None
            for _ in range(40):
                if iface_state()[0] or self._cancel:
                    break
                time.sleep(0.5)
            if self._cancel:
                quiet(["sudo", "-n", HELPER, "down"])
            elif not iface_state()[0]:
                detail = ""
                try:
                    detail = OC_LOG.read_text().strip().splitlines()[-1][:120]
                except (OSError, IndexError):
                    detail = (up.stderr.strip()[:120] if up else "")
                self._error = "The tunnel did not come up. " + detail

        @staticmethod
        def _stop(proc):
            if proc and proc.poll() is None:
                try:
                    os.killpg(proc.pid, signal.SIGTERM)
                    proc.wait(3)
                except (OSError, subprocess.SubprocessError):
                    pass

        def _do_disconnect(self, then=None):
            try:
                iface_state()
                if IFACE == OC_IFACE:
                    out = run(["sudo", "-n", HELPER, "down"], 20)
                else:
                    self._kill_ui()
                    out = run(["globalprotect", "disconnect"], 40)
                time.sleep(1)
                if iface_state()[0]:
                    self._error = "Disconnect did not complete. " + out.strip()[-120:]
                    then = None
            finally:
                if then:
                    self._busy = "connecting"
                    self._refresh()
                    then()
                else:
                    self._busy = None
                    self._refresh()

        def _start(self, kind, target, *args):
            if self._busy:
                return
            self._busy, self._cancel, self._error = kind, False, ""
            threading.Thread(target=target, args=args, daemon=True).start()
            threading.Thread(target=self._refresh, daemon=True).start()

        # ---- slots ------------------------------------------------------
        @Slot()
        def connectVpn(self):
            portal, username = account()
            self._start("connecting", self._do_connect, portal, username, "")

        @Slot()
        def disconnectVpn(self):
            self._start("disconnecting", self._do_disconnect)

        @Slot(str, str, str, result=str)
        def signIn(self, portal, username, password):
            """Connect with a new or changed account. Returns "" or what to fix."""
            portal = re.sub(r"^[a-z]+://", "", portal.strip().lower()).split("/")[0]
            username = username.strip()
            if not HOST.fullmatch(portal):
                return "Enter the portal address, like vpn.example.com."
            if not username or re.search(r"\s", username):
                return "Enter your username."
            if not password:
                return "Enter your password."
            if self._busy:
                return "Wait for the current action to finish."
            connect = lambda: self._do_connect(portal, username, password)
            if iface_state()[0]:
                self._start("disconnecting", self._do_disconnect, connect)
            else:
                self._start("connecting", connect)
            return ""

        @Slot()
        def setupEngine(self):
            """Run the one-time setup with a graphical admin prompt (no terminal needed)."""
            def work():
                try:
                    done = subprocess.run(["pkexec", "sh", str(HERE / "setup-engine.sh")], stdin=DEVNULL,
                                          capture_output=True, text=True, timeout=180)
                    ok = done.returncode == 0 and helper_ready()
                    self._error = "" if ok else ("Setup did not finish. " + (done.stderr.strip().splitlines() or [""])[-1][:120])
                except (subprocess.SubprocessError, OSError):
                    ok, self._error = False, "Setup did not finish."
                self._busy = None
                self._refresh()
                if ok:
                    portal, username = account()
                    if portal and username and keyring("lookup", portal, username):
                        self.connectVpn()
                    else:
                        self.accountNeeded.emit()
            if self._busy:
                return
            self._busy, self._error = "connecting", ""
            threading.Thread(target=work, daemon=True).start()
            threading.Thread(target=self._refresh, daemon=True).start()

        @Slot()
        def cancel(self):
            self._cancel = True

        @Slot()
        def openOfficial(self):
            def work():
                if not ui_running():
                    self._start_ui()
                hypr = shutil.which("hyprctl")
                for _ in range(20):
                    time.sleep(1)
                    if hypr and '"class": "PanGPUI"' in run(["hyprctl", "clients", "-j"], 5):
                        try:
                            ws = json.loads(run(["hyprctl", "activeworkspace", "-j"], 5))["id"]
                            quiet(["hyprctl", "dispatch", "movetoworkspace", f"{ws},class:^(PanGPUI)$"])
                        except (ValueError, KeyError):
                            pass
                        return
                    quiet(["globalprotect", "launch-ui"])
            threading.Thread(target=work, daemon=True).start()

        @Slot()
        def openTerms(self):
            page = GP_HOME / "GPWelcome.html"
            if page.exists():
                QDesktopServices.openUrl(QUrl.fromLocalFile(str(page)))

        @Slot(result=bool)
        def hasTerms(self):
            return (GP_HOME / "GPWelcome.html").exists()

        @Slot()
        def place(self):
            """Dock the panel under the bar, top right of the focused monitor."""
            def work():
                time.sleep(0.12)
                try:
                    mon = next(m for m in json.loads(run(["hyprctl", "monitors", "-j"], 5)) if m.get("focused"))
                    x = mon["x"] + int(mon["width"] / mon["scale"]) - PANEL_WIDTH - 10 - mon["reserved"][2]
                    y = mon["y"] + mon["reserved"][1] + 8
                    quiet(["hyprctl", "dispatch", "movewindowpixel", f"exact {x} {y},title:^(GlobalProtect)$"])
                except (StopIteration, ValueError, KeyError, IndexError, TypeError):
                    pass
            if shutil.which("hyprctl"):
                threading.Thread(target=work, daemon=True).start()

        @Slot()
        def copyIp(self):
            if self._d["ip"]:
                QGuiApplication.clipboard().setText(self._d["ip"])
                self.copied.emit()

        @Slot(bool)
        def setTrafficVisible(self, on):
            self._traffic_on = on
            if on:
                threading.Thread(target=self._refresh_traffic, daemon=True).start()

        @Slot(str)
        def checkSite(self, text):
            host = re.sub(r"^[a-z]+://", "", text.strip().lower()).split("/")[0].split(":")[0]
            if not HOST.fullmatch(host or ""):
                self.siteChecked.emit("Enter a site name, like youtube.com", False)
                return

            def work():
                try:
                    ips = sorted({a[4][0] for a in socket.getaddrinfo(host, None, socket.AF_INET)})
                except OSError:
                    self.siteChecked.emit(f"Could not find {host}", False)
                    return
                routes = route_table()
                vpn = any(via_vpn(ip, routes) for ip in ips)
                self.siteChecked.emit("Goes through the VPN" if vpn else "Direct, not through the VPN", vpn)

            threading.Thread(target=work, daemon=True).start()

        def command(self, name):
            if name == "connect":
                self.connectVpn()
            elif name == "disconnect":
                self.disconnectVpn()
            elif name in ("traffic", "account"):
                self.windowRequested.emit(name)
            else:
                self.toggleRequested.emit()

    app = QGuiApplication(sys.argv[:1])
    app.setDesktopFileName(APP)
    app.setQuitOnLastWindowClosed(False)
    families = QFontDatabase.families()
    font = next((f for f in ("Google Sans Flex", "Google Sans", "Inter", "Roboto") if f in families), "")
    if font:
        app.setFont(QFont(font, 10))

    # Single instance: a second launch passes its command to the first.
    probe = QLocalSocket()
    probe.connectToServer(APP)
    if probe.waitForConnected(300):
        probe.write(cmd.encode())
        probe.waitForBytesWritten(500)
        probe.disconnectFromServer()
        return 0
    QLocalServer.removeServer(APP)
    server = QLocalServer()
    server.listen(APP)

    # Tell Hyprland where the panel goes before it appears, so it opens docked
    # under the bar instead of opening in the middle and then jumping.
    if shutil.which("hyprctl"):
        try:
            mon = next(m for m in json.loads(run(["hyprctl", "monitors", "-j"], 5)) if m.get("focused"))
            x = int(mon["width"] / mon["scale"]) - PANEL_WIDTH - 10 - mon["reserved"][2]
            y = mon["reserved"][1] + 8
            quiet(["hyprctl", "keyword", "windowrule",
                   f"move {x} {y}, match:class ^({APP})$, match:initial_title ^(GlobalProtect)$"])
        except (StopIteration, ValueError, KeyError, IndexError, TypeError):
            pass

    backend = Backend()

    def on_client():
        sock = server.nextPendingConnection()
        sock.waitForReadyRead(300)
        backend.command(bytes(sock.readAll()).decode(errors="ignore").strip() or "toggle")
        sock.deleteLater()

    server.newConnection.connect(on_client)
    engine = QQmlApplicationEngine()
    engine.rootContext().setContextProperty("backend", backend)
    engine.load(QUrl.fromLocalFile(str(HERE / "Main.qml")))
    if not engine.rootObjects():
        return 1
    if cmd != "toggle":
        backend.command(cmd)
    signal.signal(signal.SIGINT, signal.SIG_DFL)
    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
