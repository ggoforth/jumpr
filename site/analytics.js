/* Plausible Analytics for getjumpr.app (JUM-80).
 * Cookieless, page views only: no custom events, nothing stored on the device.
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
})();
