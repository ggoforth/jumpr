/* Plausible Analytics for getjumpr.app.
 * Cookieless: page views, plus one "Download" event per download click.
 * Nothing is stored on the device.
 * The pa- id below names the site in Plausible and is public, not a secret.
 */
(function () {
  window.plausible = window.plausible || function () { (plausible.q = plausible.q || []).push(arguments); };
  plausible.init = plausible.init || function (i) { plausible.o = i || {}; };
  plausible.init();

  var s = document.createElement('script');
  s.async = true;
  s.src = 'https://plausible.io/js/pa-cXcqOcByrqeh1zYdCdG80.js';
  document.head.appendChild(s);

  // Count download clicks. Queued if Plausible has not loaded yet;
  // never blocks or delays the download.
  document.addEventListener('click', function (e) {
    var link = e.target.closest && e.target.closest('a[href$="/Jumpr.zip"]');
    if (link) plausible('Download');
  }, true);
})();
