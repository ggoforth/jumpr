# Jumpr v1 — design

|  |  |
|---|---|
| Date | 2026-11-04 |
| Status | Approved by Greg, 2026-11-04 |
| Evidence | Throwaway spike on branch `spike/cold-scan`, file `spike/Spike.swift` |

---

## 1. Intent

Jumpr lets you click anything on screen from the keyboard: press a hotkey, every
clickable thing gets a short letter label, type the label, it's clicked.

**Why it exists.** Greg tried Homerow. The idea worked, but:

- it felt slow to respond to the hotkey
- it only labels the current screen — he runs three
- onboarding was bad
- it costs $50

**The moment it's for.** Greg is testing an app on one monitor, with Claude desktop
on a second and a terminal on a third, all visible. He glances at Claude, hits the
hotkey, sees the label on "+ New", types it — and is in a new chat. No "switch app
first" step.

Personal tool first. What follows is undecided: after approving this design Greg
said to consider open-sourcing it and giving it away rather than selling it.
Nothing in v1 depends on which.

---

## 2. Goals

1. **Label everything visible, everywhere.** One hotkey labels every visible
   clickable element on every connected display, in every app — not just the
   focused one.
2. **One move to act.** Typing a label presses the element and brings its app and
   window forward.
3. **Works across macOS.** Native apps, web-based apps (Claude desktop, other
   Electron apps), browsers (links, buttons), the Dock, the menu bar, open menus
   (File, Edit, …), and menu bar extras.
4. **Feels instant.** Target: hotkey → first labels on screen in under 20 ms when
   the cache is warm. Fallback (nothing cached): about what the spike does today,
   ~110 ms typical.
5. **Does not eat battery.** No background work while nothing on screen changes.
6. **Onboarding that works.** First launch walks through the one permission and
   opens the right System Settings pane.
7. **Configurable.** Hotkey, label size, label color, text color, on-battery
   behavior, start at login.
8. **Shows where it's lacking.** A built-in timing readout, so slow apps and gaps
   are visible rather than guessed at.

## 3. Non-goals for v1

- Scroll mode. It is the planned next feature; v1 must not make it harder.
- Search by element text, right-click, double-click, drag, hover.
- Right-click (context) menus and other pop-up menus outside the menu bar.
- Clickable things that are not standard controls (web `div` buttons, Finder icons).
  The readout will show how much this matters before we spend on it.
- Smarter labels (stable between triggers, shortest labels nearest the cursor).
- Licensing, payments, auto-update, notarized public distribution.
- Mac App Store. Not possible: App Store apps must be sandboxed, and the sandbox
  blocks the Accessibility API this app is built on. Distribution will be direct.

## 4. Anti-goals

These make it a failure even if it technically works.

- **Battery drain or idle CPU.** Greg's words: he'd turn it off. This counts the
  whole machine: work Jumpr causes inside other apps (every scan runs on the
  scanned app's own main thread) is Jumpr's cost too.
- **Perceptible lag** between hotkey and labels.
- **Wrong click** — pressing something other than what the label was sitting on.
- **Hurting the keyboard.** Jumpr sits in the path of every keystroke; it must never
  stall typing.

---

## 5. What the spike proved

Measured on Greg's Mac: macOS 27, three displays (3440×1440 + two 1920×1080).
No cache; every trigger scanned from scratch.

| Stage | Time |
|---|---|
| List on-screen windows | 2–4 ms |
| Scan apps (in parallel) | 67–112 ms typical, up to ~270 ms on heavy web pages |
| Paint labels | 5–15 ms |
| First scan after launch | 250–285 ms (one-time connection cost per app) |

| App | Time | Elements read | Labels | Per element |
|---|---|---|---|---|
| Dia (browser) | 112 ms | 1,824 | 104 | 0.06 ms |
| Dia, heavy page | 254 ms | 4,067 | 87 | 0.06 ms |
| Claude desktop | 55 ms | 468 | 92 | 0.12 ms |
| System Settings | 51 ms | 226 | 108 | 0.23 ms |
| Dock | 3–6 ms | 28 | 26 | — |

**Lessons that shape the design**

- **Scanning is the whole cost.** Everything else is ~8 ms. With scan results
  already in hand, hotkey → labels is ~10 ms.
- **An app answers one request at a time.** Parallelism helps across apps, not
  inside one. Total time = slowest app. So a cache is the only route to instant,
  and native apps need it as much as web apps.
- **Pressing the element directly works.** 6 of 6 real clicks delivered; buttons
  and links via the accessibility "press" action, one tab via a synthetic mouse
  click.
- **Covered windows are skipped correctly** using the window server's front-to-back
  list.
- **The system hotkey API registered but never fired** on this setup. Detecting the
  hotkey in our own key listener works. Cause not found.
- **`⌃⌥J` never reached the app** from Greg's keyboard; `⌘⇧Space` does.
- **Signing with a stable identity** keeps the Accessibility grant across rebuilds.
- **Greg could not find the permission pane by hand.** A button that opens it
  directly is required, not a nicety.
- **Default 11 pt labels were too small.** 15 pt is the new default.

---

## 6. Decisions

### Greg decided

| Decision | Detail |
|---|---|
| Scope of labeling | All visible windows on all displays, all apps, at once |
| v1 quality bar | Best effort; no fill-order rules; make the gaps visible |
| Cache | Keep scan results warm in the background, invalidate smartly |
| Form factor | Menu bar only, no Dock icon, with a Settings window |
| Battery | Power-aware. On battery, spike speed (~110 ms) is acceptable outside the front app |
| Label look | Size and colors are user settings |
| Distribution | Direct sale later, not the App Store |
| Hotkey | Must be changeable in Settings; `⌘⇧Space` works for him |

### Claude's calls (not yet confirmed by Greg — check these while reading)

| Call | Why |
|---|---|
| Swift + AppKit; SwiftUI only in Settings; no third-party dependencies | Speed in the hot path; nothing to audit or update |
| Swift package + a small build script that assembles and signs the `.app` (as the spike does), not an Xcode project | Plain files, easy for agents to edit and for `swift test` to run |
| Requires macOS 15 or later | Personal tool on macOS 27; widen before any commercial release |
| Bundle ID `com.greggoforth.jumpr` | Placeholder; change freely before distribution |
| Default hotkey `⌘⇧Space` | The one that worked |
| Hotkey and label typing both go through one always-on key listener | The system hotkey API didn't fire; the listener is needed for typing anyway |
| Always re-check every visible window in the background after painting from cache | Makes correctness independent of how well each app reports changes |
| Never press an element that has moved away from where its label was drawn | Guards the "wrong click" anti-goal |
| A window known to be stale waits for its fresh scan instead of showing old labels | Labels that appear and then jump read as broken; a ~100 ms wait in one window does not |
| Background scans are capped at ~5% of any app's time, and paused for windows that won't stop changing | Scans run inside the other app; uncapped, they'd cause stutter and battery drain there |
| Web-based apps get their accessibility tree switched on while they have a visible window, and switched back off on Pause or Quit | Without it they get no labels at all; with it they do extra work for as long as it's on |
| After pressing a menu bar item, label the opened menu automatically | Otherwise every menu takes two hotkey presses |
| On battery, default mode is "front app only"; Low Power Mode counts as battery | Keeps the likeliest target instant at one app's worth of work |
| One private system call to match an accessibility window to its on-screen window | Only reliable way to know which window is on top; fallback described below |
| Placeholder icons: a system symbol in the menu bar, a simple generated app icon | Real icon is a pre-launch task |

---

## 7. How it works

### 7.1 The flow

```
hotkey
  │
  ├─ list on-screen windows (front to back)                       ~3 ms
  │
  ├─ for each visible window:
  │     cached and clean → paint its labels now                   ~5 ms
  │     known stale      → wait for its fresh scan, then paint
  │     never scanned    → scan it now, paint when its app finishes
  │
  ├─ in the background: re-scan every window painted from cache,
  │     fix up labels that moved, vanished, or appeared
  │
  └─ user types a label
        → re-read that element's position
        → still under its label?  press it, bring its app forward
        → moved or gone?          do nothing; labels are already correcting
```

### 7.2 Parts

| Part | Job |
|---|---|
| Key listener | Sees every key press. Idle: looks only for the hotkey, passes everything else through untouched. Label mode: swallows plain keys and feeds them to the label session. |
| Window snapshot | Asks the window server what is on screen, front to back, with bounds. Used to skip covered windows and covered elements. |
| Scanner | Walks one app's accessibility tree and returns its clickable elements with their visible rectangles. Same algorithm as the spike. |
| Cache | Per window: last scan's elements, when it was scanned, whether it's known stale. |
| Watcher | Subscribes to each watched app's change notifications and to system events; marks windows stale and schedules re-scans. |
| Power policy | Decides which windows the watcher keeps warm, from power source and the user's setting. |
| Overlay | One transparent, click-through window per display, always present; labels are layers added and removed. |
| Label session | Typed-prefix filtering, backspace, Esc, match. |
| Presser | Brings the app and window forward and presses the element. |
| Settings + onboarding | SwiftUI window; preferences in user defaults. |
| Menu bar item | Settings…, Pause / Resume, Quit. |
| Readout | Optional on-screen timing panel plus a log file. |

### 7.3 Scanner (carried over from the spike)

- One batched request per element: role, position, size, children, enabled.
- Clip to the window; narrow the clip at each scroll area; skip any subtree whose
  frame is entirely outside the clip. This is what keeps long web pages affordable.
- Tables and outlines: ask for visible rows only. Skip column elements (they repeat
  the rows' cells).
- Do not descend into leaf controls (buttons, links, checkboxes, text fields, …).
- Menus: descend only into the menu that is open.
- An element is labeled only if the topmost on-screen window at its center is its
  own window, or a helper window of the same app (popover, sheet, menu).
- Skip a window outright if a 5×5 grid of sample points finds none of it on top.
- Per-app budget of 500 ms and a 250 ms per-request timeout, so one hung app cannot
  hold up the rest. A blown budget returns what was found and is flagged in the readout.
- Apps are scanned in parallel; each app serially.
- Dock: walk the Dock's own element tree. Menu bar: the frontmost app's menu bar.
  Menu bar extras: each app's extras bar.
- Web-based apps keep their accessibility tree off until asked, and do extra work
  for as long as it is on. Rules:
  - Ask an app to turn its tree on (`AXManualAccessibility`) the first time it has
    a visible window — in every power mode, because without it the app gets no
    labels at all.
  - Remember which apps Jumpr switched on, and switch them back off on Pause and
    on Quit.
  - Use the heavier `AXEnhancedUserInterface` only for browsers that return an
    empty tree without it — it has known side effects on window animation.
  - The standing cost of leaving the tree on is not yet measured. Measuring it is
    an early build task (section 8); if it is large, bring it back to Greg before
    building further on this rule.

**Clickable roles in v1:** button, link, checkbox, radio button, pop-up button, menu
button, disclosure triangle, slider, incrementor, color well, text field, text
area, combo box, menu item, menu bar item, table/outline row, Dock item. Disabled
elements are skipped.

**Matching windows.** `_AXUIElementGetWindow` (private) gives the window-server ID
for an accessibility window. If it ever stops working, fall back to matching by
owning process plus identical frame.

### 7.4 Cache and watcher

**What is cached:** per on-screen window, the scanner's output.

**What marks a window stale:**

- From the app: window created, moved, resized, minimized or restored; focused
  window or element changed; layout changed; element destroyed; selection changed;
  menu opened or closed; web page finished loading; title changed.
- From the system: app launched, quit, activated, hidden, shown; Space changed;
  displays changed; wake.

**What happens then:** a re-scan of just that window, after changes stop arriving
for a settle time (start at ~300 ms; tune with the readout), and only if the
window is visible and the power policy says to keep it warm. A burst — scrolling,
typing, an animation, a chat reply streaming in — produces one re-scan when it
ends, not a stream of them.

**Limits on background scans.** A scan runs on the scanned app's main thread, so
it can make that app stutter and costs that app's battery. Background re-scans are
therefore bounded per app:

- **Spacing.** After a background scan of an app that took *t*, the next one for
  that app starts no sooner than 20 × *t* later, and never less than 1 second
  later. That caps the load Jumpr puts on any app at about 5% of its time.
- **Give up on restless windows.** If a window goes stale again within a second of
  being re-scanned, three times running, stop keeping it warm until it has been
  quiet for 2 seconds. Until then it is simply "known stale" and gets scanned on
  demand.
- **One at a time.** Never two scans of the same app at once. A trigger that needs
  a window whose scan is already running waits for that scan rather than starting
  another.
- **Low priority.** Background scans run at utility priority; scans the user is
  waiting on run at the highest.

These limits apply only to background work. A scan the user asked for by pressing
the hotkey always runs immediately.

**After Jumpr's own press.** The window just acted on is about to change, and the
next trigger is likely aimed at it. Mark it stale at once and re-scan it ahead of
the queue, exempt from the spacing rule, as soon as its changes settle (or after
~100 ms if the app reports none). This is what keeps chained use — press, then
trigger again within a second — fast.

**No timers.** Nothing polls. If nothing changes, Jumpr does nothing.

**Stops entirely** while the screen is locked, asleep, or the screen saver is up,
and when the user picks Pause.

**Why re-check on every trigger anyway.** Apps differ in how faithfully they report
changes; web content is the worst (scrolling a page often reports nothing). Rather
than trust each app, every trigger paints clean windows from cache and then
re-scans them in the background. Cost: one spike-sized scan per trigger, only when
the user asked for labels. Result: a stale label lives ~100 ms at most, well under
the time it takes to read and type one.

**Known-stale windows are held, not painted.** If the watcher already knows a
window changed since its last scan, its old labels are not shown. That window gets
its labels when its fresh scan lands (typically 50–250 ms); every other window is
labeled immediately. Old labels that appear and then jump or vanish read as broken;
a short wait in one window does not. So the under-20 ms target applies to clean
windows, and the priority re-scan after Jumpr's own press exists to make the window
being worked in clean again before the next trigger.

**Fixing up labels after the re-check:**

- element gone → remove its label
- element moved → move its label
- new element → add a label from the unused ones
- a label, once shown for an element, never changes to a different element during
  that trigger

### 7.5 Labels

- Letters only, home row first: `ASDFGHJKL` then the rest.
- All labels in one trigger have the same length, so no label is the start of
  another.
- Length is chosen before the scans finish, from the last known element counts,
  with headroom: 1 letter up to 26, 2 up to 676, 3 beyond. If the real count
  overflows, the extras go unlabeled and the readout says so.
- Placement: centered on small elements, at the left edge (vertically centered) of
  wide ones, always inside the visible part of the element and inside the display.
- Typing narrows: labels that no longer match disappear. Backspace undoes a letter.
  Esc or the hotkey cancels. Keys with ⌘, ⌃ or ⌥ pass through to the system.

### 7.6 Pressing

1. Re-read the element's position (one request, under a millisecond).
2. If it no longer overlaps where its label was drawn, or it no longer exists: do
   nothing.
3. If it belongs to a window: bring that app forward and raise that window.
4. Text fields and text areas: synthetic mouse click at the center of the visible
   part (places the cursor).
5. Everything else: accessibility "press". A "cannot complete" reply counts as
   delivered — apps answer that way while a menu they just opened is tracking.
6. If "press" is unsupported: synthetic click, after a ~40 ms pause for the raise
   to land.
7. If the pressed element was a menu bar item, or a menu item with a submenu: when
   the menu opens, label it automatically.

All of this runs off the main thread, so a slow app never stalls the key listener.

### 7.7 Power

| Situation | Windows kept warm | Hotkey → labels |
|---|---|---|
| Plugged in | All visible windows | ~10 ms |
| Battery or Low Power Mode, "Full speed" | All visible windows | ~10 ms |
| Battery or Low Power Mode, "Front app only" (default) | Frontmost app's windows | Front app ~10 ms; the rest scan on demand |
| Battery or Low Power Mode, "Scan on demand" | None | Spike speed, ~110 ms typical |

The policy switches live when the power source changes. One screen on a laptop is
just fewer windows; nothing about the feature set changes.

### 7.8 Settings

| Setting | Control | Default |
|---|---|---|
| Hotkey | Click, then press the new combination | `⌘⇧Space` |
| Label size | Slider, 10–32 pt | 15 pt |
| Label color | Color picker | Yellow `#FFD60A` |
| Text color | Color picker | Black |
| Preview | Live sample label | — |
| On battery | Full speed / Front app only / Scan on demand | Front app only |
| Start at login | Toggle | On |
| Permission | Status + "Open Accessibility Settings" button | — |
| Timing readout | Toggle | Off |

- Label settings take effect on the next trigger.
- The hotkey recorder must reject combinations with no modifier, and must not let
  Jumpr's own listener swallow the keys while recording.

### 7.9 Onboarding

- First launch, or any launch without the permission: the Settings window opens
  with the permission step at the top.
- "Open Accessibility Settings" opens the exact pane
  (`x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`).
  Greg went to the wrong Accessibility pane by hand; this button is the fix.
- The status flips to granted on its own, without a relaunch. If the key listener
  cannot start after the grant, show a "Relaunch Jumpr" button.
- Once granted, show the hotkey and a one-line "try it now".

### 7.10 Readout

Off by default; a toggle in Settings. After each trigger, a panel on the main
display shows:

- time to first labels, time to all labels
- window list / scan / paint split
- per window: served clean from cache, held for a fresh scan, or scanned cold —
  and how long until its labels appeared
- per app: time, elements read, labels
- per app, over the last minute: number of background scans and their total time
  (the load Jumpr put on that app)
- flags: budget blown, labels overflowed, window given up on as restless

The same lines go to `~/Library/Logs/Jumpr.log`. This is how "see where we are
lacking" is answered from here on.

---

## 8. How we'll know it works

**Automated (`swift test`)** — the logic that can be tested without a live screen:

- label generation: fixed length, no label a prefix of another, capacity, overflow
- which window is on top at a point; the helper-window rule; the 5×5 skip rule
- clip and prune geometry
- cache state: change events → stale → settle → one re-scan request
- background limits: spacing, giving up on a restless window and resuming, one scan
  per app at a time, priority re-scan after a press
- trigger with a clean, a stale and a never-scanned window: which paint now, which wait
- label fix-up after a re-check: gone, moved, new, never reassigned
- power policy: source + setting → which windows are warm
- label session: narrowing, backspace, Esc, pass-through of modified keys
- press safety: moved or missing element → no press

The accessibility and window-server calls sit behind a thin layer so these tests
run on plain data.

**Measured on Greg's three-display setup**, with Dia, Claude desktop and one native
app visible, read from the readout:

| Check | Pass |
|---|---|
| Hotkey → first labels, cache warm | under 20 ms |
| Hotkey → all labels, nothing cached | under 150 ms typical |
| CPU while windows are static for 5 minutes | none attributable to Jumpr |
| Scrolling a web page continuously | one re-scan after it settles, not a stream |
| A chat reply streaming in a visible Claude window | no scans while it streams; one after it ends |
| Typing for a minute in a visible window | background scan time for that app ≤ 5% of the minute |
| Press something, trigger again 1 second later | the pressed window's labels appear within 150 ms |
| Energy use of Dia and Claude desktop, accessibility tree on vs off, 5 minutes idle and 5 minutes of normal use (Activity Monitor) | recorded; reviewed with Greg before the watcher is built on top |

**By hand:**

1. Claude desktop on another display → label on "+ New" → new chat, Claude in front.
2. A link in Dia.
3. A Dock item.
4. Menu bar → File → an item, with one hotkey press.
5. A menu bar extra.
6. Unplug the laptop → readout shows only the front app served from cache.
7. Fresh install → permission granted through the button, no relaunch.
8. Change the hotkey, label size and colors → all take effect.

---

## 9. Risks

| Risk | Handling |
|---|---|
| Apps report changes unreliably | Re-check every visible window on every trigger (7.4) |
| Chatty apps flood the watcher | Settle time; small notification set; drop events for hidden windows |
| Background scans make other apps stutter or drain battery | Per-app spacing (~5% cap), giving up on restless windows, readout shows the load per app (7.4, 7.10) |
| Leaving the accessibility tree on costs web-based apps energy | Unmeasured. Measure first (section 8); switched off on Pause and Quit |
| The spike only measured cold scans, never the watcher under sustained use | The acceptance checks in section 8 cover active use; numbers in 7.4 are starting points |
| Key listener is in the path of all typing | Its handler does no blocking work; scans and presses run elsewhere; re-enable it if the system switches it off |
| Password fields block key listeners system-wide | Known limit: the hotkey won't fire while one is focused. Same for every app of this kind |
| The private window-matching call changes | Fallback by process + frame (7.3) |
| System hotkey API silently not firing | Avoided by design; cause still unknown |
| Only tested on macOS 27 | Fine for a personal tool; test older versions before any release |

### Known limits

- `AXManualAccessibility` cannot be read back, so Jumpr cannot tell whether another tool already had an app's tree on. On Pause and Quit it switches off every tree it set, including one another tool had on.
- If Jumpr loses the Accessibility permission while running, it can no longer switch trees off: they stay on until those apps quit.
- While a password field has keyboard focus (secure input), the hotkey and Esc do not reach Jumpr.
- Menu bar icons belong to apps the window list does not name, so Jumpr remembers which apps own one (asked at trust, resume, unlock, and when an app launches or first comes to the front). An app that adds its icon later is not labelled until the next of those moments.
- A web-based app whose window was covered when Jumpr started gets its tree switched on when the app first comes to the front. If its window is uncovered without the app coming to the front, the first trigger shows few labels for it and the next one is complete.

---

## 10. Left to the builder

- File and module layout.
- Exact settle time, spacing numbers and notification set — tune with the readout,
  within the ~5% cap.
- Label placement details.
- Hotkey recorder implementation (small, in-house; no dependency).
- How much of the spike to lift. It is throwaway, but the scanner, overlay and
  presser are a working reference.
