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
  depends_on macos: :sonoma

  app "Edgee.app"
  # Expose the bundled CLI on PATH (symlinked into the Homebrew prefix's bin).
  # Its version is pinned independently of the app's — `edgee --version`, or the
  # app bundle's `EdgeeCLIVersion` key, is what it actually is. NOTE: the standalone `edgee`
  # formula links the same `bin/edgee`; installing both collides (casks can't
  # declare a formula conflict), so pick one — see caveats.
  binary "#{appdir}/Edgee.app/Contents/Resources/edgee"

  # App state locations for `brew uninstall --zap`.
  zap trash: [
    "~/Library/Caches/ai.edgee.menubar",
    "~/Library/Preferences/ai.edgee.menubar.plist",
  ]

  caveats <<~EOS
    This also installs the `edgee` CLI on your PATH; it conflicts with the
    standalone `edgee` formula, so `brew unlink edgee` first if you have it.
  EOS
end
