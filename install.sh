#!/bin/sh
# Installs omarchy-gp for the current user. No root needed.
set -eu

SRC=$(cd "$(dirname "$0")" && pwd)
DEST="${XDG_DATA_HOME:-$HOME/.local/share}/omarchy-gp"
BIN="$HOME/.local/bin"
APPS="${XDG_DATA_HOME:-$HOME/.local/share}/applications"

if ! python3 -c "import PySide6.QtQuick" 2>/dev/null; then
    echo "omarchy-gp needs PySide6. Install it first:" >&2
    echo "    sudo pacman -S pyside6" >&2
    exit 1
fi
for tool in ip ss pgrep; do
    command -v "$tool" >/dev/null || { echo "Missing required tool: $tool" >&2; exit 1; }
done

mkdir -p "$DEST" "$BIN" "$APPS"
install -m 644 "$SRC"/Main.qml "$SRC"/TrafficWindow.qml "$SRC"/AccountWindow.qml "$SRC"/StatsWindow.qml "$DEST"/
install -m 755 "$SRC"/omarchy_gp.py "$SRC"/setup-engine.sh "$SRC"/omarchy-gp-helper "$DEST"/
ln -sf "$DEST/omarchy_gp.py" "$BIN/omarchy-gp"

cat > "$APPS/omarchy-gp.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=GlobalProtect Panel
Comment=Connect, disconnect and watch VPN traffic
Exec=$BIN/omarchy-gp
Icon=network-vpn
Categories=Network;
StartupWMClass=omarchy-gp
EOF

# Start with the desktop session, in the background, so the VPN reconnects at
# login and the dashboard keeps counting. Remove this file to turn that off.
AUTO="${XDG_CONFIG_HOME:-$HOME/.config}/autostart"
mkdir -p "$AUTO"
cat > "$AUTO/omarchy-gp.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=GlobalProtect Panel
Exec=$BIN/omarchy-gp start
X-GNOME-Autostart-enabled=true
NoDisplay=true
EOF

echo "Installed omarchy-gp to $DEST"
echo "Run it with: omarchy-gp"
case ":$PATH:" in *":$BIN:"*) ;; *) echo "Note: $BIN is not on your PATH. Run $BIN/omarchy-gp instead." ;; esac
command -v openconnect >/dev/null || echo "Note: openconnect is not installed. Run: sudo pacman -S openconnect vpnc"
if [ ! -x /usr/local/libexec/omarchy-gp-helper ]; then
    echo "First connect: press 'Finish setup' in the panel and approve once,"
    echo "or run: sudo $SRC/setup-engine.sh"
fi
echo "To add it to waybar, see the README."
