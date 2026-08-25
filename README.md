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
`make bundle` stamps the bundle version from `APP_VERSION`, defaulting to the
embedded CLI's version, and always records that CLI's version in the plist's
`EdgeeCLIVersion`.

## Terminal for the TUI agents

Claude Code, Codex and OpenCode need a TTY, so tapping them opens a terminal
window running `edgee launch <id>`. By default that's whatever app handles
`.command` files (Terminal.app unless you changed it).

kitty users get a window in their **own running instance** instead, if kitty's
remote control is on — add to `kitty.conf`:

```conf
allow_remote_control socket-only
listen_on unix:/tmp/kitty
```

Without it the app starts a kitty of its own, isolated in `--instance-group
edgee` and set to quit with its last window. While an agent window is open that
instance is still a running kitty, so a Dock/Spotlight launch can land your own
window in it; once the last agent window closes it exits, so it can't go on
owning your windows after the session.

## Install (Homebrew cask)

Once a release is published, end users install via the tap:

```bash
brew install --cask edgee-ai/tap/edgee-menubar
xattr -dr com.apple.quarantine "/Applications/Edgee.app"   # ad-hoc signed → clear Gatekeeper once
```

This installs `Edgee.app` **and** puts the bundled `edgee` CLI on your `PATH`
(symlinked into the Homebrew prefix's `bin`), so the app and the command line
tool always stay in lockstep. It therefore conflicts with the standalone `edgee`
formula — install one or the other (`brew unlink edgee` first if needed).

The two carry **separate version numbers**: the cask version is the app's, while
the CLI it installs is whichever release that build embedded — `edgee --version`,
or the app bundle's `EdgeeCLIVersion` key. Upgrading the cask only moves the CLI
when the app release bumped it, which each release states in its notes.

The app is **ad-hoc signed, not yet notarized**, so Gatekeeper blocks a
downloaded build on first open — hence the one-time `xattr` above (or right-click
→ Open in Finder). This step goes away once we ship a notarized, Developer-ID
build.

## Distribution (maintainers)

Releases are automated via `.github/workflows/`, mirroring the CLI's setup:

**The app version is its own.** The edgee CLI the bundle embeds is versioned
separately by `EDGEE_CLI` in `release.yml`, so an app-only fix ships without
touching the CLI.

1. To move the embedded CLI, bump `EDGEE_CLI` to a **published** edgee release
   and commit it. Leave it alone to keep the CLI you're already shipping.
2. Tag the app and push: `git tag vX.Y.Z && git push origin vX.Y.Z`.
   `release.yml` (macOS runner) builds an arm64 `Edgee.app`, packages
   `Edgee-X.Y.Z.zip` (+ sha256), and opens a **draft** GitHub Release.
3. Review and **publish** the draft. That fires `homebrew-cask.yml`, which pins
   `edgee-ai/homebrew-tap/Casks/edgee-menubar.rb` to the new version + checksum.

Required secret: `HOMEBREW_TAP_TOKEN` (write on `edgee-ai/homebrew-tap`; the CLI
binary is fetched from edgee's public releases, so no read token is needed). The
edgee release must be published (not a draft) or the build can't download the CLI
— its arm64 darwin binary is the asset the app embeds. Running `release.yml` by
hand instead takes both versions as fields, so you can embed a different CLI for
one build without a commit. Manual fallback: `make dist APP_VERSION=X.Y.Z EDGEE_BIN=<edgee>`,
upload the zip to a release, paste `version`/`sha256` into the cask, copy to the tap.

Currently an **arm64-only** build (Apple Silicon). Universal (arm64 + x86_64 via
`lipo`) is a follow-up.

### Apple signing & notarization

Releases are Developer ID signed with a hardened runtime, then notarized and
stapled by `release.yml`, so Gatekeeper accepts them with no `xattr` step. Driven
by these repo secrets:

- `APPLE_SIGN_IDENTITY` — `Developer ID Application: Edgee Cloud (VC4Z4MZLM6)`
- `APPLE_CERT_P12` (base64 of the exported `.p12`) + `APPLE_CERT_PASSWORD`
- `APPLE_API_KEY_ID`, `APPLE_API_ISSUER`, `APPLE_API_KEY_P8` (base64 App Store
  Connect API key, for `notarytool`)

All five go together: the signing *and* notarizing steps both key off
`APPLE_SIGN_IDENTITY`, so setting it without the API key secrets fails the
release. Leave it unset and builds fall back to ad-hoc signing.

The `.p12` holds the signing private key — Apple cannot reissue it, only revoke
and replace the certificate, so keep a backup outside CI. Locally:
`make dist CODESIGN_IDENTITY="Developer ID Application: Edgee Cloud (VC4Z4MZLM6)"`.

## Layout

- `Sources/EdgeeMenuBar/EdgeeMenuBarApp.swift` — `@main` app + `MenuBarExtra` scene
- `Sources/EdgeeMenuBar/MenuContentView.swift` — the dropdown UI
- `Sources/EdgeeMenuBar/EdgeeCLI.swift` — subprocess wrapper around `edgee`
- `Sources/EdgeeMenuBar/AuthStatus.swift` — decodes `edgee auth status --json`
- `Info.plist` — bundle metadata (`LSUIElement`)
- `Makefile` — build/bundle/run
