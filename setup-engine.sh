#!/bin/sh
# One-time setup for the built-in (openconnect) engine. Run with sudo:
#     sudo ./setup-engine.sh
# It installs a small root helper and lets your user run that one helper
# without a password prompt, so Connect never asks you to authenticate.
# Undo with: sudo ./setup-engine.sh --remove
set -eu

HELPER=/usr/local/libexec/omarchy-gp-helper
RULE=/etc/sudoers.d/omarchy-gp
SRC=$(cd "$(dirname "$0")" && pwd)

[ "$(id -u)" = 0 ] || { echo "Run this with sudo: sudo $0" >&2; exit 1; }

if [ "${1:-}" = "--remove" ]; then
    [ -x "$HELPER" ] && "$HELPER" down || true
    rm -f "$HELPER" "$RULE"
    echo "Removed the omarchy-gp engine helper."
    exit 0
fi

USER_NAME=${SUDO_USER:-}
# Also works when started through pkexec (the panel's "Finish setup" button).
[ -n "$USER_NAME" ] || [ -z "${PKEXEC_UID:-}" ] || USER_NAME=$(id -nu "$PKEXEC_UID")
[ -n "$USER_NAME" ] && [ "$USER_NAME" != root ] || { echo "Run this with sudo from your own account." >&2; exit 1; }
command -v openconnect >/dev/null || { echo "Install openconnect first: sudo pacman -S openconnect" >&2; exit 1; }
[ -x /etc/vpnc/vpnc-script ] || { echo "Install vpnc first (provides /etc/vpnc/vpnc-script): sudo pacman -S vpnc" >&2; exit 1; }

install -D -o root -g root -m 755 "$SRC/omarchy-gp-helper" "$HELPER"
TMP=$(mktemp)
printf '%s ALL=(root) NOPASSWD: %s\n' "$USER_NAME" "$HELPER" > "$TMP"
visudo -cf "$TMP" >/dev/null
install -o root -g root -m 440 "$TMP" "$RULE"
rm -f "$TMP"
echo "Engine helper installed for $USER_NAME."
echo "Open the panel, choose Settings > Account, and sign in once."
