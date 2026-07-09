// v-clothing — store UI
const byId = (id) => document.getElementById(id);
const post = (n, b) => fetch(`https://v-clothing/${n}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(b || {}) }).then(r => r.json()).catch(() => false);
const fmt = (n) => '$' + Math.floor(Number(n) || 0).toLocaleString('en-US');

let strings = {}, cats = [], worn = [], prices = {};
const t = (k) => strings[k] || k;
const applyStrings = () => document.querySelectorAll('[data-i18n]').forEach(el => { el.textContent = t(el.getAttribute('data-i18n')); });

function setTab(tab) {
  document.querySelectorAll('.tab').forEach(b => b.classList.toggle('on', b.getAttribute('data-tab') === tab));
  byId('pane-store').classList.toggle('hidden', tab !== 'store');
  byId('pane-worn').classList.toggle('hidden', tab !== 'worn');
  if (tab === 'worn') renderWorn();
}

function renderStore() {
  const pane = byId('pane-store'); pane.innerHTML = '';
  cats.forEach(c => {
    prices[c.key] = c.price;
    const row = document.createElement('div');
    row.className = 'crow';
    row.innerHTML =
      `<div class="cname">${t(c.i18n)}</div>` +
      `<div class="ctls">` +
        `<div class="ctl"><span class="v-label" data-i18n="cl.style">Style</span><div class="stp"><button class="s" data-dir="-1" data-f="drawable">◀</button><span class="v" data-d>${c.drawable}</span><button class="s" data-dir="1" data-f="drawable">▶</button></div></div>` +
        `<div class="ctl"><span class="v-label" data-i18n="cl.texture">Texture</span><div class="stp"><button class="s" data-dir="-1" data-f="texture">◀</button><span class="v" data-t>${c.texture}</span><button class="s" data-dir="1" data-f="texture">▶</button></div></div>` +
      `</div>` +
      `<button class="buy">${t('cl.buy')} · ${fmt(c.price)}</button>`;
    row.querySelectorAll('.s').forEach(btn => btn.onclick = async () => {
      const res = await post('cycle', { category: c.key, field: btn.getAttribute('data-f'), delta: +btn.getAttribute('data-dir') });
      if (res && res.drawable !== undefined) { row.querySelector('[data-d]').textContent = res.drawable; row.querySelector('[data-t]').textContent = res.texture; }
    });
    row.querySelector('.buy').onclick = async () => {
      const res = await post('buy', { category: c.key });
      if (res && res.cash !== undefined) byId('cash').textContent = fmt(res.cash);
    };
    pane.appendChild(row);
  });
  applyStrings();
}

function renderWorn() {
  const pane = byId('pane-worn'); pane.innerHTML = '';
  if (!worn.length) { pane.innerHTML = `<div class="empty">${t('cl.none')}</div>`; return; }
  worn.forEach(w => {
    const row = document.createElement('div');
    row.className = 'wrow';
    row.innerHTML = `<span class="wl">${t('item.' + w.item)}</span><button class="wu">${t('cl.unequip')}</button>`;
    row.querySelector('.wu').onclick = async () => {
      const res = await post('unequip', { category: w.cat });
      if (Array.isArray(res)) { worn = res; renderWorn(); }
    };
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

window.addEventListener('message', (e) => {
  const d = e.data || {};
  if (d.action === 'open') {
    strings = d.strings || {}; cats = d.cats || []; worn = d.worn || [];
    if (d.cash !== undefined) byId('cash').textContent = fmt(d.cash);
    setTab('store'); renderStore();
    byId('cl').classList.remove('hidden');
    byId('stage').classList.remove('hidden');
  } else if (d.action === 'close') {
    byId('cl').classList.add('hidden');
    byId('stage').classList.add('hidden');
  }
});
