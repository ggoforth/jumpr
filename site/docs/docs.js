/* The behavior every docs page shares. Written by hand; the pages around it
   are built from docs-src/ by scripts/build-docs.mjs. Without this script a
   page still reads top to bottom: the sidebar stays open and the two buttons
   below are not shown (docs.css). */
(function () {
  var docs = document.getElementById('docs');
  if (!docs) return;
  docs.classList.add('js');

  // Phone: the sidebar opens and closes under its button.
  var menu = document.getElementById('docs-menu');
  menu.addEventListener('click', function () {
    menu.setAttribute('aria-expanded', String(docs.classList.toggle('nav-open')));
  });

  // Copy for AI: the page's Markdown source sits beside it.
  var copy = document.getElementById('docs-copy');
  copy.addEventListener('click', function () {
    fetch(copy.getAttribute('data-md'))
      .then(function (r) { if (!r.ok) throw new Error(r.status); return r.text(); })
      .then(function (md) { return navigator.clipboard.writeText(md); })
      .then(function () { return 'Copied as Markdown'; }, function () { return 'Could not copy'; })
      .then(function (said) {
        var was = copy.textContent;
        copy.textContent = said;
        setTimeout(function () { copy.textContent = was; }, 1800);
      });
  });

  // On this page: mark the section being read.
  var links = document.querySelectorAll('.docs-toc a');
  if (links.length && 'IntersectionObserver' in window) {
    links[0].classList.add('is-active');
    var seen = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (!e.isIntersecting) return;
        Array.prototype.forEach.call(links, function (l) {
          l.classList.toggle('is-active', l.getAttribute('href') === '#' + e.target.id);
        });
      });
    }, { rootMargin: '0px 0px -70% 0px' });
    Array.prototype.forEach.call(document.querySelectorAll('.docs-article h2[id]'), function (h) { seen.observe(h); });
  }
})();
