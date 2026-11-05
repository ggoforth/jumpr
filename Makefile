.PHONY: test app run run-direct install

test:
	swift test

app:
	scripts/build-app.sh

run: app
	-pkill -x Jumpr
	open build/Jumpr.app

# Started as a child of the shell so it inherits that shell's Accessibility access.
run-direct: app
	-pkill -x Jumpr
	nohup build/Jumpr.app/Contents/MacOS/Jumpr >/dev/null 2>&1 &

install: app
	rm -rf /Applications/Jumpr.app
	cp -R build/Jumpr.app /Applications/Jumpr.app
