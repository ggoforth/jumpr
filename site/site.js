/* Jumpr site: the page below the demo.
 * Plays each drawing once when it scrolls into view, runs the "Type to narrow"
 * button and the label color swatches. No dependencies, no key handlers
 * (Space belongs to the demo). With reduced motion or no JavaScript every
 * drawing simply shows its finished state.
 */
(function () {
  'use strict';

  var root = document.documentElement;
  root.classList.add('js');   // the buttons below only show when they can work
  var motion = !window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  /* Play once on scroll into view. `anim` hides the pieces that pop in, so it
     is only set when they are certain to be played. */
  var narrowTouched = false;
  if (motion && 'IntersectionObserver' in window) {
    root.classList.add('anim');
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (!e.isIntersecting) return;
        io.unobserve(e.target);
        e.target.classList.add('play');
        if (e.target.classList.contains('t-narrow')) {
          setTimeout(function () { if (!narrowTouched) setNarrow(true); }, 1100);
          setTimeout(function () { if (!narrowTouched) setNarrow(false); }, 3200);
        }
      });
    }, { threshold: 0.3 });
    Array.prototype.forEach.call(document.querySelectorAll('[data-play]'), function (el) { io.observe(el); });
  }

  /* Type to narrow */
  var narrow = document.querySelector('[data-narrow]');
  var narrowBtn = document.querySelector('[data-narrow-btn]');
  function setNarrow(on) {
    narrow.classList.toggle('is-narrowed', on);
    narrowBtn.setAttribute('aria-pressed', on ? 'true' : 'false');
  }
  if (narrow && narrowBtn) {
    narrowBtn.addEventListener('click', function () {
      narrowTouched = true;
      setNarrow(narrowBtn.getAttribute('aria-pressed') !== 'true');
    });
  }

  /* Label color: one CSS variable recolors every label on the page, the
     demo's included. Not stored: a reload brings back yellow. */
  var note = document.querySelector('.swatch-note');
  var swatches = document.querySelectorAll('.swatch');
  Array.prototype.forEach.call(swatches, function (b) {
    b.addEventListener('click', function () {
      root.style.setProperty('--label', b.getAttribute('data-bg'));
      root.style.setProperty('--on-label', b.getAttribute('data-fg'));
      Array.prototype.forEach.call(swatches, function (o) { o.setAttribute('aria-pressed', o === b ? 'true' : 'false'); });
      var name = b.getAttribute('data-name');
      if (note) note.textContent = name === 'yellow' ? 'Yellow is the default.' : 'Every label on this page is now ' + name + '. Reload for yellow.';
    });
  });
})();
