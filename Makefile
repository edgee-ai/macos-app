APP      := Edgee.app
CONFIG   := release
BIN      := .build/$(CONFIG)/EdgeeMenuBar
DIST     := dist
# The edgee CLI binary embedded in the bundle. By default we embed the `edgee`
# already installed on PATH, so the app ships a real CLI. Override with
# EDGEE_BIN=/path/to/edgee to bundle a specific build (e.g. a local checkout's
# ../edgee/target/release/edgee).
EDGEE_BIN ?= $(shell command -v edgee 2>/dev/null)

# The app's own version, stamped into the bundle. Empty (the default) falls back
# to the embedded CLI's version, which is all a local build needs. release.yml
# passes the app tag here — the app and the CLI it embeds version independently,
# so releasing an app-only fix doesn't need a new CLI release.
APP_VERSION ?=

# Codesigning identity. Default `-` = ad-hoc (local/dev; not distributable).
# For a notarizable build, override with a Developer ID and hardened runtime is
# added automatically:
#   make dist CODESIGN_IDENTITY="Developer ID Application: Edgee (TEAMID)"
CODESIGN_IDENTITY ?= -
ifeq ($(CODESIGN_IDENTITY),-)
CODESIGN := codesign --force --sign -
else
CODESIGN := codesign --force --options runtime --timestamp --sign "$(CODESIGN_IDENTITY)"
endif

# A nix/direnv devshell may export DEVELOPER_DIR and SDKROOT pointing at a nix
# apple-sdk, and ship its own xcrun shim earlier on PATH. That breaks Xcode's
# swift/xcrun ("tool 'swift' not found"). Clear those and put the system
# toolchain paths first so `make` works inside such a shell too.
unexport DEVELOPER_DIR
unexport SDKROOT
export PATH := /usr/bin:/bin:/usr/sbin:/sbin:$(PATH)

.PHONY: build test bundle run dist clean icons

# Regenerate the app icon (Edgee.icns) and menubar template (MenuBarIcon.pdf)
# from the Edgee mark. Run after changing tools/gen-icons.swift; commit the
# resulting Assets/. (swift/iconutil inherit the fixed env from above.)
icons:
	swift tools/gen-icons.swift Assets
	iconutil -c icns Assets/Edgee.iconset -o Assets/Edgee.icns
	rm -rf Assets/Edgee.iconset

build:
	swift build -c $(CONFIG)

test:
	swift test

# Assemble a minimal .app bundle around the SwiftPM binary. The Info.plist marks
# it LSUIElement (menubar-only), and we ad-hoc codesign so macOS will run it.
bundle: build
	@test -n "$(EDGEE_BIN)" && test -x "$(EDGEE_BIN)" || { \
		echo "error: no edgee binary found (EDGEE_BIN='$(EDGEE_BIN)')."; \
		echo "install it (see https://github.com/edgee-ai/edgee) or set EDGEE_BIN=/path/to/edgee"; \
		exit 1; }
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	cp "$(BIN)" "$(APP)/Contents/MacOS/Edgee"
	cp "$(EDGEE_BIN)" "$(APP)/Contents/Resources/edgee"
	cp Assets/Edgee.icns "$(APP)/Contents/Resources/Edgee.icns"
	cp Assets/MenuBarIcon.pdf "$(APP)/Contents/Resources/MenuBarIcon.pdf"
	cp Info.plist "$(APP)/Contents/Info.plist"
	@CLI_VERSION=$$("$(EDGEE_BIN)" --version 2>/dev/null | sed -E 's/[^0-9]*([0-9]+\.[0-9]+\.[0-9]+).*/\1/'); \
		CLI_VERSION=$${CLI_VERSION:-0.0.0}; \
		VERSION="$(APP_VERSION)"; VERSION=$${VERSION:-$$CLI_VERSION}; \
		/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $$VERSION" "$(APP)/Contents/Info.plist"; \
		/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $$VERSION" "$(APP)/Contents/Info.plist"; \
		/usr/libexec/PlistBuddy -c "Set :EdgeeCLIVersion $$CLI_VERSION" "$(APP)/Contents/Info.plist"; \
		echo "stamped bundle version $$VERSION (embedded edgee CLI $$CLI_VERSION)"
	$(CODESIGN) "$(APP)/Contents/Resources/edgee"
	$(CODESIGN) "$(APP)"

run: bundle
	open "$(APP)"

# Package the signed bundle into a zip for a GitHub Release + Homebrew cask.
# `ditto` preserves the bundle and its code signature; the printed sha256 goes
# into Casks/edgee-menubar.rb once the zip is uploaded to the release.
dist: bundle
	@VERSION=$$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$(APP)/Contents/Info.plist"); \
		mkdir -p "$(DIST)"; \
		ZIP="$(DIST)/Edgee-$$VERSION.zip"; \
		rm -f "$$ZIP" "$$ZIP.sha256"; \
		ditto -c -k --sequesterRsrc --keepParent "$(APP)" "$$ZIP"; \
		shasum -a 256 "$$ZIP" | awk '{print $$1}' > "$$ZIP.sha256"; \
		echo "built $$ZIP"; \
		echo "version: $$VERSION"; \
		echo "sha256:  $$(cat $$ZIP.sha256)"

clean:
	rm -rf .build "$(APP)" "$(DIST)"
