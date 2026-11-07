# Working on Jumpr

For coding agents and for people. This file holds the rules you cannot work out from the code. How Jumpr works is in [docs/design.md](docs/design.md); what it does for a user, and how to build it, is in the [README](README.md).

## What decides a change

Jumpr puts a label on everything clickable, on every display, in about a tenth of a second. Judge a change against these, in this order.

1. **It stays fast.** Hotkey to labels should feel instant, and Jumpr sees every key press, so it must never stall typing. A change that costs time needs a measurement that says how much.
2. **It stays private.** Everything happens on the Mac. Jumpr never reads, stores or logs what is on screen: no titles, no values, no text, no typed keys. It does not record the screen. The app's only network use is the update check.
3. **Rules are general.** The tree walk, the labelling rules and the presser never ask which app they are looking at. A gap found in one app becomes a rule about roles or behaviour that holds in every app, or it is not added.
4. **A rule comes with evidence.** Before adding a labelling rule, count what it adds and what else it touches across several real apps. A rule that fixes one app and adds noise to five is a bad trade.
5. **It works before it grows.** A reliable small set of behaviours beats a wide flaky one. A setting is a cost, not a way to avoid a decision.
6. **It does nothing when idle.** No timers and no polling. Work happens because the user pressed something.

If a change does not clearly fit, open an issue and discuss it before building it.

## Standing exceptions

Two lists of app identifiers exist, both about timing, neither about what gets a label: `TreeRegistry.chromiumIDs` and `Controller.webKitHostIDs`. Do not add to them or create a third. The aim is to replace them with a decision made from how the app behaves.

## Code standards

Clean, fast, tested. Always.

- **Logic goes in `JumprCore`.** It is pure: no AppKit, no accessibility calls, no third-party code. The accessibility tree reaches it through the `AXNode` protocol, so every rule runs on plain data in a test. `Sources/Jumpr` is the shell and stays thin.
- **A failing test comes first.** Every change in behaviour starts with a test that fails for the right reason, then the code that makes it pass.
- **Tests read as sentences.** Name a test for the behaviour it protects (`aRowFilledByAButtonIsLabeledOnceOnTheButton`), and put the real case that prompted it in a comment above.
- **The smallest change that solves it.** No speculative options, no unused code. Delete what nothing calls.
- **Comments say why.** Name the case that forced the code to be this way. Do not restate what the code does.
- **No new dependencies.** Sparkle, the updater, is the only one.

## Contracts the code relies on

Breaking one of these does not fail a test. It makes Jumpr slow or makes typing stall.

- **One accessibility request per element in the walk.** Anything more must be rare and argued for in a comment, as the press check for text is.
- **No accessibility call on the main thread.** An app answers on its own main thread and can take as long as it likes. Every call goes through that app's serial queue in `Scanner`.
- **Every element gets the request timeout** (`axTimed`), so one hung app cannot hold up the rest.
- **Scan results respect the generation.** A callback from an old trigger is dropped before it touches the overlays or the session.
- **Coordinates are global, top-left origin**, everywhere except where AppKit hands over a display frame (`DisplayGeometry.swift` converts).
- **Jumpr switches off only what it switched on** in other apps, and leaves everything else alone.

## Commands

| Command | What it does |
|---|---|
| `make test` | Runs the unit tests (`swift test`). CI runs the same on every pull request. |
| `make run` | Builds `build/Jumpr.app` and opens it, stopping any running copy first |
| `make run-direct` | The same, started from the shell so it uses that shell's Accessibility access |
| `CODESIGN_IDENTITY=- make run` | Builds with ad-hoc signing, for a machine with no signing identity |

## Checking a change in the running app

Tests cover the rules. They do not cover what real apps report, so check there too.

- **Probe before you write a rule.** A small script that walks an app's accessibility tree and prints roles, sizes and counts tells you what the app really exposes. Print nothing else: no titles, values or text.
- **Read the log after a trigger.** `~/Library/Logs/Jumpr.log` gives each app's node count, label count and time. Compare before and after.
- **The debugging aids** are described in [docs/design.md](docs/design.md#debugging-aids). One of them shows labels without capturing keys, which is the safe way to trigger from a script.
- **Do not send clicks or keys into someone's apps to test.** Show the labels, read the log, and let the person press.

## Words used here

| Word | Meaning |
|---|---|
| Trigger | One press of the hotkey, from the window list to the labels on screen |
| Session | The time labels are up and Jumpr is taking the keys |
| Walk | The pass over one window's accessibility tree that finds targets |
| Target | An element that gets a label |
| Web content | Anything under a web area: a browser page or a web-based app's interface. It follows different rules for pressing and timing |
| Tree switching | Asking a web-based app to produce its accessibility tree, and undoing that on Pause and Quit |

## Documents

Each fact has one home.

- **[docs/design.md](docs/design.md):** how it works, measured timings, known limits, ideas not built.
- **[README](README.md):** what a user sees, installing, building.
- **`site/`:** the website, including the privacy page.
- **This file:** rules and contracts only.

Update the documents in the same change as the code. When a document and the code disagree, the code is right and the document gets fixed.

A change to what Jumpr reads, stores or sends must update the privacy page (`site/privacy.html`) and the README in the same change. Their claims have to stay true.

## Branches and releases

- Work on a branch and open a pull request. `main` is what ships next.
- A commit message says what changed and why, in plain sentences, with the measurement if there is one.
- Every release has notes in `site/releases.json`, landed by pull request before the tag. The `release-notes` skill drafts them.
- Tags, releases, the update feed and the website are the maintainer's. Do not tag, publish or deploy.
