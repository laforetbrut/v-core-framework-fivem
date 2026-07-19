// v-target — interaction eye NUI (free cursor: hover an entity, click an option)
const byId = (id) => document.getElementById(id);
const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const post = (n, b) => fetch(`https://v-target/${n}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(b || {}) }).catch(() => {});

const ICONS = {
  trunk: 'M4 9h16v9H4zM4 9l2-4h12l2 4M9 13h6',
  box: 'M3 7l9-4 9 4v10l-9 4-9-4V7ZM3 7l9 4 9-4M12 11v10',
  door: 'M6 3h9v18H6zM15 3l3 2v14l-3 2M11 12h.5',
  hood: 'M3 16h18l-2-5a4 4 0 0 0-4-3H9a4 4 0 0 0-4 3l-2 5ZM7 16v3M17 16v3',
  engine: 'M5 9h3V6h5l2 3h3v3h-2v3H8v-3H5zM3 11h2M19 12h2',
  lock: 'M6 10V7a6 6 0 0 1 12 0v3M4 10h16v11H4zM12 14v3',
  unlock: 'M6 10V7a6 6 0 0 1 11-3M4 10h16v11H4zM12 14v3',
  flip: 'M4 8a8 8 0 0 1 14-4M20 4v4h-4M20 16a8 8 0 0 1-14 4M4 20v-4h4',
  clean: 'M4 20l6-14 2 1-6 14zM14 4l2 1M17 7l2 1M12 9l6 3',
  search: 'M11 4a7 7 0 1 0 0 14 7 7 0 0 0 0-14ZM20 20l-4-4',
  shield: 'M12 3l7 3v5c0 5-3 8-7 10-4-2-7-5-7-10V6l7-3Z',
  wrench: 'M14 6a4 4 0 0 0-5 5L4 16l4 4 5-5a4 4 0 0 0 5-5l-3 3-2-2 3-3a4 4 0 0 0-2-2Z',
  heal: 'M12 4v16M4 12h16',
  freeze: 'M12 3v18M4.5 7.5l15 9M19.5 7.5l-15 9',
  eye: 'M2 12s4-7 10-7 10 7 10 7-4 7-10 7-10-7-10-7ZM12 9a3 3 0 1 0 0 6 3 3 0 0 0 0-6Z',
  shop: 'M4 9h16l-1 11H5L4 9ZM4 9l1-4h14l1 4M9 13a3 3 0 0 0 6 0',
  cash: 'M3 6h18v12H3zM12 9a3 3 0 1 0 0 6 3 3 0 0 0 0-6ZM6 9v.01M18 15v.01',
  tp: 'M12 3l4 4-4 4M8 21l-4-4 4-4M16 7H4M8 17h12',
  dot: 'M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8Z',
};
const svg = (name) => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="${ICONS[name] || ICONS.dot}"/></svg>`;

let cx = 0.5, cy = 0.5, lastPx = 0, lastPy = 0;

function positionOpts() {
  const wrap = byId('opts');
  // Keep the panel on-screen (flip left if near the right edge).
  const w = wrap.offsetWidth || 220, h = wrap.offsetHeight || 40;
  let x = lastPx + 18, y = lastPy - 6;
  if (x + w > window.innerWidth - 8) x = lastPx - w - 18;
  if (y + h > window.innerHeight - 8) y = window.innerHeight - h - 8;
  if (y < 8) y = 8;
  wrap.style.left = x + 'px';
  wrap.style.top = y + 'px';
}

let optCount = 0;
function renderOptions(list) {
  const wrap = byId('opts');
  wrap.innerHTML = '';
  const has = Array.isArray(list) && list.length > 0;
  optCount = has ? list.length : 0;
  wrap.classList.toggle('empty', !has);
  if (!has) return;
  list.forEach((o) => {
    const row = document.createElement('div');
    row.className = 'opt';
    row.style.setProperty('--i', o.n - 1);
    row.innerHTML = `<span class="num">${o.n}</span><span class="ico">${svg(o.icon)}</span><span class="lbl">${esc(o.label)}</span>`;
    row.onmousedown = (e) => { e.preventDefault(); post('select', { index: o.n }); };
    wrap.appendChild(row);
  });
  positionOpts();
}

// Track the free cursor and forward it (throttled) to Lua for the world raycast.
let lastPostX = -1, lastPostY = -1, lastPostT = 0;
document.addEventListener('mousemove', (e) => {
  lastPx = e.clientX; lastPy = e.clientY;
  cx = e.clientX / window.innerWidth;
  cy = e.clientY / window.innerHeight;
  byId('cursor').style.transform = `translate(${lastPx}px, ${lastPy}px)`;
  // The options panel is NOT re-anchored here — it stays where it appeared so
  // the cursor can travel onto a row and click it.
  // Posts are throttled: the Lua raycast reads ONE cursor value per frame, so a
  // post per mousemove (30-60/s) only floods the NUI channel and can starve a
  // real click ('select'). Send at most every 50ms and only when actually moved.
  const now = performance.now();
  const moved = Math.abs(lastPx - lastPostX) > 6 || Math.abs(lastPy - lastPostY) > 6;
  if (moved && now - lastPostT > 50) {
    lastPostX = lastPx; lastPostY = lastPy; lastPostT = now;
    post('cursor', { x: cx, y: cy });
  }
});

// Right-click or Escape closes the eye; number keys 1-9 trigger an option.
document.addEventListener('contextmenu', (e) => { e.preventDefault(); post('closeeye'); });
document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') { post('closeeye'); return; }
  const n = parseInt(e.key, 10);
  if (n >= 1 && n <= Math.min(optCount, 9)) post('select', { index: n });
});
// Releasing Alt closes the eye (hold-to-use). The page holds keyboard focus
// while the eye is open, so this DOM keyup is the ground truth — the game's own
// release signal (-vtarget / IsControlPressed) is fabricated once NUI focus
// grabs the keyboard mid-hold.
document.addEventListener('keyup', (e) => { if (e.key === 'Alt' || e.key === 'AltGraph') post('closeeye'); });

// Report panel hover to Lua: while the cursor is over the options list, the
// sticky target must not re-acquire whatever entity sits behind the panel.
const optsWrap = byId('opts');
optsWrap.addEventListener('mouseover', (e) => { if (!optsWrap.contains(e.relatedTarget)) post('panel', { hover: true }); });
optsWrap.addEventListener('mouseout', (e) => { if (!optsWrap.contains(e.relatedTarget)) post('panel', { hover: false }); });

// If this page loses keyboard focus while the eye is open (another menu grabbed
// it, the game window lost focus…), the Alt keyup will never arrive — ask Lua
// to close rather than leaving the eye stuck.
window.addEventListener('blur', () => post('closeeye'));

window.addEventListener('message', (e) => {
  const d = e.data || {};
  if (d.action === 'eyeon') { byId('eye').classList.remove('hidden'); document.documentElement.classList.add('eyeopen'); lastPx = window.innerWidth / 2; lastPy = window.innerHeight / 2; renderOptions([]); }
  else if (d.action === 'eyeoff') { byId('eye').classList.add('hidden'); document.documentElement.classList.remove('eyeopen'); renderOptions([]); }
  else if (d.action === 'options') { renderOptions(d.options || []); }
});
