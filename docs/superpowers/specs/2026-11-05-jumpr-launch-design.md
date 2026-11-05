# Jumpr launch: direct sale

**Date:** 2026-11-05
**Status:** draft, waiting for Greg's approval
**Builds on:** `2026-11-04-jumpr-design.md` (the app itself). Where the two disagree, this one wins.

---

## 1. Intent

Sell Jumpr directly for **$10, one time**, as side cash.

Greg's words: "we just do it direct and treat it like side cash."

So every choice here favors **least ongoing effort**: nothing to babysit, nothing that pages him, few moving parts. The model to copy is Watchflows (`/Users/greg/Projects/watchflows`), cut down to what a $10 utility needs.

---

## 2. Goals

- A stranger can find the site, download Jumpr, try it, pay $10, get a key by email, and unlock the app. No human in the loop.
- A release is one command after Greg tags.
- Customers learn about new versions without Greg emailing anyone.

## 3. Non-goals

- **Setapp.** Dropped on 2026-11-05. Nothing here should block adding it later (Watchflows shows the pattern: a second build of the same code).
- Mac App Store (the sandbox blocks the Accessibility API).
- Open source.
- Subscriptions, accounts, sign-in, device limits, licence revocation.
- The background cache and watcher (v1 plan Tasks 10, 13, the wiring half of 14). Post-launch.
- Scroll mode.

## 4. Anti-goals (a failure even if it works)

- **Greg has to do something for each sale or each support-free day.**
- **A paying customer is locked out** by a licence bug, a clock change, or the site being down. The licence check never needs the network.
- **Touching Watchflows' live systems.** Jumpr gets its own function, its own keys, its own Stripe product. Copy code; never share a running resource that takes Watchflows' money.
- **The app phones home.** The only request Jumpr ever makes is the update check (section 8).

---

## 5. Decisions

### Greg decided

| Decision | When |
|---|---|
| Sell direct, $10 one time, through Stripe, "same setup as Watchflows" | 2026-11-05 |
| A simple marketing site | 2026-11-05 |
| No Setapp | 2026-11-05 |
| Tags are made by Greg, by hand, in GitHub | standing rule |

### Claude's calls (not confirmed by Greg — check these while reading)

| # | Call | Why | Cost if wrong |
|---|---|---|---|
| C1 | **7-day full trial**, then the hotkey shows a buy prompt | Watchflows does 14; at $10 a week is enough to decide | Change one number |
| C2 | **Launch without the background cache** | Greg called 90–150 ms "very fast". The cache is the biggest remaining build. | Ship it as an update |
| C3 | **No Sparkle. A small "update available" notice** that links to the download | Sparkle means a third-party framework, nested signing, a second signing key, and a feed to maintain. Side cash. | Customers replace the app by hand; add Sparkle later |
| C4 | **No "recover my key" page.** Lost key → email support; a one-line tool issues a new key | Watchflows' version needs a database and rate limiting | A few support emails |
| C5 | **Build for Apple silicon and Intel, but only claim "macOS 15 or later"** on the site | One extra flag; Intel Macs still run macOS 15. No Intel Mac here to test on, so the site makes no Intel promise. | An Intel buyer hits a bug and gets a refund. Drop the flag. |
| C6 | **Keep the bundle ID `com.greggoforth.jumpr`** | Changing it later resets every customer's Accessibility grant and settings | None if kept forever |
| C7 | **No analytics on the site** at launch | One less account and no consent question | Add Plausible later (Watchflows' snippet) |
| C8 | **Site is 4 pages** (section 9) | Simple, as asked | Add pages |
| C9 | **Hide the "On battery" picker and the timing readout toggle** in Settings | Without the cache the picker does nothing; the readout is a builder's tool | Un-hide |
| C10 | **Releases run from a script on a Mac that has the signing certificate**, started by hand after Greg tags | Watchflows' Mac mini flow is 1,400 lines. Wire Jumpr into it later if wanted. | One command per release instead of zero |
| C11 | **Start at login is opt-in only** | A paid app should not add itself to login items unasked | Flip the default |
| C12 | **One payment function serves Stripe test mode and live mode** | Each Stripe event says which mode it is; the function picks that mode's settings. Test settings are optional. | Run two functions instead |
| C13 | **Jumpr gets its own bucket, CDN and a login limited to them**, inside the same AWS account as Watchflows | Nothing Jumpr does can touch Watchflows' site or downloads | Greg prefers a separate account: only the setup steps change |
| C14 | **This Mac is the release Mac.** It already has a Developer ID Application certificate. | Checked on 2026-11-05 | Use the Mac mini: same script |
| C15 | **Greg's hands-on checks do not gate the build.** They are batched and brought to him once; icon options go to him early. | He should not be interrupted task by task | A late finding costs some rework |
| C16 | **A throwaway test key pair lives in the repo**, clearly named, used only by tests. The real public key is a placeholder until the real pair exists, and `make release` refuses to run while the placeholder is compiled in. | Tests need a pair; a release must never ship one that cannot be unlocked | None |

### Open — only Greg can answer

| # | Question | Blocks |
|---|---|---|
| Q1 | **Domain?** | Site, key email sender, update check address. Use the placeholder `DOMAIN` until known. |
| Q2 | **Support email address?** | Site footer, key email, refund policy |
| Q3 | **Who creates the cloud pieces** (section 12): Greg by hand, or Claude with command-line access to AWS and Stripe? | Nothing in the code; only go-live |

---

## 6. The parts

| Part | What | New or reused |
|---|---|---|
| A | Finish the app for strangers (section 7) | Existing code |
| B | Licence and trial in the app (section 8) | Ported from Watchflows |
| C | Update notice (section 8) | New, small |
| D | Marketing site (section 9) | Watchflows' pattern |
| E | Payment → key by email (section 10) | Watchflows' function, trimmed |
| F | Release script (section 11) | New, small |

Order: A, B and C are app work and can go first. D and E need the domain to go live but can be built against the placeholder. F last.

---

## 7. Part A — finish the app for strangers

This replaces the rest of the v1 plan.

**Do**

- Finish the scripted live checks: Settings, hotkey recorder, Pause, Quit, Control Center press, lock / unlock (JUM-20). Then Greg's look-and-press checks, including the permission grant flow from a clean install.
- Fix overlapping labels on a row and the button inside it (JUM-21).
- A real icon (1024 px source). Greg's taste: show him options.
- Start at login: opt-in toggle only; remove the automatic registration (C11).
- Settings: hide the "On battery" picker and the readout toggle (C9). Keep both reachable by a `defaults write` key.
- Menu bar menu gains: version, "Check for Updates…", "Licence…".
- Cap the log file (1 MB, keep one older file). `JUMPR_DEBUG_LABELS` stays off unless set.
- Forget an app's scan queue and tree record when the app quits (a long-running app must not grow).
- README: what it does, permissions, known limits.

**Do not do for launch:** v1 plan Tasks 10, 13, the wiring half of 14, and the full readout in 15. The cache rules already built (Tasks 11, 12, 14's rules) stay in the library with their tests, unused.

---

## 8. Parts B and C — licence, trial, update notice

### Licence (port, do not redesign)

Source to port: `Watchflows/Services/LicenseManager.swift` and `LicenseStorage.swift`. Strip everything about subscriptions, Cloud, relay and Sparks.

- **Key:** `"JR-" + base64url(JSON({email, ts, v, sig}))`, `v` = 1. `sig` is an Ed25519 signature over the exact JSON of `{email, ts, v}`. Same construction as Watchflows; keep its byte-exact rules.
- **Jumpr has its own key pair.** The public key is a constant in the app. The private key never enters the repo.
- **Check:** offline, with CryptoKit. No server, no device limit, no expiry.
- **Stored** as a file in `~/Library/Application Support/Jumpr/`, not the Keychain (Watchflows moved off the Keychain because updates orphaned its items).

### Trial

- 7 days from first launch, full features (C1).
- The start date is stored twice (defaults and a file); the earlier wins.
- Clock set backwards: never extends the trial beyond 7 days from the stored start; never locks out a licensed user.
- No special test switch. Because the earlier date wins, back-dating either store ends the trial (that is how check 13.2 is run); deleting both restarts it. A user who deletes both gets a new trial. Accepted at $10, as in Watchflows.

### States and what the user sees

| State | Hotkey | Settings shows |
|---|---|---|
| Trial, N days left | Labels | "Trial: N days left" · Buy · Enter key |
| Licensed | Labels | "Licensed to <email>" |
| Trial over | **Opens the Licence section instead of labels** | "Your trial has ended" · Buy $10 · Enter key |

- Trial over never disables Settings, Pause or Quit, and never swallows keys.
- "Buy" opens the site's buy link. "Enter key" takes a pasted key and says plainly whether it worked.
- The state rules live in `JumprCore` (pure, unit-tested): trial arithmetic, clock-backwards cases, key parsing, signature check against test vectors made with a test key.

### Update notice (C3)

- At launch, and when the Mac wakes or unlocks, if more than 24 hours passed since the last check: fetch `https://DOMAIN/releases.json`. No repeating timer.
- Shape: `{"version": "1.1.0", "url": "https://DOMAIN/download/Jumpr.zip", "notes": "…"}`.
- Newer than the running version → the menu shows "Update available: 1.1.0", which opens `url`. Nothing is downloaded or installed automatically.
- "Check for Updates…" in the menu checks now and reports the result.
- A Settings toggle, on by default, turns the automatic check off.
- The request carries nothing about the user. A failed check is silent.

---

## 9. Part D — marketing site

**Pattern:** Watchflows' `site/`: plain HTML, Tailwind compiled ahead of time and committed, hosted on S3 behind CloudFront, deployed by a GitHub workflow on push to `main` when `site/**` changes. The deploy must not delete `download/*` or `releases.json`.

**Lives in:** `site/` in the `jumpr` repo.

**Pages (C8)**

| Page | Content |
|---|---|
| `index.html` | What it is in one line. What makes it different: **every display at once**, and **speed**. A visual of labels over an app. Download (free trial) and Buy $10. Short FAQ: permissions, privacy, refunds, system requirements. |
| `thank-you.html` | "Check your email for your key." How to enter it. Download button. |
| `privacy.html` | Jumpr reads what is on screen locally to place labels. It sends nothing. One update check a day. Payment is handled by Stripe; the key email by Resend. |
| `terms.html` | Short terms and the refund policy: 14 days, email support. |

**Copy rules**

- Lead with the difference, not with a competitor. Do not name other products on the home page.
- Plain claims only; any speed number must be one that was measured.
- Light and dark.

**Left to the builder:** layout, the hero visual (an HTML/CSS mock of labels is fine; no screen recording is required), wording. Greg approves the look before it goes live.

---

## 10. Part E — payment and the key email

**Flow:** Buy button → Stripe Payment Link ($10, one time, collects email, redirects to `thank-you.html`) → Stripe calls Jumpr's function → the function makes the key and emails it.

**The function** is a trimmed copy of `/Users/greg/Projects/watchflows/lambda/stripe-webhook/` (`index.mjs`, `lib/license.mjs`, `comp.mjs`), living in `lambda/stripe-webhook/` in the `jumpr` repo, deployed as its **own** AWS Lambda with its own address.

| Keep | Drop |
|---|---|
| `POST /webhook`, `GET /health` | `POST /recover` and its database and rate limiting (C4) |
| Signature check on every call | Anything about subscriptions |
| Acts only on a paid one-time session whose price is in the allowed list; refuses to run if that list is unset | |
| Key made from the buyer's email and the session's time (same inputs → same key) | |
| Email through Resend; if the send fails, answer with an error so Stripe retries | |

- **Settings by name** (values never in the repo): `STRIPE_WEBHOOK_SECRET`, `STRIPE_SECRET_KEY`, `LICENSE_PRIVATE_KEY`, `LICENSE_PRICE_IDS`, `RESEND_API_KEY`, `FROM_EMAIL`, `DOWNLOAD_URL`.
- **Test mode (C12):** optional `STRIPE_WEBHOOK_SECRET_TEST` and `STRIPE_SECRET_KEY_TEST`. An event marked as test mode is checked and handled with those; if they are unset it is refused. `LICENSE_PRICE_IDS` lists the live and the test price. A key bought in test mode is a real, working key, and its email says "TEST" in the subject.
- **The email:** the key, where to paste it, the download link, the support address. Plain and short.
- **Comp / replacement keys:** `make license EMAIL=…` on a machine that has the private key.
- **Deploy:** a GitHub workflow on push to `main` when `lambda/**` changes, as in Watchflows.
- **Tests:** the key generator against the app's verifier (a key made by the function must unlock the app's check, using a shared test key pair); the handler's accept / ignore / refuse cases with recorded sample events.

**Refunds:** by hand in Stripe. A refunded key keeps working (the check is offline). Accepted.

---

## 11. Part F — release

`make release VERSION=1.0.0`, run on a Mac that has the certificate, after Greg has tagged `v1.0.0`:

1. Refuse to run unless the checked-out commit is the one the tag points at and the tree is clean.
2. Build release, Apple silicon + Intel (C5). Stamp the version into the app.
3. Sign with **Developer ID Application**, hardened runtime.
4. Notarize (`notarytool`, a saved profile named `jumpr-notary`) and staple.
5. Zip with `ditto`; reject a zip containing `__MACOSX`.
6. Upload `download/Jumpr-<version>.zip` (never overwritten) and `download/Jumpr.zip` (always the latest).
7. Write and upload `releases.json`.
8. Refresh the CDN for those paths.
9. Print what it uploaded and the checks to run by hand.

- Development builds keep the "Apple Development" identity (`make app`, `make run`).
- The script never creates or pushes a tag.
- It refuses to run while the placeholder licence public key is compiled in (C16).
- Uploads use a named AWS profile on the release Mac (`jumpr`), never keys in the repo. The notary profile name can be overridden, so an existing saved profile for the same Apple account can be reused.
- If the notary profile or the AWS profile is missing, the dry run still works and says which is missing.
- A dry-run mode does steps 1–5 and stops.

---

## 12. Things only an account owner can do

Needed before go-live. Greg, or Claude if given access (Q3).

| Where | What |
|---|---|
| Registrar / DNS | Register the domain; point it at the CDN; records for the email sender |
| AWS | Bucket + CDN + certificate for the site; the function + its public address + its settings |
| Stripe | Product "Jumpr", $10 one-time price, Payment Link (collect email, redirect to thank-you), webhook endpoint for `checkout.session.completed` |
| Resend | Verify the domain; an API key |
| Apple | Developer ID Application certificate on the release Mac; the `jumpr-notary` profile |
| GitHub | Secrets for the two deploy workflows |
| Anywhere safe | Generate Jumpr's licence key pair; store the private half (Watchflows keeps its in 1Password) |

Assumed, not confirmed: the same Apple developer, Stripe, AWS and Resend accounts as Watchflows.

Already in place: the GitHub repo (`ggoforth/jumpr`, private) and a Developer ID Application certificate on this Mac.

The site deploy copies Watchflows' workflow, which deletes remote files that are not in `site/`. Its exclusions must name `download/*` and `releases.json`.

---

## 13. How we'll know it works

**Automatic**

- Unit tests: trial arithmetic and clock cases; key parse and signature check; a key from the function unlocks the app; version comparison for the update notice; the function's accept / ignore / refuse cases.

**By hand, before go-live**

1. Clean Mac user: download from the site, open, grant the permission, labels appear. Gatekeeper shows no warning.
2. Trial shows 7 days. Move the trial start back 8 days: the hotkey opens the Licence section, Settings / Pause / Quit still work.
3. Stripe **test mode**: pay → email arrives with a key → pasting it unlocks → relaunch stays unlocked with the network off.
4. A wrong key, a Watchflows key, and a truncated key are each refused with a clear message.
5. Put a higher version in `releases.json`: the menu shows the update; the link downloads the zip.
6. Site: every page in light and dark, on a phone width; every link works; the buy link is the live one.
7. One real $10 purchase end to end, then refund it.
8. `make release` dry run passes on the release Mac; the notarized app opens on a second Mac.

---

## 14. Risks

| Risk | What we do |
|---|---|
| Keys get shared (no device limit) | Accepted at $10 |
| Customers stay on old versions (manual update) | The menu notice; revisit Sparkle if support load shows it |
| Intel build is untested | Ship it, but the site only says "macOS 15 or later" (C5). Say "Intel" once someone has run it on one. |
| The permission scares people | The site and first-launch screen say exactly what Jumpr reads and that nothing leaves the Mac |
| Stripe's fee on $10 (about 59¢) | Accepted |

---

## 15. Left to the builder

- File and type names; how the Licence section is laid out in Settings.
- Site layout and visuals within section 9's rules.
- The exact shape of the release script.
- Whether the trimmed function keeps Watchflows' file layout.
- How tasks are split and ordered, within section 6's order.
