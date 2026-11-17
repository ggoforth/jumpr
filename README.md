# Jumpr

Click anything on your Mac without the mouse. Press a hotkey, type two letters, and it clicks.

[Website](https://getjumpr.app) · [Download for Mac](https://github.com/ggoforth/jumpr/releases/latest/download/Jumpr.zip) · MIT license

There is a live demo on the website: [getjumpr.app](https://getjumpr.app).

## What it does

- Press ⌘⇧Space and Jumpr puts a short label, usually two letters, on every clickable element on every display: buttons, links, Dock icons, menu bar icons, menus and notifications.
- Type the letters and Jumpr clicks that element.
- Labels take about a tenth of a second to appear.
- It is free and open source, from BaggaDonuts LLC. It needs macOS 15 or later and works with one display or several.

## Install

1. [Download Jumpr.zip](https://github.com/ggoforth/jumpr/releases/latest/download/Jumpr.zip).
2. Unzip it and move Jumpr to your Applications folder.
3. Open Jumpr. It lives in the menu bar and has no Dock icon.
4. macOS asks for the Accessibility permission. See below.

## The Accessibility permission

Jumpr needs it for two things: to find the buttons, links and icons on your screens, and to click the one you pick.

To grant it, open System Settings → Privacy & Security → Accessibility and turn on Jumpr. Until you do, the panel under Jumpr's menu bar icon has an Open Accessibility Settings button.

What Jumpr does with it:

- It reads the screen on your Mac to place labels. What it reads is not recorded, stored or sent anywhere.
- It does not record your screen.
- It keeps a small activity log on your Mac (`~/Library/Logs/Jumpr.log`). The log has timings, the names of the apps Jumpr looked at, the kind of control, the kind of click and the app for each press, and the app and amount of each scroll in scroll mode. It has no window contents, no on-screen text and nothing you type. If you attach it to an issue, it shows which apps you had open.

## Using it

1. Press ⌘⇧Space. Labels appear on every display.
2. Type the two letters of the label you want. Each letter you type hides the labels that don't match.
3. When the letters match, Jumpr clicks.

The [docs](https://getjumpr.app/docs/) cover the rest:

- [Labels and keys](https://getjumpr.app/docs/using/labels-and-keys.html): every key that works while labels are up.
- [Kinds of click](https://getjumpr.app/docs/using/kinds-of-click.html): right-click, ⌘-click, double-click and ⇧-click.
- [Persistent mode](https://getjumpr.app/docs/using/persistent-mode.html): keep the labels up for a run of clicks.
- [Scrolling](https://getjumpr.app/docs/using/scrolling.html): scroll any area from the keyboard.
- [The panel](https://getjumpr.app/docs/using/the-panel.html): colors, label size, shortcuts and the switch that pauses Jumpr.

## Updates

Once a day, Jumpr checks an update feed on getjumpr.app to see whether a new version is out. When one is, it installs it when you say so. You can turn the check off in the panel under the menu bar icon. This is the only thing the app uses the internet for.

## Privacy

- The app has no account, no analytics, no telemetry and no crash reporting.
- What Jumpr reads to place labels never leaves your Mac.
- The website (not the app) counts visits with Plausible Analytics, without cookies.

Full details: [getjumpr.app/privacy](https://getjumpr.app/privacy).

## Build from source

You need:

- macOS 15 or later
- Xcode 16 or later (the Swift 6 toolchain; `Package.swift` uses swift-tools-version 6.0)

```bash
git clone https://github.com/ggoforth/jumpr.git
cd jumpr
make test
make run
```

`make run` builds `build/Jumpr.app` and opens it. It stops any running copy of Jumpr first. The first build downloads one dependency, [Sparkle](https://sparkle-project.org) (the updater), pinned to an exact version in `Package.swift`.

`make run` signs the app with an "Apple Development" identity (`scripts/build-app.sh`). A stable identity is what keeps the Accessibility permission across rebuilds. If you have no such identity in your keychain, sign ad hoc instead:

```bash
CODESIGN_IDENTITY=- make run
```

An ad-hoc build has no stable identity, so you have to grant Accessibility again after each rebuild.

Things to know when you work on it:

- A build from source is a development build. It shows version 0.1.0, never updates itself, and shares the bundle ID, preferences and log of an installed Jumpr. `make run` stops the installed copy; reopen it from Applications when you are done.
- macOS ties the Accessibility permission to the signature. If you also have the released Jumpr installed, its entry in System Settings does not cover your build: remove the entry and add your build, or run `tccutil reset Accessibility com.greggoforth.jumpr` and grant it again.
- [docs/design.md](docs/design.md) explains how it works: the scan, web content, labels, keys and pressing.
- The docs on the website are written in `docs-src/`, one Markdown file per page. `make docs` builds them into `site/docs/` (it needs Node, and no packages); [docs-src/README.md](docs-src/README.md) says how to write a page.
- The logic lives in `Sources/JumprCore` and is covered by `make test`. `Sources/Jumpr` is the app around it (windows, the key listener, accessibility calls) and has no unit tests.
- Start Jumpr with `JUMPR_DEBUG_LABELS=1` in its environment to log every label's position. That also logs the label letters you type, so leave it off otherwise.

`make release` and `scripts/release.sh` exist for maintainers who build the signed, notarized download.

## Known limits

What Jumpr cannot label or click yet, and why, is in the docs: [Known limits](https://getjumpr.app/docs/help/known-limits.html).

## Reporting a problem

Open an issue on [GitHub](https://github.com/ggoforth/jumpr/issues). Contributions are welcome. There is no promise about how fast anyone replies.

For a security problem, please report it privately instead: see [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE). Copyright (c) 2026 BaggaDonuts LLC.

Jumpr includes [Sparkle](https://github.com/sparkle-project/Sparkle) for updates, under its own MIT-style license. That license ships inside the app as `Sparkle-LICENSE.txt`.

## More from BaggaDonuts

[Watchflows](https://watchflows.app/) builds powerful automations with a visual canvas, AI nodes, and deep macOS integration. Auto-name your screenshots. Sort your downloads.
