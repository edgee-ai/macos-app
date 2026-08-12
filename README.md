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

`--no-quarantine` is required because the app is **ad-hoc signed, not yet
notarized** by Apple — otherwise Gatekeeper blocks a downloaded build. (Dropping
the flag becomes possible once we ship a notarized, Developer-ID-signed build.)
If it's already installed with quarantine, clear it once with
`xattr -dr com.apple.quarantine "/Applications/Edgee.app"`.

## Distribution (maintainers)

The cask (`Casks/edgee-menubar.rb`) is the canonical definition; releasing is:

1. `make dist EDGEE_BIN=/path/to/matching/edgee` — builds `dist/Edgee-<version>.zip`
   and prints the `version` + `sha256`.
2. Create a GitHub Release `v<version>` on this repo and upload the zip
   (the cask's `url` points at `…/releases/download/v<version>/Edgee-<version>.zip`).
3. Update `version` + `sha256` in `Casks/edgee-menubar.rb` from step 1's output,
   then copy it to `edgee-ai/homebrew-tap/Casks/edgee-menubar.rb`.

(A CI workflow to automate build → release → cask-bump, mirroring the CLI's
`homebrew-tap.yml`, is a natural follow-up — it needs a macOS runner and, for a
frictionless install, an Apple Developer ID cert + notarization.)

## Layout

- `Sources/EdgeeMenuBar/EdgeeMenuBarApp.swift` — `@main` app + `MenuBarExtra` scene
- `Sources/EdgeeMenuBar/MenuContentView.swift` — the dropdown UI
- `Sources/EdgeeMenuBar/EdgeeCLI.swift` — subprocess wrapper around `edgee`
- `Sources/EdgeeMenuBar/AuthStatus.swift` — decodes `edgee auth status --json`
- `Info.plist` — bundle metadata (`LSUIElement`)
- `Makefile` — build/bundle/run
