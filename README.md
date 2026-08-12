# Edgee menubar app

A native macOS menubar app (SwiftUI `MenuBarExtra`) that surfaces Edgee stats
and launches agents/relay. It shells out to the `edgee` CLI and reads Edgee's
local files, so the Rust CLI stays the single source of truth.

The CLI itself lives in a separate repo ([edgee-ai/edgee](https://github.com/edgee-ai/edgee));
this app does not link it — it drives it as a subprocess and consumes its
`--json` output. `make bundle` embeds whichever `edgee` binary `EDGEE_BIN`
resolves to (the one on your `PATH` by default).

## Requirements

- macOS 14+
- Xcode / Swift toolchain (`swift`, `xcodebuild`)
- The `edgee` CLI installed (found on `PATH`, in `~/.local/bin`, or set `EDGEE_BIN`)

## Build & run

```bash
make run        # build, bundle into Edgee.app, and launch it
make build      # just `swift build -c release`
make test       # run the unit tests (swift test)
make bundle     # produce Edgee.app without launching
make dist       # package the signed bundle into dist/Edgee-<version>.zip (+ sha256)
make clean
```

`make run` produces `Edgee.app` (marked `LSUIElement`, so it lives only in the
menubar — no Dock icon) and opens it. Click the menubar icon for the dropdown.
The bundle's version is stamped from the embedded `edgee` CLI at `make bundle`
time.

## Install (Homebrew cask)

Once a release is published, end users install via the tap:

```bash
brew install --cask --no-quarantine edgee-ai/tap/edgee-menubar
```

This installs `Edgee.app` **and** puts the bundled `edgee` CLI on your `PATH`
(symlinked into the Homebrew prefix's `bin`), so the app and the command line
tool always stay in lockstep. It therefore conflicts with the standalone `edgee`
formula — install one or the other (`brew unlink edgee` first if needed).

`--no-quarantine` is required because the app is **ad-hoc signed, not yet
notarized** by Apple — otherwise Gatekeeper blocks a downloaded build. (Dropping
the flag becomes possible once we ship a notarized, Developer-ID-signed build.)
If it's already installed with quarantine, clear it once with
`xattr -dr com.apple.quarantine "/Applications/Edgee.app"`.

## Distribution (maintainers)

Releases are automated via `.github/workflows/`, mirroring the CLI's setup:

1. Make sure the edgee CLI release `vX.Y.Z` exists — its arm64 darwin binary is
   what the app embeds, so **the app version tracks the CLI version**.
2. Tag the app to match and push: `git tag vX.Y.Z && git push origin vX.Y.Z`.
   `release.yml` (macOS runner) builds an arm64 `Edgee.app`, packages
   `Edgee-X.Y.Z.zip` (+ sha256), and opens a **draft** GitHub Release.
3. Review and **publish** the draft. That fires `homebrew-cask.yml`, which pins
   `edgee-ai/homebrew-tap/Casks/edgee-menubar.rb` to the new version + checksum.

Required secret: `HOMEBREW_TAP_TOKEN` (read on `edgee-ai/edgee`, write on
`edgee-ai/homebrew-tap`). Manual fallback: `make dist EDGEE_BIN=<matching edgee>`,
upload the zip to a release, paste `version`/`sha256` into the cask, copy to the tap.

Currently an **arm64-only** build (Apple Silicon). Universal (arm64 + x86_64 via
`lipo`) is a follow-up.

### Apple signing & notarization (planned)

The app ships **ad-hoc signed** today (hence the cask's `--no-quarantine`). The
pipeline is already wired for Developer-ID signing + notarization — it stays
dormant until these secrets exist, at which point `release.yml` signs with a
hardened runtime, notarizes, and staples automatically (no code change):

- `APPLE_SIGN_IDENTITY` — e.g. `Developer ID Application: Edgee, Inc. (TEAMID)`
- `APPLE_CERT_P12` (base64 of the exported `.p12`) + `APPLE_CERT_PASSWORD`
- `APPLE_API_KEY_ID`, `APPLE_API_ISSUER`, `APPLE_API_KEY_P8` (base64 App Store
  Connect API key, for `notarytool`)

Setup: enroll in the Apple Developer Program, create a *Developer ID Application*
cert (export `.p12`) and an App Store Connect API key, add the secrets above,
then drop `--no-quarantine` (and the arch caveat) from the cask once builds are
notarized. Locally: `make dist CODESIGN_IDENTITY="Developer ID Application: … (TEAMID)"`.

## Layout

- `Sources/EdgeeMenuBar/EdgeeMenuBarApp.swift` — `@main` app + `MenuBarExtra` scene
- `Sources/EdgeeMenuBar/MenuContentView.swift` — the dropdown UI
- `Sources/EdgeeMenuBar/EdgeeCLI.swift` — subprocess wrapper around `edgee`
- `Sources/EdgeeMenuBar/AuthStatus.swift` — decodes `edgee auth status --json`
- `Info.plist` — bundle metadata (`LSUIElement`)
- `Makefile` — build/bundle/run
