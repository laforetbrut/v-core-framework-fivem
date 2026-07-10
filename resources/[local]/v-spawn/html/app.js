// v-spawn — character creator UI
const RES = 'v-spawn';
const byId = (id) => document.getElementById(id);
const post = (name, data) => fetch(`https://${RES}/${name}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data || {}) }).catch(() => {});
const getPath = (o, p) => p.split('.').reduce((a, k) => (a == null ? undefined : a[k]), o);
const setPath = (o, p, v) => { const ks = p.split('.'); let a = o; for (let i = 0; i < ks.length - 1; i++) { if (a[ks[i]] == null) a[ks[i]] = {}; a = a[ks[i]]; } a[ks[ks.length - 1]] = v; };

let strings = {};
let appearance = null;
let currentTab = 'heritage';

// ── Approximate GTA palettes (swatch = index applied to the ped) ──
const HAIR = (() => {
  const nat = ['#141013', '#241a17', '#33241d', '#432f24', '#54392a', '#654433', '#77543d', '#8a6748', '#a07c56', '#b89468', '#cdae7f', '#ddc596', '#ebd8b0', '#f3e6cd'];
  const red = ['#7a3b26', '#8f4126', '#a24a29', '#b8542c', '#c85f34', '#d76f45', '#8a3020', '#5e2417'];
  const grey = ['#8f8b86', '#a7a29c', '#c2beb8', '#d8d5d0', '#eceae6', '#6f6b66', '#54514c'];
  const dyed = ['#3a5fb0', '#2f8f6f', '#8a3f9e', '#c0407a', '#c85a2b', '#c9a12b', '#2b8fc9', '#c92b6a', '#6a2bc9', '#2bc98f', '#c9c92b', '#c92b2b', '#2b2bc9', '#9e9e9e', '#5c5c5c', '#e0e0e0', '#b0602a', '#7a4a2a', '#4a2a1a', '#2a1a10', '#d0b070', '#a08040', '#806030', '#604020', '#402810', '#e8d8b8', '#c8b898', '#a89878', '#887858', '#685838', '#483818', '#282800', '#0a0a0a', '#1a1a1a', '#2a2a2a'];
  return [...nat, ...red, ...grey, ...dyed].slice(0, 64);
})();
const EYES = ['#5b3a1e', '#6b4a2a', '#3f2a17', '#8a6a3a', '#2a6a8a', '#3a7a9a', '#4a8aaa', '#2a8a5a', '#3a9a6a', '#6a6a6a', '#8a8a8a', '#9a7a3a', '#7a3a3a', '#5a5a7a', '#3a3a5a', '#aaaaaa', '#c0c0c0', '#2a2a2a', '#5a3a1a', '#7a5a2a', '#4a6a4a', '#6a4a6a', '#2a4a2a', '#4a2a4a'];

const SCHEMA = {
  heritage: [
    { i18n: 'app.mother', path: 'headBlend.shapeFirst', type: 'step', min: 0, max: 45 },
    { i18n: 'app.father', path: 'headBlend.shapeSecond', type: 'step', min: 0, max: 45 },
    { i18n: 'app.resemblance', path: 'headBlend.shapeMix', type: 'slider', min: 0, max: 1, step: 0.05 },
    { i18n: 'app.skin', path: 'headBlend.skinMix', type: 'slider', min: 0, max: 1, step: 0.05 },
  ],
  face: [
    { i18n: 'face.nose', path: 'faceFeatures.0', type: 'slider', min: -1, max: 1, step: 0.1 },
    { i18n: 'face.nose_h', path: 'faceFeatures.1', type: 'slider', min: -1, max: 1, step: 0.1 },
    { i18n: 'face.brow', path: 'faceFeatures.6', type: 'slider', min: -1, max: 1, step: 0.1 },
    { i18n: 'face.eyes', path: 'faceFeatures.11', type: 'slider', min: -1, max: 1, step: 0.1 },
    { i18n: 'face.cheeks', path: 'faceFeatures.8', type: 'slider', min: -1, max: 1, step: 0.1 },
    { i18n: 'face.cheekbone', path: 'faceFeatures.10', type: 'slider', min: -1, max: 1, step: 0.1 },
    { i18n: 'face.jaw', path: 'faceFeatures.13', type: 'slider', min: -1, max: 1, step: 0.1 },
    { i18n: 'face.chin', path: 'faceFeatures.15', type: 'slider', min: -1, max: 1, step: 0.1 },
    { i18n: 'face.chin_len', path: 'faceFeatures.16', type: 'slider', min: -1, max: 1, step: 0.1 },
    { i18n: 'face.lips', path: 'faceFeatures.12', type: 'slider', min: -1, max: 1, step: 0.1 },
  ],
  hair: [
    { i18n: 'app.hairstyle', path: 'hair.style', type: 'step', min: 0, max: 73 },
    { i18n: 'app.haircolor', path: 'hair.color', type: 'color', palette: HAIR },
    { i18n: 'app.highlight', path: 'hair.highlight', type: 'color', palette: HAIR },
    { i18n: 'app.eyebrows', path: 'overlays.eyebrows.style', type: 'step', min: 0, max: 33 },
    { i18n: 'app.eyebrowcolor', path: 'overlays.eyebrows.color', type: 'color', palette: HAIR },
    { i18n: 'app.beard', path: 'overlays.beard.style', type: 'step', min: 0, max: 28 },
    { i18n: 'app.beardcolor', path: 'overlays.beard.color', type: 'color', palette: HAIR },
  ],
  details: [
    { i18n: 'app.eyecolor', path: 'eyeColor', type: 'color', palette: EYES },
    { i18n: 'app.makeup', path: 'overlays.makeup.style', type: 'step', min: 0, max: 74 },
    { i18n: 'app.blush', path: 'overlays.blush.style', type: 'step', min: 0, max: 6 },
    { i18n: 'app.lipstick', path: 'overlays.lipstick.style', type: 'step', min: 0, max: 9 },
  ],
  clothing: [
    { i18n: 'app.mask', path: 'components.1.drawable', type: 'step', min: 0, max: 200, cat: 'masks' },
    { i18n: 'app.tops', path: 'components.11.drawable', type: 'step', min: 0, max: 350, cat: 'tops' },
    { i18n: 'app.tops', suffix: 'app.texture', path: 'components.11.texture', type: 'step', min: 0, max: 15 },
    { i18n: 'app.undershirt', path: 'components.8.drawable', type: 'step', min: 0, max: 200, cat: 'undershirt' },
    { i18n: 'app.arms', path: 'components.3.drawable', type: 'step', min: 0, max: 200, cat: 'arms' },
    { i18n: 'app.pants', path: 'components.4.drawable', type: 'step', min: 0, max: 200, cat: 'pants' },
    { i18n: 'app.pants', suffix: 'app.texture', path: 'components.4.texture', type: 'step', min: 0, max: 15 },
    { i18n: 'app.shoes', path: 'components.6.drawable', type: 'step', min: 0, max: 100, cat: 'shoes' },
  ],
  props: [
    { i18n: 'app.hat', path: 'props.0.drawable', type: 'step', min: -1, max: 130, cat: 'hats' },
    { i18n: 'app.hat', suffix: 'app.texture', path: 'props.0.texture', type: 'step', min: 0, max: 15 },
    { i18n: 'app.glasses', path: 'props.1.drawable', type: 'step', min: -1, max: 40, cat: 'glasses' },
    { i18n: 'app.glasses', suffix: 'app.texture', path: 'props.1.texture', type: 'step', min: 0, max: 15 },
  ],
};
const TABS = [
  { key: 'heritage', i18n: 'app.tab.heritage' }, { key: 'face', i18n: 'app.tab.face' },
  { key: 'hair', i18n: 'app.tab.hair' }, { key: 'details', i18n: 'app.tab.details' },
  { key: 'clothing', i18n: 'app.tab.clothing' }, { key: 'props', i18n: 'app.tab.props' },
];

const t = (key) => strings[key] || key;
const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const postJson = (name, data) => fetch(`https://${RES}/${name}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data || {}) }).then(r => r.json()).catch(() => null);
const applyStrings = () => document.querySelectorAll('[data-i18n]').forEach(el => { el.textContent = t(el.getAttribute('data-i18n')); });

// ── Character selection ──
let charData = null;
function buildCharacters(data) {
  charData = data; strings = data.strings || strings;
  const grid = byId('charcards'); grid.innerHTML = '';
  const bySlot = {}; (data.characters || []).forEach(c => { bySlot[c.slot] = c; });
  const brk = '<i class="v-brk v-brk--tr" aria-hidden="true"></i><i class="v-brk v-brk--bl" aria-hidden="true"></i>';
  for (let s = 1; s <= (data.maxSlots || 1); s++) {
    const c = bySlot[s];
    const card = document.createElement('div');
    card.className = 'char-card ' + (c ? 'filled' : 'empty'); card.style.setProperty('--i', s - 1);
    if (c) {
      card.innerHTML = brk +
        `<span class="cc-slot">${t('sel.slot')} ${s}</span>` +
        `<div class="cc-name">${esc(c.firstname)} ${esc(c.lastname)}</div>` +
        `<div class="cc-meta"><span>${t('sel.cash')} $${(c.cash || 0).toLocaleString('en-US')}</span><span>${t('sel.bank')} $${(c.bank || 0).toLocaleString('en-US')}</span></div>` +
        `<button class="v-btn v-btn--accent cc-play" data-i18n="sel.play">Play</button>` +
        (data.canDelete ? `<button class="cc-del" data-i18n="sel.delete">Delete</button>` : '');
      card.querySelector('.cc-play').onclick = () => post('selectCharacter', { citizenid: c.citizenid });
      if (data.canDelete) {
        const del = card.querySelector('.cc-del');
        del.onclick = (ev) => {
          ev.stopPropagation();
          if (del.dataset.confirm) {
            postJson('deleteCharacter', { citizenid: c.citizenid }).then(res => {
              if (res && res.characters) buildCharacters(Object.assign({}, charData, { characters: res.characters }));
            });
          } else {
            del.dataset.confirm = '1'; del.textContent = t('sel.delete_confirm');
            setTimeout(() => { if (del.isConnected) { del.dataset.confirm = ''; del.textContent = t('sel.delete'); } }, 3000);
          }
        };
      }
    } else {
      card.innerHTML = brk + `<span class="cc-slot">${t('sel.slot')} ${s}</span><div class="cc-plus" aria-hidden="true">+</div><div class="cc-new" data-i18n="sel.new">New character</div>`;
      card.onclick = () => post('createInSlot', { slot: s });
    }
    grid.appendChild(card);
  }
  applyStrings();
  ['screen-language', 'panel', 'cam', 'stage'].forEach(id => byId(id).classList.add('hidden'));
  byId('screen-select').classList.remove('hidden');
}

function showScreen(screen, extra) {
  byId('screen-select').classList.add('hidden');   // leaving the selection screen
  byId('screen-language').classList.add('hidden');
  byId('screen-identity').classList.toggle('hidden', screen !== 'identity');
  byId('screen-appearance').classList.toggle('hidden', screen !== 'appearance');
  byId('screen-spawn').classList.toggle('hidden', screen !== 'spawnselect');
  byId('panel').classList.toggle('hidden', screen === 'spawnselect');
  byId('cam').classList.toggle('hidden', screen === 'spawnselect');
  byId('stage').classList.toggle('hidden', screen === 'spawnselect');
  if (screen === 'spawnselect') { buildSpawnCards((extra && extra.spawns) || []); return; }
  byId('panel-title').textContent = t(screen === 'appearance' ? 'app.title' : 'id.title');
  if (screen === 'appearance') buildAppearance();
}

// ── First-spawn location cards ──
const SPAWN_ICONS = {
  airport: '<svg viewBox="0 0 24 24" width="30" height="30" fill="none" stroke="currentColor" stroke-width="1.7" aria-hidden="true"><path d="M10.5 20.5 12 14l-7 -2.5v-2l7 1.5V5.5a1.5 1.5 0 0 1 3 0V11l7 -1.5v2L15 14l1.5 6.5-1.5.9-3-5.4-3 5.4z"/></svg>',
  prison:  '<svg viewBox="0 0 24 24" width="30" height="30" fill="none" stroke="currentColor" stroke-width="1.7" aria-hidden="true"><rect x="4" y="4" width="16" height="16" rx="2"/><path d="M8 4v16M12 4v16M16 4v16"/></svg>',
  sandy:   '<svg viewBox="0 0 24 24" width="30" height="30" fill="none" stroke="currentColor" stroke-width="1.7" aria-hidden="true"><circle cx="17" cy="7" r="2.6"/><path d="M2 17c2-1.6 4-1.6 6 0s4 1.6 6 0 4-1.6 6 0M2 21c2-1.6 4-1.6 6 0s4 1.6 6 0 4-1.6 6 0"/></svg>',
};

function buildSpawnCards(spawns) {
  const wrap = byId('spawncards'); wrap.innerHTML = '';
  spawns.forEach((s, i) => {
    const card = document.createElement('button');
    card.className = 'spawn-card';
    card.style.setProperty('--i', i);
    card.innerHTML = `<span class="sicon">${SPAWN_ICONS[s.key] || ''}</span>
      <span class="slabel">${s.label}</span><span class="ssub">${s.sub || ''}</span>`;
    card.onclick = () => {
      if (card.dataset.done) return;
      card.dataset.done = '1';
      wrap.querySelectorAll('.spawn-card').forEach(x => x.classList.add('fade'));
      card.classList.remove('fade'); card.classList.add('picked');
      post('spawnAt', { key: s.key });
      setTimeout(() => byId('screen-spawn').classList.add('hidden'), 450);
    };
    wrap.appendChild(card);
  });
}

let upTimer = null;
function pushUpdate() { clearTimeout(upTimer); upTimer = setTimeout(() => post('updateAppearance', { appearance }), 45); }

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

function ctrlLabel(c) { return t(c.i18n) + (c.suffix ? ' · ' + t(c.suffix) : ''); }

// ── Garment thumbnails (generated by the v-clothing admin scan) ──
const postJ = (name, data) => fetch(`https://${RES}/${name}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data || {}) }).then(r => r.json()).catch(() => null);
const CLOTH_MEM = new Map();     // 'cat_d' -> data URI
const CLOTH_IDX = new Map();     // cat -> Promise<number[]>

function clothIndex(cat) {
  if (!CLOTH_IDX.has(cat)) {
    CLOTH_IDX.set(cat, postJ('clothThumbIndex', { category: cat })
      .then(l => Array.isArray(l) ? l.map(Number).sort((a, b) => a - b) : []).catch(() => []));
  }
  return CLOTH_IDX.get(cat);
}

// A horizontal strip of garment images under a clothing stepper: click a
// picture to wear it. Only scanned pieces appear; images lazy-load in batches.
async function buildGallery(row, c) {
  const list = await clothIndex(c.cat);
  if (!list.length || !row.isConnected) return;
  const strip = document.createElement('div'); strip.className = 'thumbstrip';
  let queue = [], timer = null;
  const flush = async () => {
    timer = null;
    const imgs = queue.splice(0, 24);
    if (queue.length && !timer) timer = setTimeout(flush, 60);
    if (!imgs.length) return;
    const out = await postJ('clothThumbs', { list: imgs.map(i => ({ cat: c.cat, d: +i.dataset.d })) });
    const map = new Map((Array.isArray(out) ? out : []).map(e => [String(e.d), e.uri]));
    imgs.forEach(img => {
      const uri = map.get(img.dataset.d);
      if (uri) { CLOTH_MEM.set(c.cat + '_' + img.dataset.d, uri); img.src = uri; img.parentElement.classList.add('ready'); }
    });
  };
  const obs = new IntersectionObserver((ents) => {
    ents.forEach(en => {
      if (!en.isIntersecting) return;
      obs.unobserve(en.target);
      if (en.target.dataset.loaded) return;
      en.target.dataset.loaded = '1';
      queue.push(en.target);
      if (!timer) timer = setTimeout(flush, 60);
    });
  }, { root: strip, rootMargin: '140px' });
  const cur = Math.round(getPath(appearance, c.path) ?? -99);
  list.forEach(d => {
    const cell = document.createElement('button');
    cell.className = 'tcell' + (d === cur ? ' sel' : '');
    cell.setAttribute('aria-label', ctrlLabel(c) + ' ' + d);
    const img = document.createElement('img'); img.dataset.d = d; img.alt = '';
    const hit = CLOTH_MEM.get(c.cat + '_' + d);
    if (hit) { img.src = hit; cell.classList.add('ready'); } else obs.observe(img);
    const num = document.createElement('span'); num.className = 'tnum'; num.textContent = d;
    cell.append(img, num);
    cell.onclick = () => {
      setPath(appearance, c.path, d);
      const v = row.querySelector('[data-val]'); if (v) v.textContent = d;
      const fill = row.querySelector('.bar i'); if (fill) fill.style.width = (((d - c.min) / (c.max - c.min)) * 100) + '%';
      strip.querySelectorAll('.tcell').forEach(x => x.classList.toggle('sel', x === cell));
      pushUpdate();
    };
    strip.appendChild(cell);
  });
  row.appendChild(strip);
}

function buildControls() {
  const wrap = byId('controls'); wrap.innerHTML = '';
  (SCHEMA[currentTab] || []).forEach(c => {
    let val = getPath(appearance, c.path);
    if (val === undefined || val === null) val = (c.type === 'slider') ? 0 : (c.min || 0);

    const row = document.createElement('div');
    row.className = 'ctrl';

    if (c.type === 'color') {
      row.innerHTML = `<div class="top"><span class="v-label">${ctrlLabel(c)}</span></div>`;
      const grid = document.createElement('div'); grid.className = 'swatch-grid';
      c.palette.forEach((hex, i) => {
        const sw = document.createElement('button');
        sw.className = 'sw' + (i === val ? ' sel' : '');
        sw.style.background = hex;
        sw.setAttribute('aria-label', ctrlLabel(c) + ' ' + (i + 1));
        sw.onclick = () => {
          setPath(appearance, c.path, i);
          grid.querySelectorAll('.sw').forEach(x => x.classList.remove('sel'));
          sw.classList.add('sel'); pushUpdate();
        };
        grid.appendChild(sw);
      });
      row.appendChild(grid);
    } else if (c.type === 'slider') {
      const disp = Math.round(val * 100);
      row.innerHTML = `<div class="top"><span class="v-label">${ctrlLabel(c)}</span><span class="val" data-val>${disp}</span></div>`;
      const s = document.createElement('input');
      s.type = 'range'; s.min = c.min; s.max = c.max; s.step = c.step || 0.1; s.value = val;
      s.setAttribute('aria-label', ctrlLabel(c));
      s.oninput = () => { const v = parseFloat(s.value); setPath(appearance, c.path, v); row.querySelector('[data-val]').textContent = Math.round(v * 100); pushUpdate(); };
      row.appendChild(s);
    } else {
      row.innerHTML = `<div class="top"><span class="v-label">${ctrlLabel(c)}</span><span class="val" data-val>${Math.round(val)}</span></div>`;
      const st = document.createElement('div'); st.className = 'stepper';
      const dec = document.createElement('button'); dec.className = 'step-btn'; dec.textContent = '−'; dec.setAttribute('aria-label', ctrlLabel(c) + ' −');
      const bar = document.createElement('div'); bar.className = 'bar'; bar.innerHTML = '<i></i>';
      const inc = document.createElement('button'); inc.className = 'step-btn'; inc.textContent = '+'; inc.setAttribute('aria-label', ctrlLabel(c) + ' +');
      const fill = () => { bar.querySelector('i').style.width = (((getPath(appearance, c.path) - c.min) / (c.max - c.min)) * 100) + '%'; };
      const change = (d) => {
        let v = Math.round(getPath(appearance, c.path) ?? c.min) + d;
        if (v < c.min) v = c.max; if (v > c.max) v = c.min;
        setPath(appearance, c.path, v);
        row.querySelector('[data-val]').textContent = v; fill(); pushUpdate();
      };
      dec.onclick = () => change(-1); inc.onclick = () => change(1);
      st.append(dec, bar, inc); row.appendChild(st); setTimeout(fill, 0);
      if (c.cat) buildGallery(row, c);   // garment picture strip (if scanned)
    }
    wrap.appendChild(row);
  });
}

// ── Mouse orbit camera (drag on the stage, wheel to zoom) ──
let dragging = false, lastX = 0, lastY = 0, accDx = 0, accDy = 0, raf = false;
function flushOrbit() { if (accDx || accDy) { post('camera', { orbit: { dx: accDx, dy: accDy } }); accDx = 0; accDy = 0; } raf = false; }
byId('stage').addEventListener('mousedown', (e) => { dragging = true; lastX = e.clientX; lastY = e.clientY; });
window.addEventListener('mouseup', () => { dragging = false; });
window.addEventListener('mousemove', (e) => {
  if (!dragging) return;
  accDx += e.clientX - lastX; accDy += e.clientY - lastY; lastX = e.clientX; lastY = e.clientY;
  if (!raf) { raf = true; requestAnimationFrame(flushOrbit); }
});
window.addEventListener('wheel', (e) => { post('camera', { zoom: e.deltaY > 0 ? -1 : 1 }); });

// ── Language ──
document.querySelectorAll('.lang-btn').forEach(b => b.onclick = () => {
  post('selectLang', { lang: b.getAttribute('data-lang') });
  byId('screen-language').classList.add('hidden');
  byId('panel').classList.remove('hidden');
  byId('stage').classList.remove('hidden');
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

// ── Camera zone buttons ──
document.querySelectorAll('.cam-zone').forEach(b => b.onclick = () => {
  document.querySelectorAll('.cam-zone').forEach(x => x.classList.remove('on'));
  b.classList.add('on'); post('camera', { zone: b.getAttribute('data-zone') });
});

// ── Messages from Lua ──
window.addEventListener('message', (e) => {
  const d = e.data || {};
  switch (d.action) {
    case 'characters': buildCharacters(d.data || {}); break;
    case 'open':
      byId('screen-language').classList.remove('hidden');
      byId('panel').classList.add('hidden');
      byId('cam').classList.add('hidden');
      byId('stage').classList.add('hidden');
      break;
    case 'strings': strings = d.strings || {}; applyStrings(); break;
    case 'appearance':
      appearance = d.data; if (!byId('screen-appearance').classList.contains('hidden')) buildControls(); break;
    case 'screen':
      if (d.appearance) appearance = d.appearance;
      showScreen(d.screen, d); break;
    case 'close':
      ['screen-select', 'screen-language', 'screen-spawn', 'panel', 'cam', 'stage'].forEach(id => byId(id).classList.add('hidden'));
      break;
  }
});
