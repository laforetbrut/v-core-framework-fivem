// v-clothing — catalogue UI (click a tile -> preview on the ped)
const byId = (id) => document.getElementById(id);
const post = (n, b) => fetch(`https://v-clothing/${n}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(b || {}) }).then(r => r.json()).catch(() => false);
const fmt = (n) => '$' + Math.floor(Number(n) || 0).toLocaleString('en-US');

let strings = {}, cats = [], catMap = {}, worn = [];
let curCat = null, curDraw = 0, curTex = 0, texCount = 0, filter = '';
let thumbSet = new Set(), thumbObserver = null;
const t = (k) => strings[k] || k;
const applyStrings = () => document.querySelectorAll('[data-i18n]').forEach(el => { el.textContent = t(el.getAttribute('data-i18n')); });

function setTab(tab) {
  document.querySelectorAll('.tab').forEach(b => b.classList.toggle('on', b.getAttribute('data-tab') === tab));
  byId('pane-store').classList.toggle('hidden', tab !== 'store');
  byId('pane-worn').classList.toggle('hidden', tab !== 'worn');
  if (tab === 'worn') renderWorn();
}

function renderCats() {
  const wrap = byId('cats'); wrap.innerHTML = '';
  cats.forEach(c => {
    const b = document.createElement('button');
    b.className = 'chip' + (c.key === curCat ? ' on' : '');
    b.textContent = t(c.i18n);
    b.onclick = () => selectCategory(c.key);
    wrap.appendChild(b);
  });
}

async function selectCategory(key) {
  curCat = key; filter = ''; byId('search').value = '';
  renderCats();
  const c = catMap[key];
  curDraw = c.drawable;
  thumbSet = new Set();
  renderTiles();                       // instant grid (numbers)
  await selectDrawable(curDraw, false);
  // then discover which drawables have a generated thumbnail and upgrade
  const list = await post('thumbsFor', { category: key });
  if (key !== curCat) return;
  const set = new Set(Array.isArray(list) ? list.map(Number) : []);
  if (set.size) { thumbSet = set; renderTiles(); }
}

// Lazy-load a tile's thumbnail (base64) only when it scrolls into view.
function ensureObserver() {
  if (thumbObserver) return thumbObserver;
  thumbObserver = new IntersectionObserver((entries) => {
    entries.forEach(async (en) => {
      if (!en.isIntersecting) return;
      const img = en.target;
      thumbObserver.unobserve(img);
      if (img.dataset.loaded) return;
      img.dataset.loaded = '1';
      const uri = await post('thumb', { category: img.dataset.cat, drawable: +img.dataset.d });
      if (typeof uri === 'string' && uri) { img.src = uri; img.parentElement.classList.add('ready'); }
    });
  }, { root: byId('tiles'), rootMargin: '160px' });
  return thumbObserver;
}

function renderTiles() {
  const c = catMap[curCat];
  const grid = byId('tiles'); grid.innerHTML = '';
  const obs = ensureObserver(); obs.disconnect();
  for (let d = c.min; d < c.count; d++) {
    if (filter && !String(d).includes(filter)) continue;
    const has = thumbSet.has(d);
    const tile = document.createElement('div');
    tile.className = 'tile' + (d === curDraw ? ' sel' : '') + (has ? ' has' : '');
    tile.dataset.d = d;
    if (d < 0) {
      tile.innerHTML = `<span class="none">&times;</span>`;
    } else if (has) {
      const img = document.createElement('img');
      img.className = 'thumb'; img.dataset.cat = curCat; img.dataset.d = d; img.alt = '';
      const badge = document.createElement('span'); badge.className = 'num'; badge.textContent = d;
      tile.append(img, badge);
      obs.observe(img);
    } else {
      tile.innerHTML = `<span class="num">${d}</span>`;
    }
    tile.onclick = () => selectDrawable(d, true);
    grid.appendChild(tile);
  }
}

async function selectDrawable(d, scroll) {
  curDraw = d;
  const res = await post('select', { category: curCat, drawable: d });
  texCount = (res && res.textureCount) || 0;
  curTex = 0;
  document.querySelectorAll('#tiles .tile').forEach(x => x.classList.toggle('sel', +x.dataset.d === d));
  if (scroll) { const el = [...document.querySelectorAll('#tiles .tile')].find(x => +x.dataset.d === d); if (el) el.scrollIntoView({ block: 'nearest' }); }
  renderTex();
  updateBar();
}

function renderTex() {
  const wrap = byId('tex'); wrap.innerHTML = '';
  for (let i = 0; i < Math.max(1, texCount); i++) {
    const b = document.createElement('button');
    b.className = 'tx' + (i === curTex ? ' sel' : '');
    b.textContent = i;
    b.onclick = async () => { curTex = i; await post('selectTexture', { category: curCat, drawable: curDraw, texture: i }); renderTex(); };
    wrap.appendChild(b);
  }
}

function updateBar() {
  const c = catMap[curCat];
  byId('bsel').innerHTML = `<b>${t(c.i18n)}</b> · #${curDraw}`;
  byId('buy').textContent = `${t('cl.buy')} · ${fmt(c.price)}`;
}

byId('buy').onclick = async () => {
  const res = await post('buy', { category: curCat });
  if (res && res.cash !== undefined) byId('cash').textContent = fmt(res.cash);
};

byId('search').oninput = (e) => { filter = e.target.value.trim(); renderTiles(); };

function renderWorn() {
  const pane = byId('pane-worn'); pane.innerHTML = '';
  if (!worn.length) { pane.innerHTML = `<div class="empty">${t('cl.none')}</div>`; return; }
  worn.forEach(w => {
    const row = document.createElement('div');
    row.className = 'wrow';
    row.innerHTML = `<span class="wl">${t('item.' + w.item)}</span><button class="wu">${t('cl.unequip')}</button>`;
    row.querySelector('.wu').onclick = async () => { const res = await post('unequip', { category: w.cat }); if (Array.isArray(res)) { worn = res; renderWorn(); } };
    pane.appendChild(row);
  });
}

// ── Mouse drag → rotate the ped ──
let dragging = false, lastX = 0, accDx = 0, raf = false;
function flush() { if (accDx) { post('rotate', { dx: accDx }); accDx = 0; } raf = false; }
byId('stage').addEventListener('mousedown', (e) => { dragging = true; lastX = e.clientX; });
window.addEventListener('mouseup', () => { dragging = false; });
window.addEventListener('mousemove', (e) => { if (!dragging) return; accDx += e.clientX - lastX; lastX = e.clientX; if (!raf) { raf = true; requestAnimationFrame(flush); } });

document.querySelectorAll('.tab').forEach(b => b.onclick = () => setTab(b.getAttribute('data-tab')));
function close() { byId('cl').classList.add('hidden'); byId('stage').classList.add('hidden'); post('close'); }
byId('close').onclick = close;
document.addEventListener('keydown', (e) => { if (e.key === 'Escape' && !byId('cl').classList.contains('hidden')) close(); });

// Admin scan: downscale the raw screenshot to a square thumbnail and upload
// it to the game server over HTTP (net events would kick the player).
async function handleThumbUpload(d) {
  const done = (ok) => post('uploadDone', { ok });
  try {
    const img = new Image();
    await new Promise((res, rej) => { img.onload = res; img.onerror = rej; img.src = d.uri; });
    const s = d.size || 384;
    const cv = document.createElement('canvas'); cv.width = s; cv.height = s;
    const side = Math.min(img.width, img.height);
    cv.getContext('2d').drawImage(img, (img.width - side) / 2, (img.height - side) / 2, side, side, 0, 0, s, s);
    const uri = cv.toDataURL('image/jpeg', d.quality || 0.85);
    const r = await fetch(`http://${d.endpoint}/${d.res}/upload`, {
      method: 'POST', headers: { 'Content-Type': 'text/plain' },   // simple request: no CORS preflight
      body: JSON.stringify({ t: d.token, cat: d.cat, d: d.drawable, uri }),
    });
    done(r.ok);
  } catch (e) { done(false); }
}

window.addEventListener('message', (e) => {
  const d = e.data || {};
  if (d.action === 'uploadThumb') {
    handleThumbUpload(d);
  } else if (d.action === 'open') {
    strings = d.strings || {}; cats = d.cats || []; worn = d.worn || [];
    catMap = {}; cats.forEach(c => catMap[c.key] = c);
    if (d.cash !== undefined) byId('cash').textContent = fmt(d.cash);
    applyStrings(); setTab('store');
    if (cats[0]) selectCategory(cats[0].key);
    byId('cl').classList.remove('hidden');
    byId('stage').classList.remove('hidden');
  } else if (d.action === 'close') {
    byId('cl').classList.add('hidden');
    byId('stage').classList.add('hidden');
  }
});
