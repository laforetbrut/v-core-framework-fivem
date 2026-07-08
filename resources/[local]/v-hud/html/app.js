// v-hud — vitals rings + money + player-customizable settings
const RES = 'v-hud';
const CIRC = 113.1;                 // 2*pi*18
const byId = (id) => document.getElementById(id);
const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
const fmt = (n) => '$' + Math.floor(Number(n) || 0).toLocaleString('en-US');

const ICON = {
  health: '<path d="M20.8 5.6a5 5 0 0 0-7.1 0L12 7.3l-1.7-1.7a5 5 0 1 0-7.1 7.1L12 21l8.8-8.3a5 5 0 0 0 0-7.1Z"/>',
  armor:  '<path d="M12 3 5 6v6c0 4 3 6.5 7 9 4-2.5 7-5 7-9V6l-7-3Z"/>',
  hunger: '<path d="M7 3v7a2 2 0 0 0 4 0V3M9 10v11"/><path d="M17 3c-1.5 0-3 1.5-3 4.5S15.5 12 17 12v9"/>',
  thirst: '<path d="M12 3s6 6.4 6 10a6 6 0 0 1-12 0c0-3.6 6-10 6-10Z"/>',
  stress: '<path d="M13 2 4 14h6l-1 8 9-12h-6l1-8Z"/>',
  stamina:'<path d="M3 9h11a3 3 0 1 0-3-3M3 15h13a3 3 0 1 1-3 3"/>',
  oxygen: '<circle cx="11" cy="13" r="6"/><circle cx="18" cy="7" r="2.2"/>',
};

// key, danger(value)->bool, plus display rules
const VITALS = [
  { key: 'health',  danger: v => v <= 20 },
  { key: 'armor',   danger: () => false, hideZero: true },
  { key: 'hunger',  danger: v => v <= 15 },
  { key: 'thirst',  danger: v => v <= 15 },
  { key: 'stress',  danger: v => v >= 70, fullWhenZero: true },
  { key: 'stamina', danger: v => v <= 15 },
  { key: 'oxygen',  danger: v => v <= 30, underwaterOnly: true },
];

const LABELS = { health:'Health', armor:'Armor', hunger:'Hunger', thirst:'Thirst', stress:'Stress', stamina:'Stamina', oxygen:'Oxygen', money:'Money' };
const ACCENTS = [
  { c: '#FF6A1A', c2: '#FF9354' }, // orange (default)
  { c: '#43C46A', c2: '#6FE08D' }, // green
  { c: '#4AA8FF', c2: '#7FC1FF' }, // blue
  { c: '#E5484D', c2: '#FF6E72' }, // red
  { c: '#F5A623', c2: '#FFC65C' }, // gold
];

const DEFAULTS = {
  elements: { health:true, armor:true, hunger:true, thirst:true, stress:true, stamina:true, oxygen:true, money:true },
  accent: '#FF6A1A', opacity: 100, scale: 100, dynamic: true,
};
let settings = JSON.parse(JSON.stringify(DEFAULTS));
let lastMoney = { cash: 0, bank: 0 };

// ── Build rings ──
const rings = {};
function buildRings() {
  const wrap = byId('vitals');
  wrap.innerHTML = '';
  for (const v of VITALS) {
    const el = document.createElement('div');
    el.className = 'ring';
    el.innerHTML =
      `<svg viewBox="0 0 44 44"><circle class="track" cx="22" cy="22" r="18"/><circle class="fill" cx="22" cy="22" r="18"/></svg>` +
      `<span class="ic"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round">${ICON[v.key]}</svg></span>`;
    wrap.appendChild(el);
    rings[v.key] = { el, fill: el.querySelector('.fill') };
  }
}

function renderVitals(data) {
  for (const v of VITALS) {
    const r = rings[v.key];
    if (!r) continue;
    const on = settings.elements[v.key];
    const val = clamp(Math.round(data[v.key] || 0), 0, 100);
    const underwaterHide = v.underwaterOnly && !data.underwater;
    const zeroHide = v.hideZero && val <= 0;
    if (!on || underwaterHide || zeroHide) { r.el.classList.add('hidden'); continue; }
    r.el.classList.remove('hidden');
    r.fill.style.strokeDashoffset = CIRC * (1 - val / 100);
    const dngr = v.danger(val);
    r.el.classList.toggle('low', dngr);
    const full = v.fullWhenZero ? val <= 2 : val >= 99;
    r.el.classList.toggle('faded', settings.dynamic && full && !dngr);
  }
}

// ── Money ──
function setMoney(cash, bank, flash) {
  const set = (id, value, delta) => {
    const el = byId(id);
    el.textContent = fmt(value);
    if (flash && delta) { el.classList.remove('flash-up','flash-down'); void el.offsetWidth; el.classList.add(delta > 0 ? 'flash-up' : 'flash-down'); }
  };
  set('cash', cash, cash - lastMoney.cash);
  set('bank', bank, bank - lastMoney.bank);
  lastMoney = { cash, bank };
  byId('money').classList.toggle('hidden', !settings.elements.money);
}

// ── Apply settings (live) ──
function applySettings() {
  const root = document.documentElement.style;
  root.setProperty('--hud-opacity', settings.opacity / 100);
  root.setProperty('--hud-scale', settings.scale / 100);
  const a = ACCENTS.find(x => x.c === settings.accent) || ACCENTS[0];
  root.setProperty('--v-accent', a.c);
  root.setProperty('--v-accent-300', a.c2);
  byId('money').classList.toggle('hidden', !settings.elements.money);
}

// ── Settings panel UI ──
function buildPanel() {
  // toggles
  const tg = byId('toggles'); tg.innerHTML = '';
  Object.keys(settings.elements).forEach(key => {
    const b = document.createElement('div');
    b.className = 'toggle' + (settings.elements[key] ? ' on' : '');
    b.innerHTML = `<span class="box"></span><span>${LABELS[key] || key}</span>`;
    b.onclick = () => { settings.elements[key] = !settings.elements[key]; b.classList.toggle('on'); applySettings(); };
    tg.appendChild(b);
  });
  // swatches
  const sw = byId('swatches'); sw.innerHTML = '';
  ACCENTS.forEach(a => {
    const s = document.createElement('div');
    s.className = 'swatch' + (a.c === settings.accent ? ' sel' : '');
    s.style.background = a.c;
    s.onclick = () => { settings.accent = a.c; [...sw.children].forEach(c => c.classList.remove('sel')); s.classList.add('sel'); applySettings(); };
    sw.appendChild(s);
  });
  // sliders
  const op = byId('opacity'), sc = byId('scale');
  op.value = settings.opacity; byId('opacity-val').textContent = settings.opacity + '%';
  sc.value = settings.scale; byId('scale-val').textContent = settings.scale + '%';
  op.oninput = () => { settings.opacity = +op.value; byId('opacity-val').textContent = op.value + '%'; applySettings(); };
  sc.oninput = () => { settings.scale = +sc.value; byId('scale-val').textContent = sc.value + '%'; applySettings(); };
  // dynamic switch
  byId('dynamic').classList.toggle('on', settings.dynamic);
}

function openSettings() { buildPanel(); byId('settings').classList.remove('hidden'); }
function closeSettings() { byId('settings').classList.add('hidden'); post('closeSettings'); }
function post(name, data) {
  fetch(`https://${RES}/${name}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data || {}) }).catch(() => {});
}

// panel buttons
byId('btn-close').onclick = closeSettings;
byId('dynamic').onclick = () => { settings.dynamic = !settings.dynamic; byId('dynamic').classList.toggle('on'); applySettings(); };
byId('btn-reset').onclick = () => { settings = JSON.parse(JSON.stringify(DEFAULTS)); buildPanel(); applySettings(); };
byId('btn-save').onclick = () => { post('saveSettings', settings); closeSettings(); };
byId('settings').addEventListener('mousedown', (e) => { if (e.target.id === 'settings') closeSettings(); });
document.addEventListener('keydown', (e) => { if (e.key === 'Escape' && !byId('settings').classList.contains('hidden')) closeSettings(); });

// ── Messages from Lua ──
window.addEventListener('message', (event) => {
  const d = event.data || {};
  switch (d.action) {
    case 'init':
      if (d.settings) settings = Object.assign(JSON.parse(JSON.stringify(DEFAULTS)), d.settings);
      applySettings();
      break;
    case 'vitals':
      renderVitals(d.data || {});
      break;
    case 'money':
      setMoney(d.cash, d.bank, d.flash);
      break;
    case 'openSettings':
      openSettings();
      break;
    case 'closeSettings':
      byId('settings').classList.add('hidden');
      break;
  }
});

buildRings();
applySettings();
