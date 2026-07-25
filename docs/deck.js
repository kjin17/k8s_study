(function () {
  var slides = Array.prototype.slice.call(document.querySelectorAll('.slide'));
  var dotsBox = document.getElementById('dots');
  var KEY = 'k8s-deck-' + location.pathname;
  var idx = 0;
  var saved = parseInt(localStorage.getItem(KEY), 10);
  if (!isNaN(saved) && saved >= 0 && saved < slides.length) idx = saved;

  slides.forEach(function (_, i) {
    var d = document.createElement('div');
    d.className = 'dot' + (i === idx ? ' on' : '');
    d.addEventListener('click', function () { go(i); });
    dotsBox.appendChild(d);
  });
  var dots = Array.prototype.slice.call(dotsBox.children);

  function go(i) {
    idx = (i + slides.length) % slides.length;
    slides.forEach(function (s, k) { s.classList.toggle('active', k === idx); });
    dots.forEach(function (d, k) { d.classList.toggle('on', k === idx); });
    try { localStorage.setItem(KEY, idx); } catch (e) {}
  }
  go(idx);
  document.getElementById('prev').addEventListener('click', function () { go(idx - 1); });
  document.getElementById('next').addEventListener('click', function () { go(idx + 1); });
  document.addEventListener('keydown', function (e) {
    if (e.key === 'ArrowLeft') go(idx - 1);
    if (e.key === 'ArrowRight' || e.key === ' ') { e.preventDefault(); go(idx + 1); }
  });

  function fit() {
    var deck = document.getElementById('deck');
    var de = document.documentElement;
    var w = de.clientWidth || window.innerWidth;
    var h = de.clientHeight || window.innerHeight;
    var s = Math.min(w / 1280, h / 720) * 0.96;
    deck.style.transform = 'scale(' + s + ')';
  }
  window.addEventListener('resize', fit);
  fit();
})();
