# Contributing

Thanks for wanting to help. Bug reports, fixes and small features are welcome.

## Reporting a problem

Open an issue and include the output of `omarchy-gp doctor`. Remove your
portal address and username from it first if you would rather not share them.

## Working on the code

```sh
git clone https://github.com/Dagmawi-M/omarchy-gp.git
cd omarchy-gp
python -m unittest discover -s tests     # run the tests
./omarchy_gp.py                           # run the panel from the source tree
./install.sh                              # install your working copy
```

- `omarchy_gp.py` holds the backend and the command line. The windows are the
  `.qml` files next to it.
- `omarchy-gp-helper` runs as root. Keep it as small as it is: it must only
  bring the tunnel up or down and read the DNS cache, and it must validate
  everything it is given. Changes to it get the closest review.
- The panel must never show an authentication prompt on its own, and must
  never look up public addresses in DNS. See "Limits" in the README for why.
- Add or update a test in `tests/` for anything that parses text or makes a
  routing decision.

## Commits and pull requests

- One change per commit. Write the subject in the imperative, under 72
  characters, with no trailing full stop: `Fix false disconnect alert`.
- Use the body to say why, and what a user would have seen before the change.
- Keep pull requests focused, and say how you tested them. If your change
  alters how connecting works, say which portal setup you tried it against
  (password only, with or without a device check).
- Update `CHANGELOG.md` under "Unreleased".

## Releases

Versions follow [Semantic Versioning](https://semver.org). The version lives
in `VERSION` at the top of `omarchy_gp.py` and is tagged as `vX.Y.Z`.
