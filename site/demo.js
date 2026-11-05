/* Jumpr — the in-browser demo.
 *
 * A pretend Mac with two displays. Space (or the "Show labels" button) puts a
 * yellow two-letter label on every clickable thing on both displays. Typing
 * the first letter hides the labels that do not start with it; the second
 * letter clicks. Esc or Space cancels. Tapping a label clicks it.
 *
 * Keys are only handled while the demo itself has focus, and Tab is never
 * touched, so the page keyboard is never trapped. Left alone, the demo plays
 * itself slowly; any interaction stops that at once. With reduced motion
 * there is no autoplay and no animation.
 *
 * No dependencies. Plain DOM.
 */
(function () {
  'use strict';

  var stage = document.getElementById('stage');
  if (!stage) return;
  var captionEl = document.getElementById('caption');
  var promptEl = document.getElementById('prompt');
  var toggleBtn = document.getElementById('show-labels');

  // Same alphabet as the app (Sources/JumprCore/Labels.swift): home row first.
  var ALPHABET = 'ASDFGHJKLQWERTYUIOPZXCVBNM';

  var reduceMQ = window.matchMedia('(prefers-reduced-motion: reduce)');
  var coarseMQ = window.matchMedia('(pointer: coarse)');
  // Phones (same breakpoint as site.css) show one display; the second is
  // display:none, so it gets no labels and autoplay skips its steps.
  var phoneMQ = window.matchMedia('(max-width: 760px)');
  function reduced() { return reduceMQ.matches; }
  function touch() { return coarseMQ.matches; }        // tap wording, no keyboard hints
  function phone() { return phoneMQ.matches; }

  function $(sel, root) { return (root || stage).querySelector(sel); }
  function $$(sel, root) { return Array.prototype.slice.call((root || stage).querySelectorAll(sel)); }

  /* ------------------------------------------------------------------ */
  /* The mock: chat app, browser, settings, Dock, menus                  */
  /* ------------------------------------------------------------------ */

  var chats = [
    { id: 'c1', name: 'Trip plans', msgs: [['in', 'Train leaves at 8:10.'], ['out', 'I will bring snacks.'], ['in', 'Window seat is yours.']] },
    { id: 'c2', name: 'Groceries', msgs: [['in', 'Lemons, rice, coffee.'], ['out', 'Got it.']] },
    { id: 'c3', name: 'Design review', msgs: [['in', 'Can the type be bigger?'], ['out', 'Already on it.']] },
    { id: 'c4', name: 'Book club', msgs: [['in', 'Chapter six for Thursday.']] }
  ];
  var chatSel = 'c1';
  var newChats = 0;
  var replies = ['Sounds good.', 'On my way.', 'Done.', 'Perfect, thanks.'];
  var replyAt = 0;

  function currentChat() {
    for (var i = 0; i < chats.length; i++) if (chats[i].id === chatSel) return chats[i];
    return chats[0];
  }

  function renderChat() {
    $('#chat-list').innerHTML = chats.map(function (c) {
      return '<div class="chat-item' + (c.id === chatSel ? ' is-sel' : '') + '" data-act="chat" data-id="' + c.id +
        '" data-name="' + c.name + ' chat">' + c.name + '</div>';
    }).join('');
    var c = currentChat();
    $('#chat-title').textContent = c.name;
    $('#chat-msgs').innerHTML = c.msgs.length
      ? c.msgs.map(function (m) { return '<p class="bubble ' + m[0] + '">' + m[1] + '</p>'; }).join('')
      : '<p class="chat-empty">A new chat. Say hello.</p>';
  }

  function newChat() {
    var top = chats[0];
    if (!(top.fresh && top.msgs.length === 0)) {
      newChats += 1;
      chats.unshift({ id: 'n' + newChats, name: 'New chat', fresh: true, msgs: [] });
      if (chats.length > 5) chats.pop();
    }
    chatSel = chats[0].id;
    renderChat();
  }

  function send() {
    var c = currentChat();
    c.msgs.push(['out', replies[replyAt++ % replies.length]]);
    if (c.msgs.length > 4) c.msgs.shift();
    renderChat();
  }

  var sites = [
    { name: 'Trail Notes', host: 'trailnotes.example', home: 'Weekend routes', nav: ['Routes', 'Maps', 'Gear'], more: ['Ridge loop', 'Lake trail', 'Pine hill'] },
    { name: 'Sky Daily', host: 'skydaily.example', home: 'Clear skies, light wind', nav: ['Today', 'Week', 'Radar'], more: ['Hourly', 'Sunrise', 'Wind'] },
    { name: 'Pantry', host: 'pantry.example', home: 'Cook something simple', nav: ['Soups', 'Breads', 'Salads'], more: ['Lentil soup', 'Rye loaf', 'Green salad'] }
  ];
  var tabs = sites.map(function (s) { return { site: s, stack: [s.home] }; });
  var tabSel = 0;

  function slug(s) { return s.toLowerCase().replace(/[^a-z]+/g, '-'); }

  function renderBrowser() {
    $('#tabs').innerHTML = tabs.map(function (t, i) {
      return '<div class="tab' + (i === tabSel ? ' is-active' : '') + '" data-act="tab" data-i="' + i +
        '" data-name="' + t.site.name + ' tab">' + t.site.name + '</div>';
    }).join('');
    var t = tabs[tabSel], s = t.site, page = t.stack[t.stack.length - 1];
    $('#addr').textContent = s.host + (page === s.home ? '' : '/' + slug(page));
    var link = function (n, kind) {
      return '<span class="link" data-act="link" data-kind="' + kind + '" data-to="' + n + '" data-name="' + n + ' link">' + n + '</span>';
    };
    var more = s.more.filter(function (n) { return n !== page; }).slice(0, 2);
    $('#page').innerHTML =
      '<div class="site-head"><b>' + s.name + '</b><span class="site-nav">' +
        s.nav.map(function (n) { return link(n, 'nav'); }).join('') + '</span></div>' +
      '<h4 class="page-title">' + page + '</h4>' +
      '<div class="skel" style="--w:94%"></div><div class="skel" style="--w:88%"></div><div class="skel" style="--w:62%"></div>' +
      '<p class="read-more">Read next: ' + more.map(function (n) { return link(n, 'inline'); }).join(' · ') + '</p>';
  }

  function go(to) {
    var t = tabs[tabSel];
    if (t.stack[t.stack.length - 1] !== to) t.stack.push(to);
    if (t.stack.length > 8) t.stack.splice(1, 1);
    renderBrowser();
  }

  function back() {
    var t = tabs[tabSel];
    if (t.stack.length > 1) t.stack.pop();
    renderBrowser();
  }

  function bounce(el) {
    el.classList.add('is-running');
    if (reduced()) return;
    el.classList.remove('is-bouncing');
    void el.offsetWidth; // restart the animation
    el.classList.add('is-bouncing');
  }

  /* Menus ------------------------------------------------------------- */

  var openMenu = null; // { title, menu }

  function showMenu(title) {
    closeMenu();
    var screen = title.closest('.screen');
    var menu = document.getElementById('menu-' + title.getAttribute('data-menu'));
    if (!menu) return;
    menu.hidden = false;
    var s = screen.getBoundingClientRect(), r = title.getBoundingClientRect();
    var left = r.left - s.left;
    if (left + menu.offsetWidth > s.width) left = r.right - s.left - menu.offsetWidth;
    menu.style.left = (Math.max(0, left) / s.width * 100) + '%';
    title.classList.add('is-open');
    openMenu = { title: title, menu: menu };
  }

  function closeMenu() {
    if (!openMenu) return;
    openMenu.menu.hidden = true;
    openMenu.title.classList.remove('is-open');
    openMenu = null;
  }

  /* What a click does ------------------------------------------------- */

  function nameOf(el) {
    return el.getAttribute('data-name') || el.textContent.trim();
  }

  // Performs the click on a mock element. `viaLabel` is true when it was
  // reached through a label (so a menu it opens gets labels of its own).
  function activate(el, viaLabel, byAuto) {
    var act = el.getAttribute('data-act');
    var name = nameOf(el);

    if (act === 'menu') {
      showMenu(el);
      if (viaLabel) {
        say('Clicked: ' + name + '. Its items get their own labels.');
        later(function () { if (openMenu) showLabels(byAuto); }, reduced() ? 0 : 160);
      } else {
        say('Opened: ' + name + '.');
      }
      return;
    }

    if (openMenu && act !== 'mi') closeMenu();

    switch (act) {
      case 'mi':
        var does = el.getAttribute('data-do');
        closeMenu();
        if (does === 'newchat') newChat();
        if (does === 'sidebar') {
          var hidden = $('#chat').classList.toggle('no-sidebar');
          el.textContent = hidden ? 'Show Sidebar' : 'Hide Sidebar';
        }
        if (does === 'net') {
          $$('#menu-wifi .mi[data-do="net"]').forEach(function (n) { n.classList.toggle('is-checked', n === el); });
        }
        if (does === 'labels') {
          say('Clicked: Show Labels.');
          later(function () { showLabels(byAuto); }, reduced() ? 0 : 160);
          return;
        }
        break;
      case 'newchat': newChat(); break;
      case 'chat': chatSel = el.getAttribute('data-id'); renderChat(); break;
      case 'input':
        el.classList.add('is-focus');
        break;
      case 'send': send(); break;
      case 'dock': bounce(el); break;
      case 'desk':
        $$('.desk-icon').forEach(function (d) { d.classList.toggle('is-sel', d === el); });
        break;
      case 'tab': tabSel = +el.getAttribute('data-i'); renderBrowser(); break;
      case 'back': back(); break;
      case 'link': go(el.getAttribute('data-to')); break;
      case 'toggle':
        var on = el.classList.toggle('is-on');
        say('Clicked: ' + name + ' — now ' + (on ? 'on' : 'off') + '.');
        return;
    }
    if (act !== 'input') $$('.compose-input').forEach(function (i) { i.classList.remove('is-focus'); });
    say('Clicked: ' + name);
  }

  /* ------------------------------------------------------------------ */
  /* Labels                                                              */
  /* ------------------------------------------------------------------ */

  var session = null; // { entries:[{el,label,node}], typed:'', auto:bool, locked:bool }
  var timers = [];

  function later(fn, ms) {
    var id = setTimeout(function () {
      timers = timers.filter(function (t) { return t !== id; });
      fn();
    }, ms);
    timers.push(id);
  }

  function clearLater() {
    timers.forEach(clearTimeout);
    timers = [];
    $$('.is-pressed').forEach(function (el) { el.classList.remove('is-pressed'); });
  }

  function visible(el) {
    return el.getClientRects().length > 0 && !el.closest('[hidden]');
  }

  // Spread the first letters over the home row so typing one letter leaves a
  // handful of labels, on both displays, instead of all of them.
  function labelFor(i, n) {
    var k = Math.min(8, n);
    return ALPHABET[i % k] + ALPHABET[Math.floor(i / k)];
  }

  function showLabels(byAuto) {
    removeLabels();
    var root = openMenu ? openMenu.menu : stage;
    var els = $$('[data-act]', root).filter(visible);
    if (!els.length) return;
    session = { entries: [], typed: '', auto: !!byAuto, locked: false };
    var n = els.length;
    els.forEach(function (el, i) {
      var entry = { el: el, label: labelFor(i, n), node: null };
      entry.node = place(entry, reduced() ? 0 : ((i * 37) % n) * 3);
      session.entries.push(entry);
    });
    var screens = {};
    els.forEach(function (el) { screens[el.closest('.screen').getAttribute('data-screen')] = 1; });
    if (touch() && !session.auto) say(openMenu ? 'Labels on the menu’s items. Tap one.' : 'Labels are up. Tap one to click it.');
    else say(openMenu ? 'Labels on the menu’s items.'
      : Object.keys(screens).length > 1 ? 'Labels on both displays.' : 'Labels are up.');
    updatePrompt();
  }

  // Positions a label the way the app does (Labels.frame, build/v1), so it never
  // hides what it points at. A target under four label widths gets its label
  // hanging off its bottom-right corner, flipping left or above at the display
  // edge. A wider target (a row) keeps its label inside, at the right end.
  // Finally the label is kept inside the display.
  function place(entry, delay) {
    var screen = entry.el.closest('.screen');
    var layer = screen.querySelector('.labels');
    var s = screen.getBoundingClientRect(), r = entry.el.getBoundingClientRect();
    var node = document.createElement('span');
    node.className = 'lbl';
    node.textContent = entry.label;
    if (delay) node.style.animationDelay = delay + 'ms';
    layer.appendChild(node);
    var w = node.offsetWidth, h = node.offsetHeight;
    var fs = parseFloat(getComputedStyle(node).fontSize);
    var minX = r.left - s.left, maxX = r.right - s.left, minY = r.top - s.top, maxY = r.bottom - s.top;
    var x, y;
    if (r.width >= 4 * w) {
      x = maxX - w - 2;
      y = r.height >= 2 * h ? maxY - h - 2 : minY + r.height / 2 - h / 2;
    } else {
      var ox = Math.min(Math.round(fs * 0.75), r.width / 2);
      var oy = Math.min(fs * 0.4, r.height / 4);
      x = maxX - ox;
      y = maxY - oy;
      if (x + w > s.width) x = minX - w + ox;
      if (y + h > s.height) y = minY - h + oy;
    }
    x = Math.max(0, Math.min(x, s.width - w));
    y = Math.max(0, Math.min(y, s.height - h));
    node.style.left = (x / s.width * 100) + '%';
    node.style.top = (y / s.height * 100) + '%';
    return node;
  }

  function removeLabels() {
    $$('.labels').forEach(function (l) { l.innerHTML = ''; });
  }

  function typeLetter(ch) {
    if (!session || session.locked) return;
    var next = session.typed + ch;
    var hits = session.entries.filter(function (e) { return e.label.indexOf(next) === 0; });
    if (!hits.length) { say('No label starts with ' + next + '.'); return; }
    if (next.length === 2) { choose(hits[0]); return; }
    session.typed = next;
    session.entries.forEach(function (e) { e.node.classList.toggle('is-out', e.label.indexOf(next) !== 0); });
    var left = hits.length + ' label' + (hits.length === 1 ? '' : 's') + ' left.';
    say(touch() ? next + ' — ' + left : 'Typed ' + next + ' — ' + left);
    updatePrompt();
  }

  function backspace() {
    if (!session || session.locked || !session.typed) return;
    session.typed = '';
    session.entries.forEach(function (e) { e.node.classList.remove('is-out'); });
    say('Back to every label.');
    updatePrompt();
  }

  function choose(entry) {
    var byAuto = session.auto;
    session.locked = true;
    session.typed = entry.label;
    session.entries.forEach(function (e) { if (e !== entry) e.node.classList.add('is-out'); });
    entry.node.classList.add('is-hit');
    entry.el.classList.add('is-pressed');
    later(function () {
      entry.el.classList.remove('is-pressed');
      removeLabels();
      session = null;
      activate(entry.el, true, byAuto);
      updatePrompt();
    }, reduced() ? 0 : 190);
  }

  function cancel(message) {
    if (!session) return;
    clearLater();
    removeLabels();
    session = null;
    closeMenu();
    if (message) say(message);
    updatePrompt();
  }

  /* ------------------------------------------------------------------ */
  /* Caption and prompt                                                  */
  /* ------------------------------------------------------------------ */

  function say(text) { captionEl.textContent = text; }

  // Tapping: each label answers taps in a box at least 34 px square around
  // it. Where boxes overlap, the label whose centre is nearest wins.
  var TAP = 34;
  function labelAt(x, y) {
    if (!session || session.locked) return null;
    var best = null, bestD = Infinity;
    session.entries.forEach(function (e) {
      if (e.node.classList.contains('is-out')) return;
      var r = e.node.getBoundingClientRect();
      var cx = r.left + r.width / 2, cy = r.top + r.height / 2;
      var hw = Math.max(r.width + 12, TAP) / 2, hh = Math.max(r.height + 12, TAP) / 2;
      if (Math.abs(x - cx) > hw || Math.abs(y - cy) > hh) return;
      var d = Math.hypot(x - cx, y - cy);
      if (d < bestD) { bestD = d; best = e; }
    });
    return best;
  }

  function idleCaption() {
    return touch() ? 'Tap Show labels.' : phone() ? 'A pretend Mac.' : 'A pretend Mac with two displays.';
  }

  var active = false; // the demo has focus

  function updatePrompt() {
    var touch = coarseMQ.matches;
    var html;
    if (auto) {
      html = touch ? 'Playing on its own. Tap <b>Show labels</b> to take over.'
        : active ? 'Playing on its own. Press <kbd>Space</kbd> to take over.'
        : 'Playing on its own. Click it, then press <kbd>Space</kbd>.';
    } else if (session && session.typed && !session.locked) {
      html = 'Typed <kbd class="kbd-label">' + session.typed + '</kbd> Now the second letter. <kbd>⌫</kbd> goes back.';
    } else if (session) {
      html = touch ? 'Tap a label to click it.' : 'Type a label to click it. <kbd>Esc</kbd> cancels.';
    } else if (touch) {
      html = 'Tap <b>Show labels</b>, then tap a label.';
    } else if (active) {
      html = 'Press <kbd>Space</kbd> to show labels.';
    } else {
      html = 'Click the desktop, then press <kbd>Space</kbd>.';
    }
    promptEl.innerHTML = html;
    var up = !!session && !auto;
    toggleBtn.textContent = up ? 'Hide labels' : 'Show labels';
  }

  /* ------------------------------------------------------------------ */
  /* Autoplay                                                            */
  /* ------------------------------------------------------------------ */

  // Each step: a target to click, and optionally a menu item to click after.
  var SCRIPT = [
    { target: '.newchat' },
    { target: '.tab:not(.is-active)' },
    { target: '.dock-icon[data-name^="Music"]' },
    { target: '.link[data-kind="inline"]' },
    { target: '.mb-icon[data-menu="wifi"]', then: '#menu-wifi .mi[data-do="net"]:not(.is-checked)' },
    { target: '.toggle' },
    { target: '.chat-item:not(.is-sel)' }
  ];

  var auto = null;       // { cancelled, ids } while autoplay runs
  var idleTimer = null;
  var inView = true;

  function wait(ms) {
    var tok = auto;
    return new Promise(function (resolve, reject) {
      var id = setTimeout(function () { (tok && !tok.cancelled) ? resolve() : reject(); }, ms);
      if (tok) tok.ids.push(id);
    });
  }

  function entryFor(sel) {
    if (!session) return null;
    var el = $(sel);
    for (var i = 0; i < session.entries.length; i++) if (session.entries[i].el === el) return session.entries[i];
    return null;
  }

  function typeOut(entry) {
    typeLetter(entry.label[0]);
    return wait(1300).then(function () { typeLetter(entry.label[1]); });
  }

  function step(s) {
    var el = $(s.target);
    if (!el || !visible(el)) return Promise.resolve();
    showLabels(true);
    updatePrompt();
    return wait(1700).then(function () {
      var e = entryFor(s.target);
      if (!e) { cancel(); return; }
      return typeOut(e).then(function () {
        if (!s.then) return wait(2800);
        return wait(1700).then(function () {
          var m = entryFor(s.then);
          if (!m) { cancel(); return wait(1200); }
          return typeOut(m).then(function () { return wait(2800); });
        });
      });
    });
  }

  function startAuto() {
    if (auto || reduced()) return;
    auto = { cancelled: false, ids: [] };
    stage.classList.add('is-auto');
    updatePrompt();
    var i = 0;
    (function loop() {
      if (!auto) return;
      step(SCRIPT[i++ % SCRIPT.length]).then(function () { loop(); }, function () {});
    })();
  }

  // keep: hand the autoplay's labels to the visitor instead of removing them.
  function stopAuto(keep) {
    if (!auto) return;
    auto.cancelled = true;
    auto.ids.forEach(clearTimeout);
    auto = null;
    stage.classList.remove('is-auto');
    if (session && keep && !session.locked) session.auto = false;
    else cancel();
    updatePrompt();
  }

  function scheduleAuto(ms) {
    clearTimeout(idleTimer);
    if (reduced()) return;
    idleTimer = setTimeout(function () {
      if (session || !inView || document.hidden) scheduleAuto(4000);
      else startAuto();
    }, ms);
  }

  function interact(keep) {
    stopAuto(keep);
    scheduleAuto(12000);
  }

  /* ------------------------------------------------------------------ */
  /* Input                                                               */
  /* ------------------------------------------------------------------ */

  stage.addEventListener('keydown', function (e) {
    var key = e.key;
    var letter = key.length === 1 && /[a-z]/i.test(key) && !e.metaKey && !e.ctrlKey && !e.altKey;

    if (key === ' ' || key === 'Spacebar') {
      e.preventDefault();
      if (e.repeat) return;
      var userLabels = session && !auto;
      interact(false);
      if (userLabels) cancel('Cancelled.');
      else showLabels(false);
      return;
    }
    if (!session) return;               // nothing up: let every other key through
    if (key === 'Escape') { e.preventDefault(); interact(false); cancel('Cancelled.'); return; }
    if (key === 'Backspace') { e.preventDefault(); interact(true); backspace(); return; }
    if (letter) { e.preventDefault(); interact(true); typeLetter(key.toUpperCase()); }
  });

  stage.addEventListener('pointerdown', function (e) {
    interact(!!labelAt(e.clientX, e.clientY));
  });

  stage.addEventListener('click', function (e) {
    var hit = labelAt(e.clientX, e.clientY);
    if (hit) { choose(hit); return; }
    var t = e.target.closest('[data-act]');
    if (session) cancel();
    if (t) {
      if (openMenu && t === openMenu.title) { closeMenu(); say('Closed: ' + nameOf(t) + '.'); return; }
      activate(t, false, false);
    } else if (openMenu && !e.target.closest('.menu')) {
      closeMenu();
    }
  });

  var keepFocusFromButton = false;
  toggleBtn.addEventListener('pointerdown', function () { keepFocusFromButton = true; });
  toggleBtn.addEventListener('click', function () {
    keepFocusFromButton = false;
    var userLabels = session && !auto;
    interact(false);
    if (userLabels) cancel('Cancelled.');
    else showLabels(false);
    stage.focus({ preventScroll: true });
  });

  stage.addEventListener('focusin', function () { active = true; stage.classList.add('is-active'); updatePrompt(); });
  stage.addEventListener('focusout', function (e) {
    if (stage.contains(e.relatedTarget)) return;
    active = false;
    stage.classList.remove('is-active');
    if (!keepFocusFromButton && session && !session.auto) cancel();
    updatePrompt();
  });

  var lastWidth = window.innerWidth;
  window.addEventListener('resize', function () {
    if (window.innerWidth === lastWidth) return; // phones fire resize on scroll
    lastWidth = window.innerWidth;
    if (session && !session.locked) { session.auto ? stopAuto() : cancel(); say(idleCaption()); scheduleAuto(6000); }
  });

  if ('IntersectionObserver' in window) {
    new IntersectionObserver(function (entries) {
      inView = entries[0].isIntersecting;
      if (!inView && auto) { stopAuto(); scheduleAuto(4000); }
    }, { threshold: 0.35 }).observe(stage);
  }

  document.addEventListener('visibilitychange', function () {
    if (document.hidden && auto) { stopAuto(); scheduleAuto(4000); }
  });

  function onMotionChange() { if (reduced()) { clearTimeout(idleTimer); stopAuto(); } else scheduleAuto(6000); }
  if (reduceMQ.addEventListener) reduceMQ.addEventListener('change', onMotionChange);
  if (coarseMQ.addEventListener) coarseMQ.addEventListener('change', updatePrompt);

  // Crossing the phone breakpoint (rotation) changes which display exists:
  // end any label session cleanly rather than leave stale labels.
  function onPhoneChange() {
    stopAuto();
    cancel();
    closeMenu();
    stage.setAttribute('aria-label', phone() ? 'A pretend Mac' : 'A pretend Mac with two displays');
    say(idleCaption());
    updatePrompt();
    scheduleAuto(6000);
  }
  if (phoneMQ.addEventListener) phoneMQ.addEventListener('change', onPhoneChange);

  /* ------------------------------------------------------------------ */

  renderChat();
  renderBrowser();
  if (phone()) stage.setAttribute('aria-label', 'A pretend Mac');
  say(idleCaption());
  updatePrompt();
  scheduleAuto(3000);
})();
