# Writing a docs page

One `.md` here becomes one page at getjumpr.app/docs/. `make docs` runs
`scripts/build-docs.mjs`, which renders every page through one template into
`site/docs/`. Commit the source and the built pages together; CI fails when
they disagree. Never edit `site/docs/*.html` by hand.

## Add a page

1. Put a `.md` at the top level, or in a group's folder.
2. Give it front matter.
3. Run `make docs` and commit.

The page appears in every sidebar, and in previous and next. No other page is
edited.

```markdown
---
title: Scrolling
lede: One sentence under the title. It is also the page's description for search engines.
order: 4
---

## First section
```

- `title` is required. It is the page's heading, its sidebar link and its browser tab.
- `lede` is plain text, one sentence.
- `order` places the page among its neighbours. Pages without one come last, by title.

## Add a group

A folder is a sidebar group. Its `index.md` names the group (`title`), places
it (`order`) and is the group's own page: write one short paragraph, and the
build adds a card for each page in the folder. Folders go one level deep.

## Markdown accepted

The build stops on anything else.

| Write | Get |
|---|---|
| `## Heading`, `### Heading` | Section headings. Each `##` is also an "On this page" link |
| A blank line between paragraphs | Paragraphs |
| `- item` | A plain list. One line per item, no nesting |
| `1. item` | Numbered steps. Use it only for a real sequence |
| A pipe table with a `\|---\|---\|` row | A table |
| `> **Lead.** Text` | A callout marked Tip |
| `> ⚠️ **Lead.** Text` | A callout marked Heads up |
| Three backticks, optionally a language | A code block |
| `![Caption.](name.webp)` alone on a line | A figure. The image sits beside the `.md`; until it exists the page shows a placeholder and the build says so |
| `` `code` ``, `**bold**`, `*em*` | Inline styles |
| `[[⌘]] [[⇧]] [[Space]]` | Key caps, one key per pair of brackets |
| `[text](../help/known-limits.md)` | A link to another page, by its `.md` path. A dead link stops the build |
| `[text](https://…)` | A link anywhere else |

Raw HTML, `#` and `####` headings, and nested lists stop the build.

## Figures

Every page has one to three. Put the image beside the `.md` and name it after the page (`scroll-areas.webp`).

- Captures are WebP at one screen pixel per image pixel. The page shows them at their own size and never enlarges them, so keep a capture under 760 px wide.
- Stage a neutral subject: Calculator, a TextEdit document with made-up text, Jumpr's own panel. Nothing from a real desktop, and no other app's name.
- Capture the window by its id (`screencapture -o -l <id>`) so nothing behind it is in the picture, and leave the ground transparent: the page supplies the backdrop and the shadow in light and dark.
- A short run of steps can be an animated WebP: a few frames, each held about a second.
- The caption says what the reader is looking at. It is also the image's alt text.

## Voice

- Every fact comes from the app. If the README, `docs/design.md` or the code does not say it, it does not go in.
- Say it in the fewest words that keep every fact.
- Second person, present tense, active: "Press", "Type", "Hold".
- Lead with what it does for the reader, then how.
- Name things as the app shows them: **Shortcuts**, not "the shortcuts screen".
- A gotcha is a callout, not a paragraph. Two or three a page at most.
- Each fact has one home. Other pages link to it.
- A change to what Jumpr reads, stores or sends also updates `site/privacy.html` and the README (AGENTS.md).
