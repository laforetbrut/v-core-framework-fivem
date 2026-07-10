// v-hud — vitals rings + money + compass + fully customizable settings
const RES = 'v-hud';
const CIRC = 113.1;                 // 2*pi*18
const byId = (id) => document.getElementById(id);
const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
const fmt = (n) => '$' + Math.floor(Number(n) || 0).toLocaleString('en-US');
const post = (name, data) => fetch(`https://${RES}/${name}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data || {}) }).catch(() => {});

function lighten(hex, amt) {
  const m = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(hex || '');
  if (!m) return hex;
  const ch = i => clamp(parseInt(m[i], 16) + amt, 0, 255).toString(16).padStart(2, '0');
  return '#' + ch(1) + ch(2) + ch(3);
}

const ICON = {
  health: '<path d="M20.8 5.6a5 5 0 0 0-7.1 0L12 7.3l-1.7-1.7a5 5 0 1 0-7.1 7.1L12 21l8.8-8.3a5 5 0 0 0 0-7.1Z"/>',
  armor:  '<path d="M12 3 5 6v6c0 4 3 6.5 7 9 4-2.5 7-5 7-9V6l-7-3Z"/>',
  hunger: '<path d="M7 3v7a2 2 0 0 0 4 0V3M9 10v11"/><path d="M17 3c-1.5 0-3 1.5-3 4.5S15.5 12 17 12v9"/>',
  thirst: '<path d="M12 3s6 6.4 6 10a6 6 0 0 1-12 0c0-3.6 6-10 6-10Z"/>',
  stress: '<path d="M13 2 4 14h6l-1 8 9-12h-6l1-8Z"/>',
  stamina:'<path d="M3 9h11a3 3 0 1 0-3-3M3 15h13a3 3 0 1 1-3 3"/>',
  oxygen: '<circle cx="11" cy="13" r="6"/><circle cx="18" cy="7" r="2.2"/>',
};

const VITALS = [
  { key: 'health',  danger: v => v <= 20 },
  { key: 'armor',   danger: () => false, hideZero: true },
  { key: 'hunger',  danger: v => v <= 15, warn: v => v <= 25, keep: true },
  { key: 'thirst',  danger: v => v <= 15, warn: v => v <= 25, keep: true },
  { key: 'stress',  danger: v => v >= 70, fullWhenZero: true },
  { key: 'stamina', danger: v => v <= 15 },
  { key: 'oxygen',  danger: v => v <= 30, underwaterOnly: true },
];

const ACCENTS = [
  { c: '#FF6A1A', c2: '#FF9354' }, { c: '#43C46A', c2: '#6FE08D' },
  { c: '#4AA8FF', c2: '#7FC1FF' }, { c: '#E5484D', c2: '#FF6E72' },
  { c: '#F5A623', c2: '#FFC65C' }, { c: '#C77DFF', c2: '#DBA6FF' },
];

const DEFAULTS = {
  elements: { health: true, armor: true, hunger: true, thirst: true, stress: true, stamina: true, oxygen: true, money: true, compass: false, minimap: true },
  positions: {}, accent: '#FF6A1A', opacity: 100, scale: 100, dynamic: true, minimapVehicleOnly: false,
};
let settings = JSON.parse(JSON.stringify(DEFAULTS));
let strings = {};
let lastMoney = { cash: 0, bank: 0 };
let editing = false;
let drag = null;

const t = (k) => strings[k] || k;
const applyStrings = () => document.querySelectorAll('[data-i18n]').forEach(el => { el.textContent = t(el.getAttribute('data-i18n')); });

// ── Rings ──
const rings = {};
function buildRings() {
  const wrap = byId('vitals'); wrap.innerHTML = '';
  for (const v of VITALS) {
    const el = document.createElement('div');
    el.className = 'ring key-' + v.key + (v.keep ? ' keep' : '');
    el.innerHTML =
      `<svg viewBox="0 0 44 44"><circle class="track" cx="22" cy="22" r="18"/><circle class="fill" cx="22" cy="22" r="18"/></svg>` +
      `<span class="ic"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round">${ICON[v.key]}</svg></span>`;
    wrap.appendChild(el);
    rings[v.key] = { el, fill: el.querySelector('.fill') };
  }
}

function renderVitals(data) {
  for (const v of VITALS) {
    const r = rings[v.key]; if (!r) continue;
    const on = settings.elements[v.key];
    const val = clamp(Math.round(data[v.key] || 0), 0, 100);
    const underwaterHide = v.underwaterOnly && !data.underwater;
    const zeroHide = v.hideZero && val <= 0;
    if (!on || underwaterHide || zeroHide) { r.el.classList.add('hidden'); continue; }
    r.el.classList.remove('hidden');
    r.fill.style.strokeDashoffset = CIRC * (1 - val / 100);
    const dngr = v.danger(val);
    r.el.classList.toggle('low', dngr);
    r.el.classList.toggle('warn', !dngr && !!(v.warn && v.warn(val)));
    // hunger/thirst (keep) are never faded — always readable
    const full = v.fullWhenZero ? val <= 2 : val >= 99;
    r.el.classList.toggle('faded', !v.keep && settings.dynamic && full && !dngr && !editing);
  }
}

// ── Compass (scrolling tape) ──
const PX_PER_DEG = 2.4;
const TAPE_TURNS = 3;                 // 0..1080 so the ±window never runs off the tape
const WIN_W = 240;
const CARDINALS = { 0: 'N', 45: 'NE', 90: 'E', 135: 'SE', 180: 'S', 225: 'SW', 270: 'W', 315: 'NW' };
let lastHc = null;

function buildCompassTape() {
  const tape = byId('compass-tape');
  tape.innerHTML = '';
  for (let d = 0; d <= 360 * TAPE_TURNS; d += 15) {
    const deg = ((d % 360) + 360) % 360;
    const card = CARDINALS[deg] !== undefined;
    const tick = document.createElement('div');
    tick.className = 'tick' + (card ? ' card' : '');
    tick.style.left = (d * PX_PER_DEG) + 'px';
    tick.innerHTML = `<span class="bar"></span>${card ? `<span class="lbl">${CARDINALS[deg]}</span>` : ''}`;
    tape.appendChild(tick);
  }
  tape.style.width = (360 * TAPE_TURNS * PX_PER_DEG) + 'px';
}

function renderCompass(rawHeading) {
  const hc = ((360 - (rawHeading || 0)) % 360 + 360) % 360;   // clockwise, N=0
  const tape = byId('compass-tape');
  const tx = (WIN_W / 2) - (hc + 360) * PX_PER_DEG;           // centre on the middle turn
  if (lastHc !== null && Math.abs(hc - lastHc) > 180) {
    tape.style.transition = 'none';                            // don't animate across the 360→0 wrap
    void tape.offsetWidth;
  } else {
    tape.style.transition = 'transform .12s linear';
  }
  tape.style.transform = `translateX(${tx}px)`;
  lastHc = hc;
  byId('compass-deg').textContent = Math.round(hc) + '°';
}

// ── Money ──
function setMoney(cash, bank, flash) {
  const set = (id, value, delta) => {
    const el = byId(id); el.textContent = fmt(value);
    if (flash && delta) { el.classList.remove('flash-up', 'flash-down'); void el.offsetWidth; el.classList.add(delta > 0 ? 'flash-up' : 'flash-down'); }
  };
  set('cash', cash, cash - lastMoney.cash);
  set('bank', bank, bank - lastMoney.bank);
  lastMoney = { cash, bank };
  if (!editing) byId('money').classList.toggle('hidden', !settings.elements.money);
}

// ── Apply settings (live) ──
function applySettings() {
  const root = document.documentElement.style;
  root.setProperty('--hud-opacity', settings.opacity / 100);
  root.setProperty('--hud-scale', settings.scale / 100);
  const preset = ACCENTS.find(x => x.c.toLowerCase() === (settings.accent || '').toLowerCase());
  root.setProperty('--v-accent', settings.accent || '#FF6A1A');
  root.setProperty('--v-accent-300', preset ? preset.c2 : lighten(settings.accent, 40));
  byId('money').classList.toggle('hidden', !settings.elements.money && !editing);
  byId('compass').classList.toggle('hidden', !settings.elements.compass);
  applyLayout();
}

function applyLayout() {
  ['vitals', 'money', 'compass'].forEach(key => {
    const el = byId(key);
    const p = settings.positions && settings.positions[key];
    if (p && typeof p.x === 'number') {
      el.style.left = p.x + 'px'; el.style.top = p.y + 'px';
      el.style.right = 'auto'; el.style.bottom = 'auto'; el.style.transformOrigin = 'top left';
    } else {
      el.style.left = el.style.top = el.style.right = el.style.bottom = el.style.transformOrigin = '';
    }
  });
  applyMinimapFrame();
}

// ── Minimap frame (positioned in SCREEN FRACTIONS so it tracks the native map) ──
let mmFrame = { w: 0.15, h: 0.212, def: { x: 0.0135, y: 0.735 } };
function mmPos() {
  const p = settings.positions && settings.positions.minimap;
  return (p && typeof p.x === 'number') ? p : mmFrame.def;
}
function applyMinimapFrame() {
  const el = byId('minimap'); if (!el) return;
  const p = mmPos();
  el.style.left = (p.x * 100) + 'vw';
  el.style.top = (p.y * 100) + 'vh';
  el.style.width = (mmFrame.w * 100) + 'vw';
  el.style.height = (mmFrame.h * 100) + 'vh';
  el.classList.toggle('hidden', !settings.elements.minimap && !editing);
}

// ── Drag / layout mode ──
['vitals', 'money', 'compass', 'minimap'].forEach(key => {
  byId(key).addEventListener('mousedown', (e) => {
    if (!editing) return;
    e.preventDefault();
    const r = byId(key).getBoundingClientRect();
    drag = { key, el: byId(key), offx: e.clientX - r.left, offy: e.clientY - r.top, frac: key === 'minimap' };
  });
});
let mmRaf = false;
document.addEventListener('mousemove', (e) => {
  if (!drag) return;
  if (drag.frac) {
    // minimap: store as fractions and stream to Lua so the native map follows live
    const x = clamp((e.clientX - drag.offx) / window.innerWidth, 0, 1 - mmFrame.w);
    const y = clamp((e.clientY - drag.offy) / window.innerHeight, 0, 1 - mmFrame.h);
    drag.el.style.left = (x * 100) + 'vw'; drag.el.style.top = (y * 100) + 'vh';
    if (!settings.positions) settings.positions = {};
    settings.positions.minimap = { x, y };
    if (!mmRaf) { mmRaf = true; requestAnimationFrame(() => { mmRaf = false; post('minimapMove', settings.positions.minimap); }); }
    return;
  }
  const x = clamp(e.clientX - drag.offx, 0, window.innerWidth - 40);
  const y = clamp(e.clientY - drag.offy, 0, window.innerHeight - 20);
  drag.el.style.left = x + 'px'; drag.el.style.top = y + 'px';
  drag.el.style.right = 'auto'; drag.el.style.bottom = 'auto'; drag.el.style.transformOrigin = 'top left';
  if (!settings.positions) settings.positions = {};
  settings.positions[drag.key] = { x, y };
});
document.addEventListener('mouseup', () => { drag = null; });

function enterLayout() {
  editing = true;
  document.body.classList.add('editing');
  byId('settings').classList.add('layout');
  byId('layout-bar').classList.remove('hidden');
  byId('money').classList.toggle('hidden', !settings.elements.money);
  byId('compass').classList.toggle('hidden', !settings.elements.compass);
  byId('minimap').classList.remove('hidden');   // always grabbable while editing
  applySettings();
}
function exitLayout() {
  editing = false;
  document.body.classList.remove('editing');
  byId('settings').classList.remove('layout');
  byId('layout-bar').classList.add('hidden');
  applySettings();
}

// ── Settings panel ──
function buildPanel() {
  const tg = byId('toggles'); tg.innerHTML = '';
  Object.keys(settings.elements).forEach(key => {
    const b = document.createElement('div');
    b.className = 'toggle' + (settings.elements[key] ? ' on' : '');
    b.innerHTML = `<span class="box"></span><span>${t('el.' + key)}</span>`;
    b.onclick = () => { settings.elements[key] = !settings.elements[key]; b.classList.toggle('on'); applySettings(); };
    tg.appendChild(b);
  });

  const sw = byId('swatches'); sw.innerHTML = '';
  ACCENTS.forEach(a => {
    const s = document.createElement('div');
    s.className = 'swatch' + (a.c.toLowerCase() === (settings.accent || '').toLowerCase() ? ' sel' : '');
    s.style.background = a.c;
    s.onclick = () => { settings.accent = a.c; byId('accent-custom').value = a.c; [...sw.children].forEach(c => c.classList.remove('sel')); s.classList.add('sel'); applySettings(); };
    sw.appendChild(s);
  });
  byId('accent-custom').value = settings.accent || '#FF6A1A';
  byId('accent-custom').oninput = (e) => { settings.accent = e.target.value; [...sw.children].forEach(c => c.classList.remove('sel')); applySettings(); };

  const op = byId('opacity'), sc = byId('scale');
  op.value = settings.opacity; byId('opacity-val').textContent = settings.opacity + '%';
  sc.value = settings.scale; byId('scale-val').textContent = settings.scale + '%';
  op.oninput = () => { settings.opacity = +op.value; byId('opacity-val').textContent = op.value + '%'; applySettings(); };
  sc.oninput = () => { settings.scale = +sc.value; byId('scale-val').textContent = sc.value + '%'; applySettings(); };

  byId('dynamic').classList.toggle('on', settings.dynamic);
  byId('mapvehicle').classList.toggle('on', settings.minimapVehicleOnly);
}

function openSettings() { buildPanel(); byId('settings').classList.remove('hidden'); }
function closeSettings() { if (editing) exitLayout(); byId('settings').classList.add('hidden'); post('closeSettings'); }

byId('btn-close').onclick = closeSettings;
byId('btn-move').onclick = enterLayout;
byId('btn-layout-done').onclick = exitLayout;
byId('dynamic').onclick = () => { settings.dynamic = !settings.dynamic; byId('dynamic').classList.toggle('on'); applySettings(); };
byId('mapvehicle').onclick = () => { settings.minimapVehicleOnly = !settings.minimapVehicleOnly; byId('mapvehicle').classList.toggle('on'); };
byId('btn-reset').onclick = () => { settings = JSON.parse(JSON.stringify(DEFAULTS)); buildPanel(); applySettings(); };
byId('btn-save').onclick = () => { if (editing) exitLayout(); post('saveSettings', settings); byId('settings').classList.add('hidden'); post('closeSettings'); };
byId('settings').addEventListener('mousedown', (e) => { if (e.target.id === 'settings' && !editing) closeSettings(); });
document.addEventListener('keydown', (e) => {
  if (e.key !== 'Escape') return;
  if (editing) exitLayout();
  else if (!byId('settings').classList.contains('hidden')) closeSettings();
});

// ── Messages from Lua ──
window.addEventListener('message', (event) => {
  const d = event.data || {};
  switch (d.action) {
    case 'init':
      if (d.settings) {
        settings = Object.assign(JSON.parse(JSON.stringify(DEFAULTS)), d.settings);
        settings.elements = Object.assign({}, DEFAULTS.elements, d.settings.elements || {});
        settings.positions = d.settings.positions || {};
      }
      applySettings();
      break;
    case 'minimapFrame':
      if (typeof d.w === 'number') mmFrame.w = d.w;
      if (typeof d.h === 'number') mmFrame.h = d.h;
      if (d.default) mmFrame.def = d.default;
      applyMinimapFrame();
      break;
    case 'strings': strings = d.strings || {}; applyStrings(); break;
    case 'vitals': renderVitals(d.data || {}); break;
    case 'heading': renderCompass(d.h); break;
    case 'money': setMoney(d.cash, d.bank, d.flash); break;
    case 'openSettings': openSettings(); break;
    case 'closeSettings': if (editing) exitLayout(); byId('settings').classList.add('hidden'); break;
  }
});

buildRings();
buildCompassTape();
applySettings();
