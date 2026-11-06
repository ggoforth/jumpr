.PHONY: test app release run run-direct install icon

test:
	swift test

# Env: CODESIGN_IDENTITY, CODESIGN_OPTIONS, JUMPR_FEED_URL, JUMPR_SPARKLE_PUBLIC_KEY, JUMPR_VERSION, JUMPR_BUILD_NUMBER (defaults: dev build, updates off; see the script).
app:
	scripts/build-app.sh

# Universal, Developer ID signed, notarized build/release/Jumpr.zip with Sparkle, and its
# signed build/release/appcast.xml. Uploads nothing.
#   make release VERSION=1.0.0 JUMPR_NOTARY_PROFILE=<profile>
#   make release VERSION=1.0.0 ARGS=--skip-notarize
release:
	@test -n "$(VERSION)" || { echo "usage: make release VERSION=x.y.z [ARGS=--skip-notarize]" >&2; exit 1; }
	scripts/release.sh $(VERSION) $(ARGS)

# Both listen for the same hotkey: the throwaway spike is stopped first.
run: app
	-pkill -x jumpr-spike
	-pkill -x Jumpr
	open build/Jumpr.app

# Started as a child of the shell so it inherits that shell's Accessibility access.
run-direct: app
	-pkill -x jumpr-spike
	-pkill -x Jumpr
	nohup build/Jumpr.app/Contents/MacOS/Jumpr >/dev/null 2>&1 &

install: app
	rm -rf /Applications/Jumpr.app
	cp -R build/Jumpr.app /Applications/Jumpr.app

# Redraws the placeholder icon. Resources/AppIcon.icns is committed; the iconset is scratch.
icon:
	rm -rf build/AppIcon.iconset
	swift scripts/make-icon.swift build/AppIcon.iconset
	iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
