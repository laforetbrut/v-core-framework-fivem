// v-target — interaction eye NUI
//
// The world ray is cast from the screen centre in Lua. This page never tells Lua where
// to look; it only draws what Lua found and reports which row was chosen. That split is
// why the cursor no longer has to be round-tripped through the NUI channel every frame.

const byId = (id) => document.getElementById(id);
const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const post = (n, b) => fetch(`https://v-target/${n}`, {
  method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(b || {}),
}).catch(() => {});

// ── Icons ──────────────────────────────────────────────────────
// One flat path each, stroked. Anything the catalogue asks for that is missing falls
// back to `dot`, so a new option never renders as a broken box.
const ICONS = {
  // storage & vehicle parts
  trunk: 'M4 9h16v9H4zM4 9l2-4h12l2 4M9 13h6',
  box: 'M3 7l9-4 9 4v10l-9 4-9-4V7ZM3 7l9 4 9-4M12 11v10',
  bag: 'M6 8h12l1 12H5L6 8ZM9 8V6a3 3 0 0 1 6 0v2',
  door: 'M6 3h9v18H6zM15 3l3 2v14l-3 2M11 12h.5',
  hood: 'M3 16h18l-2-5a4 4 0 0 0-4-3H9a4 4 0 0 0-4 3l-2 5ZM7 16v3M17 16v3',
  engine: 'M5 9h3V6h5l2 3h3v3h-2v3H8v-3H5zM3 11h2M19 12h2',
  wheel: 'M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18Zm0 5a4 4 0 1 0 0 8 4 4 0 0 0 0-8ZM12 3v5M4 16l4-2M20 16l-4-2',
  fuel: 'M4 21V5a2 2 0 0 1 2-2h6a2 2 0 0 1 2 2v16M3 21h12M4 11h10M17 8l3 3v7a2 2 0 0 1-4 0V9',
  lock: 'M6 10V7a6 6 0 0 1 12 0v3M4 10h16v11H4zM12 14v3',
  unlock: 'M6 10V7a6 6 0 0 1 11-3M4 10h16v11H4zM12 14v3',
  key: 'M15 4a5 5 0 1 1-4.6 7L4 17.4V20h3v-2h2v-2h2l1.4-1.4A5 5 0 0 1 15 4Z',
  flip: 'M4 8a8 8 0 0 1 14-4M20 4v4h-4M20 16a8 8 0 0 1-14 4M4 20v-4h4',
  clean: 'M4 20l6-14 2 1-6 14zM14 4l2 1M17 7l2 1M12 9l6 3',
  wrench: 'M14 6a4 4 0 0 0-5 5L4 16l4 4 5-5a4 4 0 0 0 5-5l-3 3-2-2 3-3a4 4 0 0 0-2-2Z',
  plate: 'M3 7h18v10H3zM6 11h3M11 11h2M15 11h3M6 14h12',
  seat: 'M7 4h6a2 2 0 0 1 2 2v8H7zM7 14h10a2 2 0 0 1 2 2v4M5 20v-6',
  // people
  person: 'M12 3a4 4 0 1 0 0 8 4 4 0 0 0 0-8ZM4 21a8 8 0 0 1 16 0',
  hands: 'M8 13V5a1.5 1.5 0 0 1 3 0v6M11 11V4a1.5 1.5 0 0 1 3 0v7M14 11V6a1.5 1.5 0 0 1 3 0v9a6 6 0 0 1-6 6H9l-4-5 2-2',
  cuff: 'M8 7a3 3 0 1 0 0 6 3 3 0 0 0 0-6ZM16 11a3 3 0 1 0 0 6 3 3 0 0 0 0-6ZM10 10l4 3',
  search: 'M11 4a7 7 0 1 0 0 14 7 7 0 0 0 0-14ZM20 20l-4-4',
  id: 'M3 5h18v14H3zM8 11a2 2 0 1 0 0-4 2 2 0 0 0 0 4ZM5 16c.6-2 5-2 6 0M14 9h4M14 13h4',
  heal: 'M12 4v16M4 12h16',
  pulse: 'M3 12h4l2-6 4 12 2-6h6',
  drag: 'M5 20l6-8M11 12l2-8M13 4h6M9 20h6',
  give: 'M4 12h9M13 8l4 4-4 4M17 4h3v16h-3',
  // world & places
  shop: 'M4 9h16l-1 11H5L4 9ZM4 9l1-4h14l1 4M9 13a3 3 0 0 0 6 0',
  cash: 'M3 6h18v12H3zM12 9a3 3 0 1 0 0 6 3 3 0 0 0 0-6ZM6 9v.01M18 15v.01',
  bank: 'M3 10h18L12 4 3 10ZM5 10v8M10 10v8M14 10v8M19 10v8M3 20h18',
  house: 'M4 11l8-7 8 7v9H4zM10 20v-6h4v6',
  garage: 'M3 20V9l9-5 9 5v11M7 20v-7h10v7M7 16h10',
  work: 'M4 8h16v12H4zM9 8V6a2 2 0 0 1 2-2h2a2 2 0 0 1 2 2v2M4 13h16',
  craft: 'M12 3l2.5 5.5L20 11l-5.5 2.5L12 19l-2.5-5.5L4 11l5.5-2.5Z',
  farm: 'M12 21V9M12 9c0-3 2-5 5-5 0 3-2 5-5 5ZM12 12c0-3-2-5-5-5 0 3 2 5 5 5Z',
  radio: 'M4 9h16v11H4zM8 9l10-4M8 15h4M17 14a1 1 0 1 0 0 2 1 1 0 0 0 0-2Z',
  music: 'M9 18V5l10-2v13M9 18a3 3 0 1 1-6 0 3 3 0 0 1 6 0ZM19 16a3 3 0 1 1-6 0 3 3 0 0 1 6 0Z',
  phone: 'M7 2h10v20H7zM10 5h4M12 19h.01',
  // status & tools
  shield: 'M12 3l7 3v5c0 5-3 8-7 10-4-2-7-5-7-10V6l7-3Z',
  eye: 'M2 12s4-7 10-7 10 7 10 7-4 7-10 7-10-7-10-7ZM12 9a3 3 0 1 0 0 6 3 3 0 0 0 0-6Z',
  tp: 'M12 3l4 4-4 4M8 21l-4-4 4-4M16 7H4M8 17h12',
  freeze: 'M12 3v18M4.5 7.5l15 9M19.5 7.5l-15 9',
  clock: 'M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18ZM12 7v5l3 2',
  info: 'M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18ZM12 11v6M12 8v.01',
  flag: 'M5 21V4h11l-1.5 3L16 10H5',
  dot: 'M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8Z',
};
const svg = (name) =>
  `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="${ICONS[name] || ICONS.dot}"/></svg>`;
const CHEVRON =
  '<svg class="chev" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M9 5l7 7-7 7"/></svg>';

// ── State ──────────────────────────────────────────────────────
let rows = [];      // the option payload currently drawn
let sel = 0;        // highlighted index, 0-based
let depth = 1;      // 1 = root list, >1 = inside a submenu
let hints = {};

function paintSelection() {
  const wrap = byId('rows');
  const kids = wrap.children;
  for (let i = 0; i < kids.length; i++) kids[i].classList.toggle('sel', i === sel);
  const el = kids[sel];
  // Only scroll when the row is actually out of view: calling this unconditionally makes
  // a mouse hovering near the edge fight the scroll position.
  if (el && el.scrollIntoView) {
    const box = wrap.getBoundingClientRect();
    const r = el.getBoundingClientRect();
    if (r.top < box.top || r.bottom > box.bottom) el.scrollIntoView({ block: 'nearest' });
  }
}

function render(list, title) {
  rows = Array.isArray(list) ? list : [];
  const wrap = byId('rows');
  const panel = byId('panel');
  wrap.innerHTML = '';

  if (!rows.length) { panel.classList.add('hidden'); return; }
  panel.classList.remove('hidden');

  byId('ttl').textContent = title || '';
  byId('back').classList.toggle('hidden', depth <= 1);

  rows.forEach((o, i) => {
    const row = document.createElement('div');
    row.className = 'row' + (o.blocked ? ' blocked' : '');
    row.style.setProperty('--i', i);
    const sub = o.blocked || o.hint;
    row.innerHTML =
      `<span class="num">${o.n === 10 ? 0 : o.n}</span>` +
      `<span class="ico">${svg(o.icon)}</span>` +
      `<span class="txt"><span class="lbl">${esc(o.label)}</span>` +
      (sub ? `<span class="sub">${esc(sub)}</span>` : '') +
      `</span>` +
      (o.sub ? CHEVRON : '');
    // Hover and keyboard share one highlight, so the row you see lit is the row Enter runs.
    row.addEventListener('mouseenter', () => { sel = i; paintSelection(); });
    row.addEventListener('mousedown', (e) => { e.preventDefault(); post('select', { index: o.n }); });
    wrap.appendChild(row);
  });

  if (sel >= rows.length) sel = rows.length - 1;
  if (sel < 0) sel = 0;
  paintSelection();

  // Only flag the overflow fade when the list genuinely overflows: drawn unconditionally
  // it would sit on top of the last row of every short menu.
  panel.classList.toggle('scrolls', wrap.scrollHeight > wrap.clientHeight + 1);
}

function reticle(state) {
  const r = byId('reticle');
  r.classList.toggle('live', state === 'live');
  r.classList.toggle('self', state === 'self');
}

function footer() {
  byId('foot').innerHTML =
    `<span><b>&uarr;&darr;</b> ${esc(hints.nav || '')}</span>` +
    `<span><b>&crarr;</b> ${esc(hints.pick || '')}</span>` +
    `<span><b>ESC</b> ${esc(hints.close || '')}</span>`;
}

// ── Input ──────────────────────────────────────────────────────
document.addEventListener('mousemove', (e) => {
  byId('cursor').style.transform = `translate(${e.clientX}px, ${e.clientY}px)`;
});

document.addEventListener('contextmenu', (e) => { e.preventDefault(); post('closeeye'); });

// Scrolling moves the selection. It is the fastest way through a long list and costs
// nothing, since the camera is not ours to scroll while the eye is open.
document.addEventListener('wheel', (e) => {
  if (!rows.length) return;
  sel = (sel + (e.deltaY > 0 ? 1 : -1) + rows.length) % rows.length;
  paintSelection();
}, { passive: true });

document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') { post('closeeye'); return; }
  if (e.key === 'Backspace' || e.key === 'ArrowLeft') { if (depth > 1) post('back'); return; }
  if (!rows.length) return;

  if (e.key === 'ArrowDown') { sel = (sel + 1) % rows.length; paintSelection(); e.preventDefault(); return; }
  if (e.key === 'ArrowUp')   { sel = (sel - 1 + rows.length) % rows.length; paintSelection(); e.preventDefault(); return; }
  if (e.key === 'Enter' || e.key === ' ' || e.key === 'ArrowRight') {
    const o = rows[sel];
    if (o) post('select', { index: o.n });
    e.preventDefault();
    return;
  }
  // Number keys map to the badge on each row. '0' is the tenth, which is what the badge
  // shows, so the two never disagree.
  let n = parseInt(e.key, 10);
  if (e.key === '0') n = 10;
  if (n >= 1 && n <= Math.min(rows.length, 10)) post('select', { index: n });
});

// Releasing the hold key closes the eye. The page holds keyboard focus while the eye is
// open, so this DOM keyup is the ground truth: the game's own release signal is
// fabricated once SetNuiFocus grabs the keyboard mid-hold.
document.addEventListener('keyup', (e) => {
  if (e.key === 'Alt' || e.key === 'AltGraph') post('closeeye');
});

byId('back').addEventListener('mousedown', (e) => { e.preventDefault(); post('back'); });

// If this page loses keyboard focus while the eye is open (another menu grabbed it, the
// game window lost focus…), the keyup will never arrive — ask Lua to close rather than
// leaving the eye stuck holding NUI focus.
window.addEventListener('blur', () => post('closeeye'));

// ── Lua → page ─────────────────────────────────────────────────
window.addEventListener('message', (e) => {
  const d = e.data || {};
  if (d.action === 'eyeon') {
    hints = d.hints || {};
    footer();
    sel = 0; depth = 1;
    byId('eye').classList.remove('hidden');
    document.documentElement.classList.add('eyeopen');
    byId('cursor').style.transform = `translate(${window.innerWidth / 2}px, ${window.innerHeight / 2}px)`;
    reticle(null);
    render([], '');
  } else if (d.action === 'eyeoff') {
    byId('eye').classList.add('hidden');
    document.documentElement.classList.remove('eyeopen');
    render([], '');
    reticle(null);
  } else if (d.action === 'options') {
    const prevDepth = depth;
    depth = d.depth || 1;
    // Entering or leaving a submenu starts the new list at the top; a live refresh of the
    // same list must not yank the highlight away from the row under the cursor.
    if (depth !== prevDepth) sel = 0;
    render(d.options || [], d.title);
    const list = d.options || [];
    reticle(list.length ? (d.self ? 'self' : 'live') : null);
  }
});
