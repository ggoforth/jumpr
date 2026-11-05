.PHONY: test app run install

test:
	swift test

app:
	scripts/build-app.sh

run: app
	-pkill -x Jumpr
	open build/Jumpr.app

install: app
	rm -rf /Applications/Jumpr.app
	cp -R build/Jumpr.app /Applications/Jumpr.app
