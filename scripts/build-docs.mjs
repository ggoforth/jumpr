#!/usr/bin/env node
// build-docs.mjs: docs-src/**/*.md → site/docs/**/*.html (+ .md copies, llms.txt)
//
// No dependencies. One template renders every page, and the sidebar, previous
// and next, and "On this page" are worked out from the folders and each page's
// front matter. Adding a page is adding one file; no other page is edited.
//
// The Markdown accepted is a deliberate subset. The template only has a home
// for these shapes, and anything else stops the build rather than rendering
// wrong (docs-src/README.md is the writer's guide):
//
//   ## / ###            headings (the h1 is the front matter `title`)
//   paragraphs          separated by a blank line
//   - item / 1. item    flat lists; a numbered list renders as steps
//   | a | b |           pipe tables (separator row required)
//   > text              callout; `> ⚠️ text` is the heads-up variant
//   ![caption](file)    figure: the file beside the .md is copied through,
//                       a missing file renders a labelled placeholder
//   ```lang             fenced code
//   inline: `code` **bold** *em* [text](page.md) [[Key]]
//
// Front matter: `title` (required), `lede`, `order`.
//
// Layout of docs-src/: pages at the top level, and one level of folders. A
// folder is a sidebar group; its index.md names the group (`title`), places
// it (`order`) and is the group's own page, which lists the group's pages.
//
// Usage: node scripts/build-docs.mjs [--check]
//   --check  render to memory and fail if site/docs/ differs (the CI gate).

import { readFileSync, writeFileSync, mkdirSync, readdirSync, statSync, existsSync, rmSync } from 'node:fs';
import { join, dirname, basename, posix } from 'node:path';

const SRC = 'docs-src';
const OUT = 'site/docs';
const SITE = 'https://getjumpr.app/docs/';
const DOWNLOAD = 'https://github.com/ggoforth/jumpr/releases/latest/download/Jumpr.zip';
const CHECK = process.argv.includes('--check');
// Written by hand and kept beside the built pages. Everything else under
// site/docs/ is build output, so a file there that no page produced is stale.
const HAND_WRITTEN = new Set(['docs.css', 'docs.js']);

function fail(file, msg) {
  console.error(`build-docs: ${file}: ${msg}`);
  process.exit(1);
}

function walk(dir, acc = []) {
  if (!existsSync(dir)) return acc;
  for (const name of readdirSync(dir).sort()) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) walk(p, acc);
    else acc.push(p);
  }
  return acc;
}

// ───────────────────────── front matter ─────────────────────────

function parseFrontMatter(text, file) {
  if (!text.startsWith('---\n')) fail(file, 'missing front matter');
  const end = text.indexOf('\n---\n', 3);
  if (end === -1) fail(file, 'unterminated front matter');
  const fm = {};
  for (const raw of text.slice(4, end).split('\n')) {
    if (!raw.trim()) continue;
    const m = /^(title|lede|order):\s*(.+)$/.exec(raw);
    if (!m) fail(file, `bad front matter line (title, lede and order are the only keys): ${raw}`);
    fm[m[1]] = m[2].trim().replace(/^"(.*)"$/, '$1');
  }
  if (!fm.title) fail(file, 'front matter needs a title');
  if (fm.order !== undefined && !/^\d+$/.test(fm.order)) fail(file, `order must be a whole number: ${fm.order}`);
  return { fm, body: text.slice(end + 5) };
}

// ───────────────────────── markdown ─────────────────────────

const esc = s => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const slug = s => s.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
const rel = (from, to) => posix.relative(posix.dirname(from), to) || '.';

function inline(text, ctx) {
  // Code and keys are lifted out first so nothing inside them is read as Markdown.
  const held = [];
  const hold = html => { held.push(html); return `\u0000${held.length - 1}\u0000`; };
  let s = esc(text)
    .replace(/`([^`]+)`/g, (_, c) => hold(`<code>${c}</code>`))
    .replace(/\[\[([^\]]+)\]\]/g, (_, k) => hold(`<kbd>${k}</kbd>`));
  s = s.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
  s = s.replace(/(^|[\s(])\*([^*]+)\*/g, '$1<em>$2</em>');
  s = s.replace(/\[([^\]]+)\]\(([^)]+)\)/g, (_, t, href) => {
    if (/^https?:\/\//.test(href) || href.startsWith('#')) return `<a href="${href}">${t}</a>`;
    const [path, anchor] = href.split('#');
    if (!path.endsWith('.md')) fail(ctx.file, `link to another docs page by its .md path, or use a full https:// address: ${href}`);
    const target = posix.normalize(posix.join(posix.dirname(ctx.href), path)).replace(/\.md$/, '.html');
    if (!hrefs.has(target)) fail(ctx.file, `dead link: ${href}`);
    return `<a href="${rel(ctx.href, target)}${anchor ? `#${anchor}` : ''}">${t}</a>`;
  });
  return s.replace(/\u0000(\d+)\u0000/g, (_, i) => held[i]);
}

function figure(caption, src, ctx) {
  const local = join(dirname(ctx.file), src);
  const cap = inline(caption, ctx);
  if (existsSync(local)) {
    ctx.assets.push([local, join(dirname(ctx.out), src)]);
    return `<figure class="docs-figure"><div class="frame"><img src="${esc(src)}" alt="${esc(caption)}" loading="lazy"></div><figcaption>${cap}</figcaption></figure>`;
  }
  placeholders.push(`${ctx.file}: ${src}`);
  return `<figure class="docs-figure"><div class="frame is-placeholder"><span class="docs-chip">Screenshot pending</span><span class="file">${esc(src)}</span></div><figcaption>${cap}</figcaption></figure>`;
}

function markdown(body, ctx) {
  const lines = body.split('\n');
  const out = [];
  const toc = [];
  const para = [];
  const flush = () => { if (para.length) { out.push(`<p>${inline(para.join(' '), ctx)}</p>`); para.length = 0; } };
  let i = 0;

  while (i < lines.length) {
    const line = lines[i];
    if (!line.trim()) { flush(); i++; continue; }

    let m;
    if ((m = /^(#{2,3}) (.+)$/.exec(line))) {
      flush();
      const level = m[1].length, text = m[2].trim(), id = slug(text);
      if (level === 2) toc.push({ id, text });
      out.push(`<h${level} id="${id}">${inline(text, ctx)}</h${level}>`);
      i++; continue;
    }
    if (/^#/.test(line)) fail(ctx.file, `only ## and ### headings are allowed: ${line}`);
    if (/^</.test(line)) fail(ctx.file, `raw HTML is not allowed: ${line}`);
    if (/^\s+(-|\d+\.) /.test(line)) fail(ctx.file, `lists are flat, one line per item: ${line}`);

    if (line.startsWith('```')) {
      flush();
      const start = i, lang = line.slice(3).trim(), code = [];
      i++;
      while (i < lines.length && !lines[i].startsWith('```')) code.push(lines[i++]);
      if (i >= lines.length) fail(ctx.file, `code block opened on line ${start + 1} is never closed`);
      i++;
      out.push(`<pre${lang ? ` data-lang="${esc(lang)}"` : ''}><code>${esc(code.join('\n'))}</code></pre>`);
      continue;
    }

    if ((m = /^!\[([^\]]*)\]\(([^)]+)\)\s*$/.exec(line))) {
      flush();
      out.push(figure(m[1], m[2], ctx));
      i++; continue;
    }

    if (line.startsWith('|')) {
      flush();
      const rows = [];
      while (i < lines.length && lines[i].startsWith('|')) rows.push(lines[i++]);
      const cells = r => r.trim().replace(/^\||\|$/g, '').split(/(?<!\\)\|/).map(c => inline(c.trim().replace(/\\\|/g, '|'), ctx));
      if (rows.length < 3 || !/^\|[\s|:-]+\|\s*$/.test(rows[1])) fail(ctx.file, 'a table needs a header, a separator row, and at least one row');
      const head = cells(rows[0]);
      const bodyRows = rows.slice(2).map(r => {
        const c = cells(r);
        if (c.length !== head.length) fail(ctx.file, `table row has ${c.length} cells, header has ${head.length}: ${r}`);
        return `<tr>${c.map(v => `<td>${v}</td>`).join('')}</tr>`;
      });
      // The wrapper scrolls sideways on a phone, so a wide table never widens the page.
      out.push(`<div class="docs-table"><table><thead><tr>${head.map(h => `<th>${h}</th>`).join('')}</tr></thead><tbody>${bodyRows.join('')}</tbody></table></div>`);
      continue;
    }

    if (line.startsWith('> ')) {
      flush();
      const q = [];
      while (i < lines.length && lines[i].startsWith('> ')) q.push(lines[i++].slice(2));
      let text = q.join(' ');
      const warn = text.startsWith('⚠️');
      if (warn) text = text.replace(/^⚠️\s*/, '');
      out.push(`<div class="docs-note${warn ? ' warn' : ''}"><span class="docs-chip">${warn ? 'Heads up' : 'Tip'}</span><p>${inline(text, ctx)}</p></div>`);
      continue;
    }

    if ((m = /^(-|\d+\.) /.exec(line))) {
      flush();
      const ordered = m[1] !== '-';
      const item = ordered ? /^\d+\. / : /^- /;
      const items = [];
      while (i < lines.length && item.test(lines[i])) items.push(lines[i++].replace(item, ''));
      out.push(`<${ordered ? 'ol class="docs-steps"' : 'ul'}>${items.map(t => `<li>${inline(t, ctx)}</li>`).join('')}</${ordered ? 'ol' : 'ul'}>`);
      continue;
    }

    para.push(line.trim());
    i++;
  }
  flush();
  return { html: out.join('\n'), toc };
}

// ───────────────────────── pages and navigation ─────────────────────────

function loadPages() {
  const pages = [];
  for (const file of walk(SRC)) {
    const path = posix.relative(SRC, file.split('\\').join('/'));
    if (!path.endsWith('.md') || path === 'README.md') continue;
    const parts = path.split('/');
    if (parts.length > 2) fail(file, 'pages sit at the top level or one folder down, no deeper');
    const { fm, body } = parseFrontMatter(readFileSync(file, 'utf8'), file);
    const href = path.replace(/\.md$/, '.html');
    pages.push({ file, fm, body, href, out: join(OUT, href), isIndex: basename(path) === 'index.md', folder: parts.length === 2 ? parts[0] : null });
  }
  if (!pages.some(p => p.href === 'index.html')) fail(SRC, 'needs an index.md, the Overview page');
  return pages;
}

// Index first, then front matter `order`, then title.
const byOrder = (a, b) => (a.isIndex ? -1 : b.isIndex ? 1 : (Number(a.fm.order ?? 999) - Number(b.fm.order ?? 999)) || a.fm.title.localeCompare(b.fm.title));

function nav(pages) {
  const root = pages.filter(p => !p.folder).sort(byOrder);
  const groups = [...new Set(pages.filter(p => p.folder).map(p => p.folder))].map(folder => {
    const items = pages.filter(p => p.folder === folder).sort(byOrder);
    if (!items[0].isIndex) fail(join(SRC, folder), 'a folder needs an index.md: its title names the group in the sidebar');
    return { index: items[0], items: items.slice(1) };
  }).sort((a, b) => (Number(a.index.fm.order ?? 999) - Number(b.index.fm.order ?? 999)) || a.index.fm.title.localeCompare(b.index.fm.title));
  // The reading order previous and next walk: the sidebar, top to bottom.
  const flat = [...root, ...groups.flatMap(g => [g.index, ...g.items])];
  return { root, groups, flat };
}

const groupOf = (page, navData) => navData.groups.find(g => g.index.folder === page.folder);
const current = (p, page) => (p === page ? ' aria-current="page"' : '');

function sidebar(page, { root, groups }) {
  const link = p => `<a href="${rel(page.href, p.href)}"${current(p, page)}>${p.href === 'index.html' ? 'Overview' : esc(p.fm.title)}</a>`;
  const blocks = groups.map(g => `<p class="docs-group"><a href="${rel(page.href, g.index.href)}"${current(g.index, page)}>${esc(g.index.fm.title)}</a></p>${g.items.map(link).join('')}`).join('');
  return `<nav class="docs-side" id="docs-side" aria-label="Docs">${root.map(link).join('')}${blocks}</nav>`;
}

// A group's own page ends with a card for each page in the group.
function cards(page, navData) {
  if (!page.folder || !page.isIndex) return '';
  return `<div class="docs-cards">${groupOf(page, navData).items.map(p => `<a href="${rel(page.href, p.href)}"><b>${esc(p.fm.title)}</b>${p.fm.lede ? `<span>${esc(p.fm.lede)}</span>` : ''}</a>`).join('')}</div>`;
}

function prevNext(page, { flat }) {
  const i = flat.indexOf(page);
  const a = (p, cls, label) => p ? `<a href="${rel(page.href, p.href)}" class="${cls}"><small>${label}</small>${p.href === 'index.html' ? 'Overview' : esc(p.fm.title)}</a>` : '<span></span>';
  return `<footer class="docs-foot">${a(flat[i - 1], 'prev', '← Previous')}${a(flat[i + 1], 'next', 'Next →')}</footer>`;
}

function render(page, navData) {
  const ctx = { file: page.file, out: page.out, href: page.href, assets: [] };
  const md = markdown(page.body, ctx);
  const up = '../'.repeat(page.href.split('/').length - 1);   // to site/docs/
  const site = `${up}../`;                                     // to site/
  const title = page.fm.title;
  const crumb = page.folder && !page.isIndex ? groupOf(page, navData).index.fm.title : 'Jumpr docs';
  const canonical = SITE + page.href.replace(/(^|\/)index\.html$/, '$1');
  const toc = md.toc.length > 1 ? `<aside class="docs-toc" aria-label="On this page"><h2>On this page</h2>${md.toc.map(t => `<a href="#${t.id}">${inline(t.text, ctx)}</a>`).join('')}</aside>` : '';

  const html = `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${page.href === 'index.html' ? '' : `${esc(title)}: `}Jumpr docs</title>
  <meta name="description" content="${esc(page.fm.lede || `${title}: Jumpr documentation`)}">
  <meta name="color-scheme" content="light dark">
  <link rel="canonical" href="${canonical}">
  <link rel="icon" href="${site}favicon.svg" type="image/svg+xml">
  <link rel="stylesheet" href="${site}site.css">
  <link rel="stylesheet" href="${up}docs.css">
  <script src="${site}analytics.js" defer></script>
  <script src="${up}docs.js" defer></script>
</head>
<body>
  <a class="skip" href="#main">Skip to content</a>

  <header class="site-header docs-header">
    <a class="brand" href="${site}index.html" aria-label="Jumpr home"><span class="brand-mark" aria-hidden="true">J</span>Jumpr</a>
    <nav class="header-nav" aria-label="Site">
      <a class="header-link" href="${up}index.html" aria-current="page">Docs</a>
      <a class="header-link wide" href="${site}changelog.html">Changelog</a>
      <a class="header-link wide" href="https://github.com/ggoforth/jumpr">GitHub</a>
      <a class="header-link" href="${DOWNLOAD}">Download</a>
    </nav>
  </header>

  <div class="docs" id="docs">
    <button class="docs-menu" id="docs-menu" type="button" aria-controls="docs-side" aria-expanded="false"><b>Browse docs</b><span>${esc(page.href === 'index.html' ? 'Overview' : title)}</span></button>
    ${sidebar(page, navData)}
    <main class="docs-content" id="main">
      <header class="docs-hero">
        <div>
          <p class="docs-crumb"><i aria-hidden="true"></i>${esc(crumb)}</p>
          <h1>${esc(title)}</h1>
          ${page.fm.lede ? `<p class="docs-lede">${esc(page.fm.lede)}</p>` : ''}
        </div>
        <button class="docs-copy" id="docs-copy" type="button" data-md="${basename(page.href, '.html')}.md" title="Copy this page as Markdown, to paste into any AI">Copy for AI</button>
      </header>
      <div class="docs-main">
        <article class="docs-article">
${md.html}
${cards(page, navData)}
${prevNext(page, navData)}
        </article>
        ${toc}
      </div>
    </main>
  </div>
</body>
</html>
`;
  return { html, assets: ctx.assets };
}

// ───────────────────────── write / check ─────────────────────────

const placeholders = [];
const pages = loadPages();
const hrefs = new Set(pages.map(p => p.href));
const navData = nav(pages);
const outputs = new Map(); // path → content (string) | [srcPath] (copy)

for (const page of pages) {
  const { html, assets } = render(page, navData);
  outputs.set(page.out, html);
  outputs.set(page.out.replace(/\.html$/, '.md'), readFileSync(page.file, 'utf8'));   // what "Copy for AI" fetches
  for (const [from, to] of assets) outputs.set(to, [from]);
}
outputs.set(join(OUT, 'llms.txt'), `# Jumpr docs\n\n> Jumpr is a free, open-source menu bar app for macOS. Press a hotkey and everything clickable on every display gets a two-letter label; type it, and it is clicked. Each page below is also available as Markdown at the same path with a .md extension.\n\n${navData.flat.map(p => `- [${p.fm.title}](${SITE}${p.href.replace(/\.html$/, '.md')})${p.fm.lede ? `: ${p.fm.lede}` : ''}`).join('\n')}\n`);

let stale = 0;
for (const [path, content] of outputs) {
  const next = Array.isArray(content) ? readFileSync(content[0]) : Buffer.from(content);
  if (existsSync(path) && readFileSync(path).equals(next)) continue;
  if (CHECK) { console.error(`stale: ${path}`); stale++; continue; }
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, next);
}
// A page that was renamed or deleted leaves its old output behind; remove it.
for (const path of walk(OUT)) {
  if (outputs.has(path) || HAND_WRITTEN.has(posix.relative(OUT, path.split('\\').join('/')))) continue;
  if (CHECK) { console.error(`stale: ${path} (no page builds it)`); stale++; continue; }
  rmSync(path);
}
if (CHECK && stale) { console.error(`build-docs: ${stale} file(s) out of date. Run \`make docs\` and commit.`); process.exit(1); }
if (placeholders.length) console.error(`build-docs: ${placeholders.length} figure(s) still placeholders\n  ${placeholders.join('\n  ')}`);
console.log(`build-docs: ${pages.length} page(s) ${CHECK ? 'checked' : 'rendered'} → ${OUT}/`);
