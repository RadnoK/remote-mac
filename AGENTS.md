# Agent notes

## Releases are driven by tags

Pushing a `v*.*.*` tag runs `.github/workflows/release.yml`. Nothing else
publishes; never build a zip by hand for testers.

- **Stable** — `vX.Y.Z`: build, Developer ID signature, notarization, GitHub
  release, Sparkle appcast on `gh-pages`, and both casks in
  `RadnoK/homebrew-tap` (`remote-mac` and `remote-mac@beta`).
- **Beta** — `vX.Y.Z-beta.N` (any suffix after `-`): same build and
  notarization, but a GitHub *prerelease*, no appcast (Sparkle must never
  offer a beta to stable users), and only the `remote-mac@beta` cask is
  updated. Testers install it with
  `brew install --cask radnok/tap/remote-mac@beta` (conflicts with
  `remote-mac`, uninstall that first).

The tag must match `Resources/Info.plist`, or the workflow fails:

- `CFBundleShortVersionString` = the tag without `v` (`1.2.0-beta.3`).
- `CFBundleVersion` = an integer that only ever goes up, across stable and
  beta alike. Sparkle compares this number, not the version string.

Bump both in a `chore: version X.Y.Z` commit, tag that commit, push the
branch and the tag. A beta can be tagged on a feature branch.

## Before picking a version number

Releases also get cut from other machines. Always check first, and go one
above whatever is newest:

```bash
git fetch --tags origin
gh release list --limit 5
gh run list --workflow Release --limit 3   # a release may still be running
```

Don't push a tag while another Release run is in progress — both push to
the tap, and the second push can be rejected.

## Environment

- `gh` and `brew` live in `/opt/homebrew/bin`, which may not be on `PATH`.
- Tests: `swift test`. CI runs only `--filter RemoteMacCoreTests`, because
  `RemoteMacTests` needs a window server; run the full suite locally.
- `Scripts/release.sh <version>` does a release locally (needs notarization
  credentials and the Sparkle key in the keychain).
