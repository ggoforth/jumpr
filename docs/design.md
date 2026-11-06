# Jumpr design

How Jumpr works today, for anyone who wants to understand or change the code. For what the app does from a user's point of view, how to install it and how to build it, see the [README](../README.md).

## Overview

Jumpr lets you click anything on screen from the keyboard. Press the hotkey and every clickable element on every display gets a short letter label; type a label and Jumpr clicks that element, bringing its app forward if needed. Two targets shape the design:

- **Every display at once.** One hotkey labels every visible window of every app on every connected display, not just the focused app or the current screen.
- **Labels in about a tenth of a second.** Hotkey to labels should feel instant, and Jumpr sits in the path of every keystroke, so it must never stall typing.

Measured during development on one three-display Mac, approximately: listing the on-screen windows takes 2–4 ms, scanning all apps in parallel about 70–110 ms (up to about 270 ms on a heavy web page), and painting labels 5–15 ms. The first scan of an app after Jumpr starts costs more, about 250–285 ms, a one-time connection cost per app. Scanning is nearly the whole cost, and an app answers one accessibility request at a time, so the total is set by the slowest app.

Jumpr does nothing in the background while you are not using it: there are no timers and no polling of its own. The few delayed calls in the code are one-shot. The one exception is the updater's daily check for a new version.

## Shape of the code

The package has two targets. `JumprCore` is pure logic: no AppKit, no accessibility calls, no third-party code, and it is what `make test` covers. `Jumpr` is the AppKit shell around it and has no unit tests. The accessibility tree reaches `JumprCore` through the small `AXNode` protocol, so the tree walk runs on plain data in tests.

| File | What it is for |
|---|---|
| **`Sources/JumprCore`** | |
| `TreeWalk.swift` | The tree walk: clickable roles, clipping, the depth cap, the covered-row rule; the web-tree timing rules |
| `Geometry.swift` | `WindowStack`: the on-screen windows front to back, which window is on top at a point, which apps to scan |
| `Labels.swift` | The label alphabet, label length, label placement, `LabelPool` |
| `LabelSession.swift` | What each key does while labels are up |
| `PressSafety.swift` | Pressing rules: whether to press at all, `AXPress` or click, where to click, when a click may be sent |
| `Settings.swift` | `Hotkey`, `RGB`, the label size clamp, and `Keys`, the names of every preference |
| `DisplayGeometry.swift` | Conversion between AppKit's bottom-left display frames and the global top-left coordinates used everywhere else |
| `LogFile.swift` | The log size cap and when to rotate |
| `UpdatePolicy.swift` | Whether a build carries a real update feed and key |
| **`Sources/Jumpr`** | |
| `main.swift` | Wires everything together: pause, quit, trust changes, debug signals |
| `Controller.swift` | One trigger end to end: window list, scans, painting, typing, cancelling; the web look-again pass |
| `Scanner.swift` | Runs accessibility work on each app's own serial queue; scans an app's windows and system pieces |
| `AX.swift` | Thin wrappers over the accessibility API, the per-request timeout, `AXElementNode` |
| `TreeRegistry.swift` | Switches web-based apps' accessibility trees on, and back off |
| `ExtrasOwners.swift` | Remembers which apps own a menu bar extra |
| `WindowServer.swift` | Reads the window server's on-screen window list |
| `Overlay.swift` | One transparent, click-through window per display; `LabelStyle` |
| `KeyTap.swift` | The event tap that sees every key press |
| `Presser.swift` | Presses a matched element |
| `Activation.swift` | Ways to bring another app forward, mildest first |
| `Readout.swift` | Per-trigger timing, always logged, optionally drawn on screen |
| `Onboarding.swift` | The Accessibility permission; `LoginItem` (start at login) |
| `SettingsView.swift`, `HotkeyRecorder.swift` | The Settings window (the only SwiftUI) and the hotkey recorder |
| `StatusItem.swift` | The menu bar icon and its menu |
| `UpdaterController.swift` | Sparkle |
| `PowerSource.swift` | Tracks whether the screen is locked, asleep or showing the screen saver |
| `Log.swift`, `DefaultsWatcher.swift`, `DistributedObserver.swift` | The log file; live reaction to preference changes; distributed notifications delivered immediately |

## The trigger, end to end

```
hotkey (event tap, main run loop)
  └─ Controller.trigger
       ├─ list on-screen windows, front to back (WindowServer.snapshot)
       ├─ for each app to scan, on that app's own serial queue, all apps in parallel:
       │     walk each visible window, then the app's menu bar and extras
       │     └─ each window's result comes back to main and is painted at once
       ├─ user types: labels that no longer match are hidden
       └─ a full label matches → cancel the session → Presser.press
```

**Which apps are scanned.** `WindowStack.appsToScan` takes each window owner once, front to back, never Jumpr itself. The frontmost app is added if it has no on-screen window, so its menu bar is still labelled. Then come the apps that own menu bar extras (see `ExtrasOwners`): the menu bar's windows belong to the window server, so the window list never names those apps.

**Parallel across apps, serial within one.** `Scanner.perform` runs work on a serial queue per process. Apps scan in parallel, and no app ever has two scans, or a scan and a press, at once. Scans the user is waiting on run at user-interactive priority; bookkeeping and tree switching run at utility priority.

**Budgets.** Each app gets a 0.5 s scan budget (`Scanner.budget`) shared by all its windows; a walk that runs out returns what it found and is flagged `TIMEOUT` in the readout. Every accessibility request has a 0.25 s timeout (`axRequestTimeout`, set on each element by `axTimed`) instead of the system default of 6 s, so one hung app cannot hold up the rest.

**Painting as results arrive.** Each window's result reaches `Controller.receive` on the main queue as soon as it is ready, so fast apps show labels before slow ones finish. When every app has answered, `finish` writes the readout. If nothing was labelled, the session cancels, because a capturing session with nothing to type at would only swallow keys.

**The generation rule.** Every trigger and every cancel bumps `generation`. Each scan callback captures the generation it was issued under and is dropped, before it touches overlays, the session or the readout, unless it still matches and a session is active (`isCurrent`). Scans already queued for an old generation stop early: `isStale` reads a lock-protected copy (`SharedGeneration`) before the first accessibility call and between windows.

**Nothing accessibility-related runs on the main thread.** The event tap's callback runs on the main run loop and must return at once; if it stalls, typing stalls system-wide. An accessibility request is answered on the target app's own main thread and can take as long as that app is busy. So every accessibility call goes through an app's scan queue, and the main thread only reads the window list, paints and handles keys.

The same session ends on Esc, the hotkey, a match, a display change (overlays are rebuilt), a Space change, a screen lock, and Pause.

## Scanning

A scan of one app (`Scanner.scanApp`) asks for `AXWindows`, `AXMenuBar` and `AXExtrasMenuBar` in one request, walks each window, then walks the system pieces: the menu bar only for the frontmost app, and the extras bar for any app. The Dock is walked from its application element.

**Windows.** An accessibility window is matched to its window-server ID with the private `_AXUIElementGetWindow`, the only way to tie the two together. If it fails, the fallback is the same app's on-screen window whose bounds match the element's frame within 1 pt per edge (`sameWindowFrame`). A window is skipped outright if a 5×5 grid of sample points finds none of it on top (`WindowStack.anyVisible`).

**One request per element.** `AXElementNode.info` fetches role, position, size, children and enabled state in one `AXUIElementCopyMultipleAttributeValues` call. The one exception is text that may be pressable (below), which costs a second request for its action names.

**The walk** (`walk` in `TreeWalk.swift`):

- **Clickable roles** (`Roles.clickable`): button, link, checkbox, radio button, pop-up button, menu button, disclosure triangle, slider, incrementor, color well, text field, text area, combo box, Dock item, menu item, menu bar item, row. Disabled elements are skipped, and so is anything whose visible part is under 4×4 pt.
- **Text that offers a press** (`Roles.clickableIfPressable`): static text is labelled if the element itself offers `AXPress`. Apps built with the iPad frameworks present a list item this way: every conversation and pin in Messages' sidebar is text that offers a press. The walk asks only where the answer can matter: not in web content, where a long page holds thousands of text nodes and links and buttons have roles of their own, and not under an element that already has a label, such as the text in a table's rows. Only text is asked, because in those apps plain groups offer a press too. Side effect: there, text that does nothing when pressed (a timestamp between messages) offers a press as well, and gets a label.
- **A list's items with no role** (`Roles.clickableAsListItem`): a direct child of an `AXList` whose role is `AXUnknown` is labelled. Dia's sidebar presents each folder this way, with no children and no actions, so its place in the list is the only sign that it is something to click; it gets a synthetic click, since it offers no press. Lists in web content are left alone: their links have a role of their own. Such an item can span more than its own line (an open folder also spans the tabs in it, which are the list's next items), so its rectangle is trimmed to the largest band the list's other labels leave free (`largestFreeBand`), and it gets no label if nothing is free.
- **Leaf controls** (`Roles.leaf`, every clickable role except menu items, menu bar items and rows) are not descended into.
- **Clipping.** The walk starts clipped to the window's bounds and narrows the clip at each scroll area. A subtree whose frame lies entirely outside the clip is skipped. This is what keeps long web pages affordable.
- **On top.** A window element is labelled only if the topmost occluding window at its center is its own window, or a helper window of the same app that is not one of its regular windows (a popover, sheet or menu). System pieces are labelled if their center is on some display.
- **Tables and outlines** are walked through `AXVisibleRows` only. Column elements are skipped, since they repeat the rows' cells.
- **Menus.** A menu bar item or menu item is descended into only while it is selected, that is, while its menu is open.
- **Depth cap.** The walk stops 80 levels deep.
- **Covered rows.** A clickable element with a clickable descendant covering at least half its area gets no label of its own. Both labels would sit at the same right end, and a press on the row would mostly land on the inner element anyway. A smaller control inside, such as a checkbox at the edge of a wide row, is a different action, so both keep their labels.

The walk also counts `AXWebArea` nodes and marks each target found under one as `inWeb`, which the web rules and the presser use.

## Web content

Web-based apps (Electron-style apps, Chromium and WebKit browsers, apps that show mail or documents in a web view) keep their accessibility tree off, or unbuilt, until something asks, and do extra work for as long as it is on. Without it they get few or no labels. `TreeRegistry` switches trees on, records exactly the ones Jumpr switched on, and switches those back off.

**`AXManualAccessibility`, for Electron-style apps.** The first time a regular app has a visible window, `enableIfNeeded` sets `AXManualAccessibility` on it. The app is recorded before the call, so a Pause that starts during the call still switches it off. A "cannot complete" reply means the app did not answer in time, and it is tried again next time. Any other error means the app does not support it (native apps, whose tree is always on), and it is not recorded. The attribute is write-only in practice: a read never returns true.

This runs at every moment an app may first show a window: when Jumpr becomes trusted, on resume, on unlock, 2 s after an app launches, 0.5 s after an app first comes to the front, and on every trigger as a catch-all (`Controller.enableTrees`, `treeCandidates`). The tree arrives some time after the request, so switching it on before the first trigger means that trigger usually finds it built.

**`AXEnhancedUserInterface`, for Chromium browsers whose page is missing.** After each complete scan of an app with a visible window, `noteScan` checks whether a browser on the built-in Chromium list (`TreeRegistry.chromiumIDs`) walked a window and found nothing to click in web content (`webTreeLooksEmpty`). An empty window is not the sign: Chrome with its page tree off still answers with its toolbar. If the page looks missing, Jumpr sets the heavier `AXEnhancedUserInterface`, which has known side effects on window animation and so is used only here. A browser that refused `AXManualAccessibility` (Chrome does) gets it at once; one that accepted it gets it only from its second scan, since its first tree may still be arriving (`mayAskForEnhancedTree`). Chrome answers "not implemented" to this attribute and switches its page tree on all the same, so the code reads the attribute back rather than trusting the result. If it was already on before Jumpr touched it, another tool switched it on, and Jumpr leaves it alone for good. Nothing is decided while the screen is locked, since every window scan is empty then.

**The look-again pass** (`Controller.rescanWhileTreeBuilds`). A scan can come too early for an app's tree, so while the labels are up Jumpr scans the app again every 0.4 s and adds only labels that are new (elements already labelled are skipped by identity). It repeats in two cases:

- A tree Jumpr switched on less than 3 s ago may still be arriving (`treeMayStillBeBuilding`).
- A web view may still be building (`webViewMayStillBeBuilding`): the app hosts web content, walked a window, found nothing to click in it, and the labels went up less than 1.3 s ago. WebKit views, as in Safari and Mail, build their tree only once something asks. A single read every few seconds does not wake them, while a second read shortly after the first does; the scan that asked finds nothing, and the look a moment later finds the page.

An app "hosts web content" if it is on the built-in Chromium list, on the built-in WebKit list (`Controller.webKitHostIDs`: Safari, Safari Technology Preview, Mail), or has shown an `AXWebArea` in some earlier scan. That last list (`webHosts`) is saved in preferences as `webHostApps`, because a web view that is not built yet gives no sign of itself: without the remembered list, the first page after Jumpr starts would get no labels. The WebKit list exists because the remembered list cannot learn those apps in time.

**Switching off.** On Pause and on Quit, `disableAll` stops further enabling, forgets every record, and switches off each attribute Jumpr set, on each app's scan queue. Quit waits up to 0.5 s for that, since the process is exiting. SIGTERM and SIGINT take the same quit path. On resume, `allowEnabling` lets trees come back on.

**When an app quits**, `ExtrasOwners` forgets it, `TreeRegistry.forget` drops its records (queued behind any work still running for it, so that work cannot record it again), and its scan queue goes once it drains.

## Labels

- **Alphabet.** Letters only, home row first: `ASDFGHJKL`, then `QWERTYUIOP`, then `ZXCVBNM`.
- **Fixed length.** All labels in one trigger have the same length, so no label is the start of another. The length is chosen before the scans finish, from the previous complete trigger's label count (200 if there is none) with 1.5x headroom: one letter up to 26, two up to 676, three beyond (`Labels.length`).
- **Overflow.** If the real count exceeds what that length allows, the extras go unlabelled and the readout says `OVERFLOW`. The next trigger sizes from the new count.
- **Placement** (`Labels.frame`). A label must not hide what it points at. A target narrower than four label widths gets its label hanging off its bottom-right corner, overlapping only a few points. At a display edge the label flips to the other side of the target rather than sliding back over it. A larger target (a row, a wide button) keeps its label inside, at the right end, because outside it would straddle two stacked rows and belong to neither. A label is always kept inside its display, and goes on the display that holds the target's center.
- **Look.** Bold monospaced system font, size 10–32 pt (15 by default), label color and text color from preferences. `LabelStyle` is re-read on every trigger. If a color changes in Settings while labels are up, the labels on screen are recolored at once (`Controller.recolor`); size is left alone, since it would move every label.
- **Overlays.** One transparent, click-through window per display, always ordered in, so showing labels is only adding layers. Overlays take global top-left rectangles; the flip to AppKit's bottom-left happens only in `Overlay`.

## Keys

`KeyTap` is a session-level event tap on key-down events. The system hotkey API is not used: during development it registered but never fired, while detecting the hotkey in this listener worked, and the listener is needed for typing labels anyway.

- **Idle.** The tap looks only for the hotkey and passes everything else through untouched. The hotkey is always swallowed; auto-repeats of it are ignored.
- **Labels up** (`capturing`). Plain keys go to `LabelSession`:
  - a letter that extends a label narrows (labels that no longer match are hidden); one that completes a label matches; one that matches nothing is swallowed
  - Backspace undoes a letter
  - Esc cancels; the hotkey cancels too (it reaches the controller as a second trigger)
  - any other plain key is swallowed
  - keys with ⌘, ⌃ or ⌥ pass through to the system, so shortcuts keep working while labels are up
- **The handler never blocks**: no accessibility calls, no scans. The hotkey's work runs on the main queue's next turn.
- **Re-enabled if switched off.** If the system disables the tap (timeout or user input), it is re-enabled at once and trust is checked again.
- **Hotkey recorder.** While the Settings recorder is recording, the tap is suspended (`suspended`) so the keys reach the recorder. Recording ends whenever the window closes or stops being key, so the tap is never left suspended. A combination without ⌘, ⌃ or ⌥ is rejected (`Hotkey.isValid`). The hotkey is stored as `keyCode:modifiers` and applied live.
- **Secure input.** While a password field has keyboard focus, macOS keeps keystrokes from every event tap, so neither the hotkey nor Esc reaches Jumpr.

## Pressing

`Presser.press` runs on the target app's scan queue, so a press never overlaps a scan of the same app. Never pressing something other than what the label was on is the rule everything here serves.

1. **Check it is still there.** Re-read the element's frame. If the element is gone, or no longer overlaps the rectangle it had when it was scanned, do nothing (`pressDecision`). The label is not the reference: it hangs beside small targets.
2. **Bring its app forward.** If the element belongs to a window: ask the app to be frontmost through accessibility (`AXFrontmost`, which macOS 27 ignores), make the public activation request (`Activation.activate`), and raise the window (`AXRaise`).
3. **Choose `AXPress` or a click** (`usesAXPress`). Text fields, text areas and combo boxes always get a click, which puts the caret in them. Web content (`inWeb`) always gets a click: it can answer success to `AXPress` and do nothing, so only a real click is trustworthy there. Anything else uses `AXPress` if it offers that action, and is clicked if it does not.
4. **`AXPress`** (`afterAXPress`). Success counts as pressed. So does "cannot complete": apps answer that way while tracking a menu the press just opened. "Invalid element" means it is gone: do nothing. Any other error falls back to a click.
5. **Wait until the app is really in front** (`waitUntilForward`, `clickReadiness`). A click on a window that is not in front only brings it forward; browsers do not pass that first click on to the page. So before a click into a window, Jumpr waits until the app says it is frontmost and the window is its main window. Activation is cooperative since macOS 14, so the request escalates in steps, each checked before the next:
   1. the public request already made in step 2, given 0.15 s
   2. opening the running app through Launch Services, as the Dock does (`Activation.open`), 0.35 s
   3. a direct request to the window server, marked as user generated (`Activation.windowServer`), 0.3 s. This is a private call that window switchers use; its symbols are looked up at run time, so a macOS that drops them costs only this step.

   Once the app is in front, the window is raised again and Jumpr waits a further 50 ms for the window server to catch up. If it never comes, Jumpr clicks anyway and says so in the log. With no window to wait for (a menu bar extra whose `AXPress` failed), the click follows a fixed 40 ms pause instead.
6. **Click once.** Re-read the frame, since the raise or a failed press may have moved or closed it, and check again as in step 1. Then post one synthetic click at the center of the part that was visible when scanned, as it is now (`clickPoint`), with modifier flags cleared so a key still held from typing the label does not ride along. One click, never two: an app that does pass the first click on would get a double click.
7. **Label the opened menu.** If a menu bar item or menu item was pressed and is now selected (its menu or submenu opened), Jumpr triggers again 0.1 s later, unless a session has started meanwhile (`relabelsAfterPress`). Otherwise every menu would take two hotkey presses. Menu bar extras share the menu bar item role but open panels, so they are relabelled only if selected.

The log records each press: role, result (`pressed`, `clicked` or `skipped`), time, the raw `AXPress` error when it was not success, and which activation step worked.

## Permission and lifecycle

**Accessibility permission.** Jumpr needs only this one. At launch without it, Jumpr asks the system once to prompt (which also adds Jumpr to the list) and opens Settings with the permission step at the top. Its button opens the exact System Settings pane (`Onboarding.accessibilityPane`), because the pane is hard to find by hand. A change in trust is learned from the `com.apple.accessibility.api` distributed notification, rechecked 0.5 s and 2 s after it fires, because the answer lags the notification. On gaining trust, Jumpr starts the key tap and switches web trees on; if the tap still cannot start, Settings shows a Relaunch button. On losing it, Jumpr stops the tap, cancels any session and shows Settings. A stable signing identity keeps the grant across rebuilds (see the README).

**Pause.** The `paused` preference is the single source of truth: the menu item writes it, and `defaults write` works the same way. Pausing cancels any session, makes the tap ignore the hotkey, and switches off every tree Jumpr switched on. Resuming switches trees on again.

**Lock.** `PowerSource` tracks three causes apart (session lock, display sleep, screen saver, in `LockCauses`), so that one ending cannot clear another that still holds. Every lock event cancels a running session, since a capturing key listener must never be live at a lock screen. The trigger also checks the lock live and ignores the hotkey while locked, so a missed notification can never make the hotkey dead. A hotkey press resyncs the causes. On unlock, Jumpr switches on trees it skipped while locked.

**Start at login** is opt-in: off until the user turns it on in Settings, backed by `SMAppService.mainApp`, and Jumpr only reads its state otherwise.

**The log** is `~/Library/Logs/Jumpr.log`: launch, trust, pause, lock, tree switching, each trigger's readout lines, each press, updates. It names apps and element roles; Jumpr never reads element text. Past about 1 MB (`LogFile.cap`) it moves to `Jumpr.log.1`, replacing the one there, and starts again, so a copy left running for months cannot fill a disk.

**Preferences** (names in `Keys`): `hotkey`, `labelSize`, `labelColor`, `labelTextColor`, `paused`, `showReadout`, `showAdvancedSettings`, and `webHostApps`, which is not a setting but Jumpr's remembered list of web-hosting apps. Sparkle keeps its own settings. Hotkey, readout and pause changes apply live through `DefaultsWatcher`, including changes made with `defaults write`; label settings apply on the next trigger.

## Updates

Jumpr updates through Sparkle, its only third-party dependency and its only network use. `scripts/build-app.sh` stamps the feed address and Sparkle public key into `Info.plist` (`SUFeedURL`, `SUPublicEDKey`). A development build gets a feed that goes nowhere and a placeholder key; `UpdatePolicy.isConfigured` sees that, so `UpdaterController` never starts the updater, "Check for Updates…" stays disabled, and Settings says updates are off. The build script applies the same rule to refuse a release build without a real feed and key.

Jumpr has no Dock icon and is rarely the active app, so a scheduled update alert could open unseen behind other apps. It uses Sparkle's gentle reminders instead: Sparkle shows a scheduled update itself only when it would be in immediate focus; otherwise Jumpr puts a dot on its menu bar icon and the menu item reads "Update Available…" until the user looks.

**Releases.** `scripts/release.sh <version>` builds the downloadable zip: a universal app, Developer ID signed, notarized and stapled, with Sparkle embedded, then a signed appcast for it. It uploads nothing. `--skip-notarize` makes a signed test build with no appcast. The feed address and the public key live in that script; read it for the details rather than this document.

## Known limits

- `AXManualAccessibility` cannot be read back, so Jumpr cannot tell whether another tool already had an app's tree on. On Pause and Quit it switches off every such tree it set, including one another tool had on.
- If Jumpr loses the Accessibility permission while running, it can no longer switch trees off: they stay on until those apps quit.
- While a password field has keyboard focus (secure input), the hotkey and Esc do not reach Jumpr.
- Menu bar extras belong to apps the window list does not name, so Jumpr remembers which apps own one, asking at trust, resume and unlock, and when an app launches or first comes to the front. An app that adds its icon later is not labelled until the next of those moments.
- A web-based app whose window was covered when Jumpr started gets its tree switched on when the app first comes to the front. If its window is uncovered without the app coming to the front, the first trigger shows few labels for it and the next one is complete.
- Pages in WebKit and Chromium apps can take a moment to get labels the first time, while the app builds its tree; the look-again pass adds them while the labels are up.
- Only standard accessibility roles are labelled, plus text that offers a press and a list's items with no role (see Scanning). Anything else that is clickable without being one of those gets no label.
- What an app does not put in its accessibility tree cannot be labelled. The pinned tiles at the top of Dia's sidebar are an example: a hit test there answers with the window itself.
- The window match relies on a private call, `_AXUIElementGetWindow`, with a fallback by process and frame. The third activation step relies on another private call.
- `JumprCore` is unit-tested; the app shell in `Sources/Jumpr` has no unit tests and is checked by running the app.

## Ideas not built

None of these is implemented.

- **A warm cache**, keeping scan results up to date in the background so labels appear almost instantly instead of after a fresh scan.
- **Scanning less on battery**, for example only the frontmost app.

## Debugging aids

- **`JUMPR_DEBUG_LABELS`**: set it in Jumpr's environment to log every label's role, process, window and position when a trigger completes, each narrowing as you type, and when the look-again pass finds nothing in a web view. It logs the letters you type, so leave it off otherwise.
- **`JUMPR_DEBUG_SIGNALS`**: set it to make two signals do something. `kill -USR1 <pid>` runs a trigger that scans and paints without capturing keys, cancelled after 2 s (a second USR1 within that time cancels it). `kill -USR2 <pid>` opens Settings by the same path as the menu item. Without the variable both signals are ignored, so a normal copy has no such hook.
- **`showReadout`**: a hidden preference that draws each trigger's timing on the main display: total time split into window list, scan and paint; label and app counts; then per app its time, elements read, labels and any timeout. The same lines are always written to the log.
- **`showAdvancedSettings`**: a hidden preference that shows the timing readout toggle in Settings.

Set the hidden preferences with `defaults write <bundle ID> showReadout -bool true`; the bundle ID is in `Resources/Info.plist`.
