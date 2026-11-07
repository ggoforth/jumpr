---
name: release-notes
description: Use before every Jumpr release, or when asked to write release notes or prepare a tag. Drafts the notes from what shipped, gets them approved, and lands them in site/releases.json.
---

# Release notes

Every release gets notes. `site/releases.json` is their one home: the changelog page, the update window and the GitHub release all read the same entry. `scripts/release.sh` refuses a notarized build without one.

The notes land **before** the tag, by pull request, so the tagged commit carries them.

## Steps

1. **See what shipped.** `git fetch --tags`, take the newest `v*` tag, then read `git log <tag>..origin/main` and the bodies of the pull requests merged in that range. If nothing shipped, stop and say so.

2. **Pick the version.** The next patch, unless the user says otherwise.

3. **Draft the entry,** in the voice of the entries already in the file:
   - `summary`: one or two sentences. Lead with the change a user would notice most.
   - `bullets`: what changed, for someone using Jumpr. Name the app or feature first, in `<strong>`, when that helps. Leave out a bullet that would only repeat the summary.
   - `note`: optional. What did not get fixed, when a user would expect it to have been.
   - Plain words, no marketing. Every claim traces to a commit or pull request.
   - Nothing internal: no refactors, tests, tickets or CI, unless that is the whole release. Then say so plainly ("A housekeeping release").
   - `date` is today, `YYYY-MM-DD`.

4. **Show the draft and wait for approval.**

5. **Land it.** On a branch, add the entry at the top of `releases`. Run `swift scripts/release-notes.swift check`. Open a pull request. Merge when the user says so.

6. **Hand back the release steps.** Never tag, publish, upload or deploy: those are the maintainer's.

   ```
   make release VERSION=<version> JUMPR_NOTARY_PROFILE=<profile>
   ```

   It builds from `main`, prints what to upload and in what order, and writes the GitHub release's text to `build/release/notes.md`.
