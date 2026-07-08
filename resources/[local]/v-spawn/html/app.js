// v-spawn — character creator UI
const RES = 'v-spawn';
const byId = (id) => document.getElementById(id);
const post = (name, data) => fetch(`https://${RES}/${name}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data || {}) }).catch(() => {});
const getPath = (o, p) => p.split('.').reduce((a, k) => (a == null ? undefined : a[k]), o);
const setPath = (o, p, v) => { const ks = p.split('.'); let a = o; for (let i = 0; i < ks.length - 1; i++) { if (a[ks[i]] == null) a[ks[i]] = {}; a = a[ks[i]]; } a[ks[ks.length - 1]] = v; };

let strings = {};
let appearance = null;
let currentTab = 'heritage';

const SCHEMA = {
  heritage: [
    { i18n: 'app.mother', path: 'headBlend.shapeFirst', type: 'step', min: 0, max: 45 },
    { i18n: 'app.father', path: 'headBlend.shapeSecond', type: 'step', min: 0, max: 45 },
    { i18n: 'app.resemblance', path: 'headBlend.shapeMix', type: 'slider', min: 0, max: 1, step: 0.05 },
    { i18n: 'app.skin', path: 'headBlend.skinMix', type: 'slider', min: 0, max: 1, step: 0.05 },
  ],
  face: [
    { i18n: 'face.nose', path: 'faceFeatures.0', type: 'slider', min: -1, max: 1, step: 0.1 },
    { i18n: 'face.eyes', path: 'faceFeatures.11', type: 'slider', min: -1, max: 1, step: 0.1 },
    { i18n: 'face.cheeks', path: 'faceFeatures.8', type: 'slider', min: -1, max: 1, step: 0.1 },
    { i18n: 'face.jaw', path: 'faceFeatures.13', type: 'slider', min: -1, max: 1, step: 0.1 },
    { i18n: 'face.chin', path: 'faceFeatures.15', type: 'slider', min: -1, max: 1, step: 0.1 },
    { i18n: 'face.lips', path: 'faceFeatures.12', type: 'slider', min: -1, max: 1, step: 0.1 },
  ],
  hair: [
    { i18n: 'app.hairstyle', path: 'hair.style', type: 'step', min: 0, max: 73 },
    { i18n: 'app.haircolor', path: 'hair.color', type: 'step', min: 0, max: 63 },
    { i18n: 'app.eyebrows', path: 'overlays.eyebrows.style', type: 'step', min: 0, max: 33 },
    { i18n: 'app.beard', path: 'overlays.beard.style', type: 'step', min: 0, max: 28 },
  ],
  details: [
    { i18n: 'app.eyecolor', path: 'eyeColor', type: 'step', min: 0, max: 31 },
  ],
  clothing: [
    { i18n: 'app.tops', path: 'components.11.drawable', type: 'step', min: 0, max: 300 },
    { i18n: 'app.undershirt', path: 'components.8.drawable', type: 'step', min: 0, max: 200 },
    { i18n: 'app.arms', path: 'components.3.drawable', type: 'step', min: 0, max: 200 },
    { i18n: 'app.pants', path: 'components.4.drawable', type: 'step', min: 0, max: 200 },
    { i18n: 'app.shoes', path: 'components.6.drawable', type: 'step', min: 0, max: 100 },
  ],
};
const TABS = [
  { key: 'heritage', i18n: 'app.tab.heritage' }, { key: 'face', i18n: 'app.tab.face' },
  { key: 'hair', i18n: 'app.tab.hair' }, { key: 'details', i18n: 'app.tab.details' },
  { key: 'clothing', i18n: 'app.tab.clothing' },
];

const t = (key) => strings[key] || key;

function applyStrings() {
  document.querySelectorAll('[data-i18n]').forEach(el => { el.textContent = t(el.getAttribute('data-i18n')); });
}

function showScreen(screen) {
  byId('screen-identity').classList.toggle('hidden', screen !== 'identity');
  byId('screen-appearance').classList.toggle('hidden', screen !== 'appearance');
  byId('panel-title').setAttribute('data-i18n', screen === 'appearance' ? 'app.title' : 'id.title');
  byId('panel-title').textContent = t(screen === 'appearance' ? 'app.title' : 'id.title');
  byId('cam').classList.remove('hidden');
  if (screen === 'appearance') buildAppearance();
}

// ── debounced ped update ──
let upTimer = null;
function pushUpdate() {
  clearTimeout(upTimer);
  upTimer = setTimeout(() => post('updateAppearance', { appearance }), 45);
}

// ── appearance UI ──
function buildAppearance() {
  const tabsEl = byId('tabs'); tabsEl.innerHTML = '';
  TABS.forEach(tab => {
    const b = document.createElement('button');
    b.className = 'tab' + (tab.key === currentTab ? ' on' : '');
    b.textContent = t(tab.i18n);
    b.onclick = () => { currentTab = tab.key; buildAppearance(); };
    tabsEl.appendChild(b);
  });
  buildControls();
}

function buildControls() {
  const wrap = byId('controls'); wrap.innerHTML = '';
  (SCHEMA[currentTab] || []).forEach(c => {
    let val = getPath(appearance, c.path);
    if (val === undefined || val === null) val = (c.type === 'slider') ? (c.min < 0 ? 0 : c.min) : c.min;

    const row = document.createElement('div');
    row.className = 'ctrl';
    const disp = c.type === 'slider' ? Math.round(val * 100) : Math.round(val);
    row.innerHTML = `<div class="top"><span class="v-label">${t(c.i18n)}</span><span class="val" data-val>${disp}</span></div>`;

    if (c.type === 'slider') {
      const s = document.createElement('input');
      s.type = 'range'; s.min = c.min; s.max = c.max; s.step = c.step || 0.1; s.value = val;
      s.oninput = () => { const v = parseFloat(s.value); setPath(appearance, c.path, v); row.querySelector('[data-val]').textContent = Math.round(v * 100); pushUpdate(); };
      row.appendChild(s);
    } else {
      const st = document.createElement('div'); st.className = 'stepper';
      const dec = document.createElement('button'); dec.className = 'step-btn'; dec.textContent = '−';
      const bar = document.createElement('div'); bar.className = 'bar'; bar.innerHTML = '<i></i>';
      const inc = document.createElement('button'); inc.className = 'step-btn'; inc.textContent = '+';
      const fill = () => { bar.querySelector('i').style.width = ((getPath(appearance, c.path) - c.min) / (c.max - c.min) * 100) + '%'; };
      const change = (d) => {
        let v = Math.round(getPath(appearance, c.path) || c.min) + d;
        if (v < c.min) v = c.max; if (v > c.max) v = c.min;   // wrap
        setPath(appearance, c.path, v);
        row.querySelector('[data-val]').textContent = v; fill(); pushUpdate();
      };
      dec.onclick = () => change(-1); inc.onclick = () => change(1);
      st.append(dec, bar, inc); row.appendChild(st); setTimeout(fill, 0);
    }
    wrap.appendChild(row);
  });
}

// ── Language ──
document.querySelectorAll('.lang-btn').forEach(b => b.onclick = () => {
  post('selectLang', { lang: b.getAttribute('data-lang') });
  byId('screen-language').classList.add('hidden');
  byId('panel').classList.remove('hidden');
});

// ── Identity ──
document.querySelectorAll('.seg-btn').forEach(b => b.onclick = () => {
  document.querySelectorAll('.seg-btn').forEach(x => x.classList.remove('on'));
  b.classList.add('on');
  post('setSex', { sex: parseInt(b.getAttribute('data-sex'), 10) });
});
byId('btn-next').onclick = () => {
  const fn = byId('firstname').value.trim(), ln = byId('lastname').value.trim();
  if (!fn || !ln) { byId('id-err').textContent = t('err.name'); return; }
  byId('id-err').textContent = '';
  post('identityNext', { firstname: fn, lastname: ln, dob: byId('dob').value });
};

// ── Appearance buttons ──
byId('btn-back').onclick = () => showScreen('identity');
byId('btn-confirm').onclick = () => post('confirm', { appearance });

// ── Camera ──
document.querySelectorAll('.cam-btn').forEach(b => b.onclick = () => post('camera', { rotate: parseFloat(b.getAttribute('data-rot')) }));
document.querySelectorAll('.cam-zone').forEach(b => b.onclick = () => {
  document.querySelectorAll('.cam-zone').forEach(x => x.classList.remove('on'));
  b.classList.add('on'); post('camera', { zone: b.getAttribute('data-zone') });
});

// ── Messages from Lua ──
window.addEventListener('message', (e) => {
  const d = e.data || {};
  switch (d.action) {
    case 'open':
      byId('screen-language').classList.remove('hidden');
      byId('panel').classList.add('hidden');
      byId('cam').classList.add('hidden');
      break;
    case 'strings':
      strings = d.strings || {}; applyStrings(); break;
    case 'appearance':
      appearance = d.data; if (!byId('screen-appearance').classList.contains('hidden')) buildControls(); break;
    case 'screen':
      if (d.appearance) appearance = d.appearance;
      showScreen(d.screen); break;
    case 'close':
      byId('screen-language').classList.add('hidden');
      byId('panel').classList.add('hidden');
      byId('cam').classList.add('hidden');
      break;
  }
});
