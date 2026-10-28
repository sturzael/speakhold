// Live GitHub star count in the nav. Unauthenticated API, 60 requests an hour per visitor, cached for an hour in
// localStorage. The number is shown only once it is past ten, so the chip never advertises a zero.
(function () {
  var el = document.querySelector('[data-stars]'); if (!el) return;
  function show(n) { if (n >= 10) { el.textContent = n >= 1000 ? (n / 1000).toFixed(1).replace(/\.0$/, '') + 'k' : String(n); el.hidden = false; } }
  try { var c = JSON.parse(localStorage.getItem('speakhold-stars') || 'null'); if (c && Date.now() - c.t < 3600e3) { show(c.n); return; } } catch (e) {}
  fetch('https://api.github.com/repos/sturzael/speakhold').then(function (r) { return r.ok ? r.json() : null; }).then(function (j) {
    if (!j) return; var n = j.stargazers_count || 0; show(n);
    try { localStorage.setItem('speakhold-stars', JSON.stringify({ n: n, t: Date.now() })); } catch (e) {}
  }).catch(function () {});
})();
