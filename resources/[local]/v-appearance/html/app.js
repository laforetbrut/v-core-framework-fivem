// v-appearance — barber / surgery / tattoo editor
const byId = (id) => document.getElementById(id);
const post = (n, b) => fetch(`https://v-appearance/${n}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(b || {}) }).then(r => r.json()).catch(() => false);
const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

let strings = {}, data = null;
const t = (k) => strings[k] || k;
const applyStrings = () => document.querySelectorAll('[data-i18n]').forEach(el => { el.textContent = t(el.getAttribute('data-i18n')); });

// ── control primitives ──
function stepper(label, value, count, onChange) {
  const row = document.createElement('div'); row.className = 'ctrl';
  row.innerHTML = `<div class="top"><span class="v-label">${esc(label)}</span><span class="val">${value}</span></div>
    <div class="stepper"><button class="step dec" aria-label="Previous">−</button><div class="bar"><i style="width:${count > 1 ? (value / (count - 1) * 100) : 0}%"></i></div><button class="step inc" aria-label="Next">+</button></div>`;
  const val = row.querySelector('.val'), fill = row.querySelector('.bar i');
  let v = value;
  const set = (nv) => { v = (nv + count) % count; val.textContent = v; fill.style.width = (count > 1 ? v / (count - 1) * 100 : 0) + '%'; onChange(v); };
  row.querySelector('.dec').onclick = () => set(v - 1);
  row.querySelector('.inc').onclick = () => set(v + 1);
  return row;
}
function slider(label, value, min, max, step, onChange) {
  const row = document.createElement('div'); row.className = 'ctrl';
  row.innerHTML = `<div class="top"><span class="v-label">${esc(label)}</span><span class="val">${(+value).toFixed(2)}</span></div>
    <input type="range" min="${min}" max="${max}" step="${step}" value="${value}" aria-label="${esc(label)}" />`;
  const val = row.querySelector('.val'), inp = row.querySelector('input');
  inp.oninput = () => { val.textContent = (+inp.value).toFixed(2); onChange(+inp.value); };
  return row;
}
function swatches(label, count, selected, onPick) {
  const row = document.createElement('div'); row.className = 'ctrl';
  const grid = document.createElement('div'); grid.className = 'sw-grid';
  for (let i = 0; i < count; i++) {
    const s = document.createElement('button'); s.className = 'sw' + (i === selected ? ' on' : ''); s.dataset.i = i;
    s.style.setProperty('--h', (i / Math.max(1, count)) * 360);
    s.setAttribute('aria-label', label + ' ' + i);
    s.onclick = () => { grid.querySelectorAll('.sw').forEach(x => x.classList.remove('on')); s.classList.add('on'); onPick(i); };
    grid.appendChild(s);
  }
  row.innerHTML = `<span class="v-label">${esc(label)}</span>`;
  row.appendChild(grid);
  return row;
}
function group(titleKey) {
  const g = document.createElement('div'); g.className = 'grp';
  if (titleKey) { const h = document.createElement('div'); h.className = 'grp-h'; h.textContent = t(titleKey); g.appendChild(h); }
  return g;
}

// ── modes ──
function buildBarber() {
  const body = byId('body'); body.innerHTML = '';
  const a = data.appearance;
  const hair = a.hair || { style: 0, color: 0, highlight: 0 };
  const g = group('app.hair');
  g.appendChild(stepper(t('app.hair_style'), hair.style || 0, data.hairCount || 1, (v) => { hair.style = v; post('appSetHair', { style: v }); }));
  g.appendChild(swatches(t('app.hair_color'), data.hairColors || 1, hair.color || 0, (v) => post('appSetHair', { color: v })));
  g.appendChild(swatches(t('app.hair_highlight'), data.hairColors || 1, hair.highlight || 0, (v) => post('appSetHair', { highlight: v })));
  body.appendChild(g);

  (data.overlays || []).forEach(ov => {
    const cur = (a.overlays || {})[ov.key] || { style: 0, opacity: 1.0, color: 0 };
    const grp = group('app.ov.' + ov.key);
    grp.appendChild(stepper(t('app.style'), cur.style || 0, (ov.count || 0) + 1, (v) => post('appSetOverlay', { key: ov.key, style: v })));
    grp.appendChild(slider(t('app.opacity'), cur.opacity != null ? cur.opacity : 1.0, 0, 1, 0.05, (v) => post('appSetOverlay', { key: ov.key, opacity: v })));
    if (ov.colorType) {
      const cc = ov.colorType === 2 ? (data.makeupColors || 1) : (data.hairColors || 1);
      grp.appendChild(swatches(t('app.color'), cc, cur.color || 0, (v) => post('appSetOverlay', { key: ov.key, color: v })));
    }
    body.appendChild(grp);
  });
}

function buildSurgery() {
  const body = byId('body'); body.innerHTML = '';
  const a = data.appearance;
  const hb = a.headBlend || {};
  const g = group('app.headblend');
  g.appendChild(slider(t('app.shape_mix'), hb.shapeMix != null ? hb.shapeMix : 0.5, 0, 1, 0.05, (v) => post('appSetBlend', { shapeMix: v })));
  g.appendChild(slider(t('app.skin_mix'), hb.skinMix != null ? hb.skinMix : 0.5, 0, 1, 0.05, (v) => post('appSetBlend', { skinMix: v })));
  body.appendChild(g);

  const gf = group(null);
  (data.features || []).forEach(f => {
    const cur = (a.faceFeatures || {})[String(f.id)] || 0;
    gf.appendChild(slider(t(f.i18n), cur, -1, 1, 0.05, (v) => post('appSetFace', { id: f.id, value: v })));
  });
  body.appendChild(gf);
}

const ZONE_KEYS = { ZONE_HEAD: 'app.zone_head', ZONE_TORSO: 'app.zone_torso', ZONE_LEFT_ARM: 'app.zone_left_arm', ZONE_RIGHT_ARM: 'app.zone_right_arm', ZONE_LEFT_LEG: 'app.zone_left_leg', ZONE_RIGHT_LEG: 'app.zone_right_leg', ZONE_HAIR: 'app.zone_hair' };
let tatZone = 'ZONE_TORSO';
function isApplied(tt) { return (data.applied || []).some(x => x.c === tt.c && x.h === tt.h); }
function buildTattoo() {
  const body = byId('body'); body.innerHTML = '';
  const zones = data.zones || {};
  // zone tabs
  const tabs = document.createElement('div'); tabs.className = 'tzones';
  Object.keys(ZONE_KEYS).filter(z => zones[z] && zones[z].length).forEach(z => {
    const b = document.createElement('button'); b.className = 'tz' + (z === tatZone ? ' on' : ''); b.textContent = t(ZONE_KEYS[z]);
    b.onclick = () => { tatZone = z; buildTattoo(); };
    tabs.appendChild(b);
  });
  body.appendChild(tabs);

  const clear = document.createElement('button'); clear.className = 'v-btn v-btn--danger clear-all'; clear.textContent = t('app.clear_all');
  clear.onclick = () => { data.applied = []; post('appClearTattoos'); buildTattoo(); };
  body.appendChild(clear);

  const list = document.createElement('div'); list.className = 'tlist';
  (zones[tatZone] || []).forEach(tt => {
    const row = document.createElement('button'); row.className = 'trow' + (isApplied(tt) ? ' on' : '');
    row.innerHTML = `<span class="tn">${esc(tt.label || tt.name)}</span><span class="tk">${isApplied(tt) ? '✕' : '+'}</span>`;
    row.onclick = () => {
      if (isApplied(tt)) { data.applied = data.applied.filter(x => !(x.c === tt.c && x.h === tt.h)); post('appRemoveTattoo', { c: tt.c, h: tt.h }); }
      else { (data.applied = data.applied || []).push({ c: tt.c, h: tt.h }); post('appAddTattoo', { c: tt.c, h: tt.h }); }
      row.classList.toggle('on'); row.querySelector('.tk').textContent = isApplied(tt) ? '✕' : '+';
    };
    list.appendChild(row);
  });
  body.appendChild(list);
}

function buildMode() {
  const titles = { barber: 'app.barber', surgery: 'app.surgery', tattoo: 'app.tattoo' };
  byId('dock-title').textContent = t(titles[data.mode] || 'app.barber');
  if (data.mode === 'barber') buildBarber();
  else if (data.mode === 'surgery') buildSurgery();
  else buildTattoo();
}

// ── camera: drag the stage to orbit; zone buttons ──
let dragging = false, lastX = 0;
byId('stage').addEventListener('mousedown', (e) => { dragging = true; lastX = e.clientX; });
document.addEventListener('mouseup', () => { dragging = false; });
document.addEventListener('mousemove', (e) => { if (!dragging) return; const dx = e.clientX - lastX; lastX = e.clientX; if (dx) post('appCam', { orbit: dx }); });
byId('zones').addEventListener('click', (e) => {
  const b = e.target.closest('.zbtn'); if (!b) return;
  byId('zones').querySelectorAll('.zbtn').forEach(x => x.classList.remove('on')); b.classList.add('on');
  post('appCam', { zone: b.dataset.zone });
});

byId('confirm').onclick = () => post('appConfirm');
byId('cancel').onclick = () => post('appClose');
document.addEventListener('keydown', (e) => { if (e.key === 'Escape' && !byId('app').classList.contains('hidden')) post('appClose'); });

// ── messages from Lua ──
window.addEventListener('message', (e) => {
  const d = e.data || {};
  if (d.action === 'open') {
    data = d.data || {}; strings = data.strings || {};
    byId('app').classList.remove('hidden');
    applyStrings(); buildMode();
  } else if (d.action === 'close') {
    byId('app').classList.add('hidden');
  }
});
