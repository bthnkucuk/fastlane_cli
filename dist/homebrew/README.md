# dist/homebrew — draft tap layout

This directory is a draft of the future tap repo's `Formula/` directory. When
ROADMAP §0 lands (owner / repo name decided), the contents of `Formula/` will
be copied or moved into a separate `homebrew-fastlane_cli` repo under the
chosen owner — Homebrew taps are required to be standalone repos named
`homebrew-<tapname>`, so this directory cannot serve as a real tap from within
the main source repo. It exists here so the formula skeleton can be reviewed
alongside the Wave 1 release-pipeline and skills work, and so release CI
(Track D2) has a single source of truth to template URLs and SHA256 values
against before the tap repo exists.

## Dev install (from this draft)

`brew install --HEAD ./dist/homebrew/Formula/fastlane_cli.rb` is **not
supported** — Homebrew requires a full tap layout (a repo named
`homebrew-<name>` with `Formula/` at the root), and `--HEAD` requires a `head`
stanza that this skeleton intentionally omits. For local development install,
use `dart compile exe` instead:

```sh
dart pub get
dart compile exe bin/fastlane_cli.dart -o build/fastlane_cli
./build/fastlane_cli --help
```

Once the tap repo exists, end-user install will be:

```sh
brew tap <owner>/fastlane_cli
brew install fastlane_cli
```
