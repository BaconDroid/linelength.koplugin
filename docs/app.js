/* Line Length project page. No libraries, no network requests. */
(() => {
  'use strict';

  const $ = (sel, root = document) => root.querySelector(sel);
  const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];
  const root = document.documentElement;
  const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)').matches;

  /* ---------- theme switch (remembered in this browser only) ---------- */
  const themeBtn = $('#theme');
  const effectiveTheme = () =>
    root.dataset.theme || (matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light');
  if (themeBtn) {
    themeBtn.addEventListener('click', () => {
      const next = effectiveTheme() === 'dark' ? 'light' : 'dark';
      root.dataset.theme = next;
      try { localStorage.setItem('ll-theme', next); } catch (e) { /* private mode: fine */ }
    });
  }

  /* ---------- header gets a rule once the page scrolls ---------- */
  const header = $('header.site');
  const onScroll = () => header && header.classList.toggle('scrolled', window.scrollY > 8);
  onScroll();
  addEventListener('scroll', onScroll, { passive: true });

  /* ---------- reveal on scroll ---------- */
  const reveals = $$('.reveal');
  if ('IntersectionObserver' in window && !reduceMotion) {
    const io = new IntersectionObserver((entries) => {
      for (const e of entries) {
        if (e.isIntersecting) { e.target.classList.add('in'); io.unobserve(e.target); }
      }
    }, { threshold: 0.12, rootMargin: '0px 0px -6% 0px' });
    reveals.forEach((el) => io.observe(el));
  } else {
    reveals.forEach((el) => el.classList.add('in'));
  }

  /* ---------- a small tilt on the screenshots (mouse only) ---------- */
  if (!reduceMotion && matchMedia('(hover: hover) and (pointer: fine)').matches) {
    $$('.frame').forEach((frame) => {
      frame.addEventListener('pointermove', (e) => {
        const r = frame.getBoundingClientRect();
        const x = (e.clientX - r.left) / r.width - 0.5;
        const y = (e.clientY - r.top) / r.height - 0.5;
        frame.classList.add('tilting');
        frame.style.setProperty('--ry', (x * 7).toFixed(2) + 'deg');
        frame.style.setProperty('--rx', (-y * 7).toFixed(2) + 'deg');
      });
      frame.addEventListener('pointerleave', () => {
        frame.classList.remove('tilting');
        frame.style.setProperty('--rx', '0deg');
        frame.style.setProperty('--ry', '0deg');
      });
    });
  }

  /* ---------- the demo: count the longest rendered line, as the plugin does ---------- */
  const demo = $('#demo');
  const page = $('#page');
  if (!demo || !page) return;

  // Same edges as the plugin (linelength/rating.lua): 50 / 67 / 76 / 81.
  const BANDS = [
    { id: 'short', name: 'Short', min: 0 },
    { id: 'excellent', name: 'Excellent', min: 50 },
    { id: 'comfortable', name: 'Comfortable', min: 67 },
    { id: 'readable', name: 'Still readable', min: 76 },
    { id: 'long', name: 'Too long', min: 81 },
  ];
  const bandFor = (n) => BANDS.reduce((b, x) => (n >= x.min ? x : b), BANDS[0]);

  // Put every word in its own span so the browser's own line breaking can be read back.
  const words = [];
  $$('p', page).forEach((p) => {
    const list = p.textContent.trim().split(/[ \n\t]+/);
    p.textContent = '';
    list.forEach((text, i) => {
      const span = document.createElement('span');
      span.className = 'w';
      span.dataset.n = String([...text].length);
      span.textContent = i < list.length - 1 ? text + ' ' : text;
      p.append(span);
      words.push(span);
    });
  });

  const box = $('.page-box', demo);
  const countEl = $('#count');
  const verdictEl = $('#verdict');
  const markerEl = $('#marker');
  const liveEl = $('#live');
  const margins = $('#margins');
  const smaller = $('#smaller');
  const larger = $('#larger');

  const SIZES = [2.5, 2.8, 3.1, 3.45, 3.85];   // text size, in % of the page width
  let size = 0;
  let last = { n: -1, id: '' };
  let liveTimer = 0;

  function measure() {
    const limit = box.clientHeight;
    const lines = new Map();
    for (const w of words) {
      if (w.offsetTop + w.offsetHeight > limit) continue;     // not on the page
      const key = w.offsetTop;
      if (!lines.has(key)) lines.set(key, []);
      lines.get(key).push(w);
    }
    let best = [], bestN = 0;
    for (const ws of lines.values()) {
      const n = ws.reduce((sum, w) => sum + Number(w.dataset.n), 0) + ws.length - 1;
      if (n > bestN) { bestN = n; best = ws; }
    }
    const band = bandFor(bestN);
    words.forEach((w) => w.classList.remove('longest'));
    best.forEach((w) => w.classList.add('longest'));

    demo.dataset.band = band.id;
    countEl.textContent = bestN || '\u2013';
    verdictEl.textContent = band.name;
    markerEl.style.left = Math.min(bestN, 100) + '%';

    if (bestN !== last.n || band.id !== last.id) {
      last = { n: bestN, id: band.id };
      if (liveEl) {            // announce once things settle, not on every step of a drag
        clearTimeout(liveTimer);
        liveTimer = setTimeout(() => {
          liveEl.textContent = 'Longest line: ' + bestN + ' characters. ' + band.name + '.';
        }, 500);
      }
    }
  }

  let queued = false;
  const schedule = () => {
    if (queued) return;
    queued = true;
    requestAnimationFrame(() => { queued = false; measure(); });
  };

  function apply() {
    page.style.setProperty('--m', margins.value + 'cqw');
    page.style.setProperty('--fs', SIZES[size] + 'cqw');
    smaller.disabled = size === 0;
    larger.disabled = size === SIZES.length - 1;
    schedule();
  }

  margins.addEventListener('input', apply);
  smaller.addEventListener('click', () => { if (size > 0) { size -= 1; apply(); } });
  larger.addEventListener('click', () => { if (size < SIZES.length - 1) { size += 1; apply(); } });

  if ('ResizeObserver' in window) new ResizeObserver(schedule).observe(box);
  if (document.fonts && document.fonts.ready) document.fonts.ready.then(schedule);
  apply();
})();
