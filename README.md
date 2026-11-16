# omarchy-gp

A small, modern panel for the official Palo Alto GlobalProtect VPN client on
Omarchy / Arch with Hyprland.

- One-click connect and disconnect
- Status, gateway, IP address and data counters
- A traffic window that shows which connections go through the VPN and which
  go straight to the internet, with a "check a site" box
- A dashboard with time connected and data used per day
- An account window for adding or changing the portal, username and password

It can connect in two ways:

- **Built-in engine (recommended):** uses `openconnect`. No official client
  needed, one-click connect, password kept in your system keyring. Works with
  portals that use a username and password.
- **Official client:** if the official GlobalProtect client is installed and
  the built-in engine is not set up, the panel shows its status and can
  disconnect it. Connecting through it is unreliable; use its own window.

## Requirements

- `pyside6`, `openconnect` and `vpnc` (`sudo pacman -S pyside6 openconnect vpnc`)
- `libsecret` and a running keyring such as `gnome-keyring` (to remember the
  password)
- `iproute2` (`ip`, `ss`) and `procps-ng` (`pgrep`), present on any Arch install
- Optional: Hyprland (panel docking, hiding the official window), `libnotify`
  (drop alerts), `systemd-resolved` (DNS note in the traffic window)

## Install

```sh
git clone https://github.com/Dagmawi-M/omarchy-gp.git
cd omarchy-gp
./install.sh
sudo ./setup-engine.sh
```

`install.sh` copies the app to `~/.local/share/omarchy-gp` and adds the
`omarchy-gp` command to `~/.local/bin`; it needs no root.

`setup-engine.sh` is the one step that needs `sudo`. It installs a small root
helper (`/usr/local/libexec/omarchy-gp-helper`) that can only bring the VPN
tunnel up or down, and lets your user run that helper without a password
prompt. Your VPN password never reaches the helper.

To remove everything: `./uninstall.sh` and `sudo ./setup-engine.sh --remove`.

## Use

| Command | What it does |
|---|---|
| `omarchy-gp` | Show or hide the panel |
| `omarchy-gp connect` | Connect with the saved account |
| `omarchy-gp disconnect` | Disconnect |
| `omarchy-gp traffic` | Open the traffic window |
| `omarchy-gp dashboard` | Open the usage dashboard |
| `omarchy-gp status` | Print JSON for waybar |

First time: open the settings button (top right of the panel), choose
**Account**, and enter your portal, username and password. The password is
stored in your system keyring. After that, **Connect** is one click and never
asks you to authenticate.

Esc hides a window. The panel keeps running in the background so it reopens
instantly; choose **Quit** in settings to stop it.

## Waybar

Add a module to `~/.config/waybar/config.jsonc` and list it in a `modules-*`
array:

```jsonc
"custom/omarchy-gp": {
  "exec": "omarchy-gp status",
  "return-type": "json",
  "interval": 5,
  "format": "{icon}",
  "format-icons": { "connected": "󰦝", "disconnected": "󰦞" },
  "on-click": "omarchy-gp"
}
```

Optional styling in `style.css`:

```css
#custom-omarchy-gp.disconnected { opacity: 0.5; }
```

## Limits

- Web (SAML) logins and one-time codes are not handled. Use **Open official
  client** in settings for those.
- The traffic window lists TCP connections by app and IP address. It does not
  look up site names, because those lookups could themselves be sent to your
  organisation's DNS servers.
- App names are only shown for your own processes.

## Troubleshooting

- **Connect fails:** the error screen offers the official client. Connect once
  there, then try the panel again.
- **"This portal needs your password":** open **Account** in settings.
- **Nothing happens on Connect:** check the services with
  `systemctl status gpd` and `systemctl --user status gpa`.
