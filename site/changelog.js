/* Renders releases.json, newest first, a few at a time.
 * The HTML in an entry is first-party: scripts/release-notes.swift allows only a few inline tags.
 */
(function () {
  var PAGE_SIZE = 5;
  var list = document.getElementById('releases');
  var more = document.getElementById('show-older');
  var releases = [];
  var shown = 0;

  // The version is the anchor: #v1-0-5 links to one release, even one not yet shown.
  function anchor(r) { return r.version.replace(/\./g, '-'); }

  function longDate(iso) {
    var p = iso.split('-');
    // Built from parts: parsing the string reads it as UTC, which is the day before in America.
    return new Date(p[0], p[1] - 1, p[2]).toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: 'numeric' });
  }

  function article(r) {
    var bullets = (r.bullets || []).map(function (b) { return '<li>' + b + '</li>'; }).join('');
    return '<article class="release" id="' + anchor(r) + '" tabindex="-1">'
      + '<div class="release-head">'
      + '<h2><a href="#' + anchor(r) + '">' + r.version + '</a></h2>'
      + '<span class="release-date">' + longDate(r.date) + '</span>'
      + '</div>'
      + '<p>' + r.summary + '</p>'
      + (bullets ? '<ul>' + bullets + '</ul>' : '')
      + (r.note ? '<p>' + r.note + '</p>' : '')
      + '</article>';
  }

  function showMore() {
    var next = releases.slice(shown, shown + PAGE_SIZE);
    list.insertAdjacentHTML('beforeend', next.map(article).join(''));
    shown += next.length;
    var left = releases.length - shown;
    more.hidden = left === 0;
    more.textContent = 'Show older releases (' + left + ' more)';
    return next[0];
  }

  function revealHash() {
    var id = location.hash.slice(1);
    if (!/^v[0-9]/.test(id)) return;
    while (!document.getElementById(id) && shown < releases.length) showMore();
    var el = document.getElementById(id);
    if (el) el.scrollIntoView();
  }

  more.addEventListener('click', function () {
    var first = showMore();
    // The button may have just gone away, so keyboard focus moves to what appeared.
    document.getElementById(anchor(first)).focus({ preventScroll: true });
  });
  window.addEventListener('hashchange', revealHash);

  fetch('releases.json')
    .then(function (r) { if (!r.ok) throw new Error(r.status); return r.json(); })
    .then(function (data) {
      releases = data.releases;
      list.textContent = '';
      showMore();
      revealHash();
    })
    .catch(function () {
      list.innerHTML = '<p>The changelog could not load. Every release is also on <a href="https://github.com/ggoforth/jumpr/releases">GitHub</a>.</p>';
    });
})();
