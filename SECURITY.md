# Security

omarchy-gp installs a root helper and handles a VPN password, so security
reports are taken seriously.

## Reporting a vulnerability

Please do not open a public issue. Use GitHub's private reporting instead:
**Security** tab, then **Report a vulnerability**
(https://github.com/Dagmawi-M/omarchy-gp/security/advisories/new).

Include what you found, how to reproduce it, and the version
(`omarchy-gp --version`). You should get a reply within a week.

## What to know about the design

- The VPN password is stored in the system keyring through `secret-tool`. It
  is never written to a file and never passed to the root helper.
- Sign-in runs as your own user. Only the resulting session is handed to the
  helper.
- `/usr/local/libexec/omarchy-gp-helper` can be run as root without a password
  by the user who ran `setup-engine.sh`. It accepts three actions: bring the
  tunnel up, take it down, and print the local DNS cache. A user who can run it
  can point the tunnel at a VPN server of their choice, which is the same
  trust any VPN client gives its user.
- Only the latest release is supported with fixes.
