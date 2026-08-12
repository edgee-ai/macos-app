# Homebrew cask for the Edgee macOS menubar app.
#
# Canonical copy lives here; the release flow copies it into the tap at
# edgee-ai/homebrew-tap/Casks/edgee-menubar.rb (see README "Distribution").
# `version` and `sha256` are filled from `make dist` output for each release.
cask "edgee-menubar" do
  version "0.4.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/edgee-ai/macos-app/releases/download/v#{version}/Edgee-#{version}.zip"
  name "Edgee"
  desc "Menubar app for the Edgee agent gateway"
  homepage "https://www.edgee.cloud"

  # Apple Silicon only for now — CI ships an arm64 build (see release.yml).
  depends_on arch: :arm64
  # macOS 14 Sonoma or newer (matches the app's LSMinimumSystemVersion).
  depends_on macos: ">= :sonoma"

  app "Edgee.app"
  # Expose the bundled CLI on PATH (symlinked into the Homebrew prefix's bin);
  # it always matches the installed app version.
  binary "#{appdir}/Edgee.app/Contents/Resources/edgee"

  # The standalone `edgee` CLI formula links the same `bin/edgee`; installing both
  # would collide, so make them mutually exclusive.
  conflicts_with formula: "edgee"

  # The bundled `edgee` CLI and app state live under the standard locations.
  zap trash: [
    "~/Library/Caches/ai.edgee.menubar",
    "~/Library/Preferences/ai.edgee.menubar.plist",
  ]

  caveats <<~EOS
    Edgee.app is ad-hoc signed (not yet notarized by Apple). If macOS refuses to
    open it, reinstall without quarantine:

      brew reinstall --cask --no-quarantine edgee-menubar

    or clear the quarantine flag once:

      xattr -dr com.apple.quarantine "#{appdir}/Edgee.app"
  EOS
end
