# Jumpr

Click anything on your Mac without the mouse. Press a hotkey, type two letters, and it clicks.

[Website](https://getjumpr.app) · [Download for Mac](https://github.com/ggoforth/jumpr/releases/latest/download/Jumpr.zip) · MIT license

There is a live demo on the website: [getjumpr.app](https://getjumpr.app).

## What it does

- Press ⌘⇧Space and Jumpr puts a two-letter label on every clickable element on every display: buttons, links, Dock icons, menu bar icons and menus.
- Type the two letters and Jumpr clicks that element.
- Labels take about a tenth of a second to appear.
- It is free and open source, from BaggaDonuts LLC. It needs macOS 15 or later and works with one display or several.

## Install

1. [Download Jumpr.zip](https://github.com/ggoforth/jumpr/releases/latest/download/Jumpr.zip).
2. Unzip it and move Jumpr to your Applications folder.
3. Open Jumpr. It lives in the menu bar and has no Dock icon.
4. macOS asks for the Accessibility permission. See below.

## The Accessibility permission

Jumpr needs it for two things: to find the buttons, links and icons on your screens, and to click the one you pick.

To grant it, open System Settings → Privacy & Security → Accessibility and turn on Jumpr. Jumpr's Settings window also has an Open Accessibility Settings button.

What Jumpr does with it:

- It reads the screen on your Mac to place labels. What it reads is not recorded, stored or sent anywhere.
- It does not record your screen.
- It keeps a small activity log on your Mac (`~/Library/Logs/Jumpr.log`). The log has timings and the kind of control and app for each press. It has no window contents, no on-screen text and nothing you type.

## Using it

1. Press ⌘⇧Space. Labels appear on every display.
2. Type the two letters of the label you want. Each letter you type hides the labels that don't match.
3. When the letters match, Jumpr clicks.

| Key | What it does |
|---|---|
| Backspace | Undoes the last letter |
| Esc | Cancels |
| The hotkey again | Cancels |

The menu bar icon has Settings…, Pause (Resume when paused) and Quit.

Settings lets you change:

- The hotkey
- Label size, label color and text color
- How much Jumpr scans while on battery: full speed, front app only (the default), or scan on demand
- Start at login
- A timing readout, off by default

## Updates

Once a day, Jumpr checks an update feed on getjumpr.app to see whether a new version is out. When one is, it installs it when you say so. You can turn the check off in Settings. This is the only thing the app uses the internet for.

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

`make run` builds `build/Jumpr.app` and opens it. It stops any running copy of Jumpr first.

`make run` signs the app with an "Apple Development" identity (`scripts/build-app.sh`). A stable identity is what keeps the Accessibility permission across rebuilds. If you have no such identity in your keychain, signing fails. Skip it and sign ad hoc instead:

```bash
JUMPR_NO_SIGN=1 make app
codesign --force --sign - build/Jumpr.app
open build/Jumpr.app
```

An ad-hoc build has no stable identity, so you have to grant Accessibility again after each rebuild.

`make release` and `scripts/release.sh` exist for maintainers who build the signed, notarized download.

## Known limits

- Web pages in a browser can take a moment to get their labels the first time, because browsers build that information on request.
- A web-based app that was covered by other windows when Jumpr started gets its labels when the app first comes to the front. If you uncover it some other way, the first press may show few labels for it and the next is complete.
- Menu bar icons are found by remembering which apps own one. If an app adds its icon later, it has no label until Jumpr next checks (at unlock, resume, or when an app launches or first comes to the front).
- While a password field has keyboard focus, macOS keeps keystrokes from reaching Jumpr, so neither the hotkey nor Esc works.
- Jumpr turns on accessibility information in web-based apps so it can see them. When you Pause or Quit, it turns off everything it turned on, including anything another tool had turned on too. If Jumpr loses the Accessibility permission while it runs, it can't turn them off, and they stay on until those apps quit.

## Reporting a problem

Open an issue on [GitHub](https://github.com/ggoforth/jumpr/issues). Contributions are welcome. There is no promise about how fast anyone replies.

## License

[MIT](LICENSE). Copyright (c) 2026 BaggaDonuts LLC.

## More from BaggaDonuts

[Watchflows](https://watchflows.app/) builds powerful automations with a visual canvas, AI nodes, and deep macOS integration. Auto-name your screenshots. Sort your downloads.
