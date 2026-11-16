#!/bin/sh
# Removes omarchy-gp. Your VPN, the official client and your waybar config are left alone.
set -eu
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
pkill -f "python3 .*/omarchy-gp( |\$)" 2>/dev/null || true
rm -rf "$DATA/omarchy-gp"
rm -f "$HOME/.local/bin/omarchy-gp" "$DATA/applications/omarchy-gp.desktop" \
    "${XDG_CONFIG_HOME:-$HOME/.config}/autostart/omarchy-gp.desktop"
echo "Removed omarchy-gp."
echo "Saved portal and username remain in ${XDG_CONFIG_HOME:-$HOME/.config}/omarchy-gp (delete it if you want)."
echo "If you added it to waybar, remove that module from your waybar config."
