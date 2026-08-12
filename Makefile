APP      := Edgee.app
CONFIG   := release
BIN      := .build/$(CONFIG)/EdgeeMenuBar
# The edgee CLI binary embedded in the bundle. By default we embed the `edgee`
# already installed on PATH, so the app ships a real CLI. Override with
# EDGEE_BIN=/path/to/edgee to bundle a specific build (e.g. a local checkout's
# ../edgee/target/release/edgee).
EDGEE_BIN ?= $(shell command -v edgee 2>/dev/null)

# A nix/direnv devshell may export DEVELOPER_DIR and SDKROOT pointing at a nix
# apple-sdk, and ship its own xcrun shim earlier on PATH. That breaks Xcode's
# swift/xcrun ("tool 'swift' not found"). Clear those and put the system
# toolchain paths first so `make` works inside such a shell too.
unexport DEVELOPER_DIR
unexport SDKROOT
export PATH := /usr/bin:/bin:/usr/sbin:/sbin:$(PATH)

.PHONY: build test bundle run clean icons

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
	@VERSION=$$("$(EDGEE_BIN)" --version 2>/dev/null | sed -E 's/[^0-9]*([0-9]+\.[0-9]+\.[0-9]+).*/\1/'); \
		VERSION=$${VERSION:-0.0.0}; \
		/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $$VERSION" "$(APP)/Contents/Info.plist"; \
		/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $$VERSION" "$(APP)/Contents/Info.plist"; \
		echo "stamped bundle version $$VERSION (from embedded edgee CLI)"
	codesign --force --sign - "$(APP)/Contents/Resources/edgee"
	codesign --force --sign - "$(APP)"

run: bundle
	open "$(APP)"

clean:
	rm -rf .build "$(APP)"
