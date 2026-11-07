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
- It keeps a small activity log on your Mac (`~/Library/Logs/Jumpr.log`). The log has timings, the names of the apps Jumpr looked at, the kind of control and app for each press, and the app and amount of each scroll in scroll mode. It has no window contents, no on-screen text and nothing you type. If you attach it to an issue, it shows which apps you had open.

## Using it

1. Press ⌘⇧Space. Labels appear on every display.
2. Type the two letters of the label you want. Each letter you type hides the labels that don't match.
3. When the letters match, Jumpr clicks.

| Key | What it does |
|---|---|
| Backspace | Undoes the last letter |
| Esc | Cancels |
| The hotkey again | Cancels |

Click the menu bar icon for Jumpr's panel. It has a switch that turns Jumpr on and off (off is a pause: the hotkey does nothing), a preview of the labels, Check for Updates…, Report a Problem and Quit.

The panel is also where you change:

- The hotkey, and the scroll shortcut
- Label size, label color and letter color (Auto picks black or white, whichever reads better on the label)
- Start at login (off until you turn it on)
- Whether Jumpr checks for updates on its own

### Scrolling

Press ⌘⇧J to turn on scroll mode. Every scrollable area on every display gets a letter, and the one you scrolled last in that window (or the one holding the keyboard focus) is already outlined. Your pointer never moves.

| Key | What it does |
|---|---|
| J / K | Scrolls the outlined area down / up a line |
| D / U | Half the area's height down / up |
| G / Shift G | To the top / the bottom |
| An area's letter | Outlines that area instead |
| F | Brings the letters back |
| Esc, or ⌘⇧J again | Leaves scroll mode |

Holding a key keeps scrolling. While scroll mode is on, Jumpr takes the keys and the menu bar icon stays highlighted; shortcuts with ⌘, ⌃ or ⌥ still work. A click anywhere, switching apps, locking the screen or pausing Jumpr also leaves it.

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
- The logic lives in `Sources/JumprCore` and is covered by `make test`. `Sources/Jumpr` is the app around it (windows, the key listener, accessibility calls) and has no unit tests.
- Start Jumpr with `JUMPR_DEBUG_LABELS=1` in its environment to log every label's position. That also logs the label letters you type, so leave it off otherwise.

`make release` and `scripts/release.sh` exist for maintainers who build the signed, notarized download.

## Known limits

- Widgets on the desktop have no labels.
- While Notification Center is open, windows behind it on that display have no labels, because a click outside it only closes it.
- Web pages in a browser can take a moment to get their labels the first time, because browsers build that information on request.
- A web-based app that was covered by other windows when Jumpr started gets its labels when the app first comes to the front. If you uncover it some other way, the first press may show few labels for it and the next is complete.
- Menu bar icons are found by remembering which apps own one. If an app adds its icon later, it has no label until Jumpr next checks (at unlock, resume, or when an app launches or first comes to the front).
- While a password field has keyboard focus, macOS keeps keystrokes from reaching Jumpr, so neither the hotkey nor Esc works.
- Jumpr turns on accessibility information in web-based apps so it can see them. When you Pause or Quit, it turns off everything it turned on, including anything another tool had turned on too. If Jumpr loses the Accessibility permission while it runs, it can't turn them off, and they stay on until those apps quit.

## Reporting a problem

Open an issue on [GitHub](https://github.com/ggoforth/jumpr/issues). Contributions are welcome. There is no promise about how fast anyone replies.

For a security problem, please report it privately instead: see [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE). Copyright (c) 2026 BaggaDonuts LLC.

Jumpr includes [Sparkle](https://github.com/sparkle-project/Sparkle) for updates, under its own MIT-style license. That license ships inside the app as `Sparkle-LICENSE.txt`.

## More from BaggaDonuts

[Watchflows](https://watchflows.app/) builds powerful automations with a visual canvas, AI nodes, and deep macOS integration. Auto-name your screenshots. Sort your downloads.
