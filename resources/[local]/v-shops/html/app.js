// v-shops — store UI (catalogue + your inventory; buy via button or drag-to-inventory)
const byId = (id) => document.getElementById(id);
const post = (n, b) => fetch(`https://v-shops/${n}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(b || {}) }).then(r => r.json()).catch(() => false);
// Muted/earthy category rings — orange stays the only saturated hue on screen.
const CAT = { food: '#4E8C5A', drinks: '#2F6F9E', medical: '#C2362F', weapon: '#6B6156', tool: '#C98A2B',
  gadget: '#2F6F9E', tech: '#2F6F9E', smokes: '#6B6156', money: '#5FA36A', misc: '#FF6A1A' };
const RARITY = { common: '#6B6156', uncommon: '#4E8C5A', rare: '#2F6F9E', epic: '#8A4BD1', legendary: '#FF6A1A', mythic: '#C2362F' };
const fmt = (n) => '$' + Math.floor(Number(n) || 0).toLocaleString('en-US');
const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

// Clothing items carry no raster image — fall back to a garment/box glyph.
const CLOTH_IC = {
  mask: 'M4 8c0-2 3-3 8-3s8 1 8 3v3c0 4-4 8-8 8s-8-4-8-8Z', top: 'M8 3 4 6l2 3 1-1v12h10V8l1 1 2-3-4-3-3 2Z',
  pants: 'M6 3h12l-1 18h-4l-1-9-1 9H6Z', shoes: 'M2 16h13l5 2v2H2ZM5 16V9l4-1 2 3 4 1',
};
const BOX_IC = '<path d="M3 7l9-4 9 4v10l-9 4-9-4V7Z"/><path d="M3 7l9 4 9-4M12 11v10"/>';
function iconFor(name) {
  const p = CLOTH_IC[name];
  return `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linejoin="round">${p ? `<path d="${p}"/>` : BOX_IC}</svg>`;
}

let strings = {}, shop = null, account = 'cash';
const t = (k) => strings[k] || k;
const applyStrings = () => document.querySelectorAll('[data-i18n]').forEach(el => { el.textContent = t(el.getAttribute('data-i18n')); });

function setAccount(acc) {
  account = acc;
  byId('pay-cash').classList.toggle('sel', acc === 'cash');
  byId('pay-bank').classList.toggle('sel', acc === 'bank');
}
function setBalances(cash, bank) { byId('w-cash').textContent = fmt(cash); byId('w-bank').textContent = fmt(bank); }
function close() { byId('shop').classList.add('hidden'); post('close'); }

byId('pay-cash').onclick = () => setAccount('cash');
byId('pay-bank').onclick = () => setAccount('bank');
byId('close').onclick = close;
document.addEventListener('keydown', (e) => { if (e.key === 'Escape' && !byId('shop').classList.contains('hidden')) close(); });

// ── Buy (shared by the button and drag-to-inventory) ──
async function buy(name, amount) {
  const res = await post('buy', { shopId: shop.id, item: name, amount, account });
  if (res && res.cash !== undefined) {
    shop.cash = res.cash; shop.bank = res.bank; setBalances(res.cash, res.bank);
    if (res.inv) { shop.inv = res.inv; renderInventory(); }
  }
}

// ── Catalogue ──
function renderCatalogue() {
  const list = byId('list'); list.innerHTML = '';
  shop.items.forEach((it, i) => {
    const row = document.createElement('div');
    row.className = 'row'; row.dataset.name = it.name;
    row.style.setProperty('--cat', RARITY[it.rarity] || CAT[it.category] || CAT.misc);
    row.style.setProperty('--i', i);
    const thumb = it.image
      ? `<div class="thumb" style="background-image:url('https://cfx-nui-v-inventory/html/images/${esc(it.image)}')"></div>`
      : `<div class="thumb ph">${iconFor(it.name)}</div>`;
    row.innerHTML =
      thumb +
      `<div class="info"><div class="name">${esc(it.label)}</div><div class="price"><b>${fmt(it.price)}</b> ${t('shop.each')}</div></div>` +
      `<div class="stepper"><button class="step dec" aria-label="Decrease quantity">−</button><span class="qty">1</span><button class="step inc" aria-label="Increase quantity">+</button></div>` +
      `<button class="buy" data-i18n="shop.buy">Buy</button>`;
    const qty = row.querySelector('.qty');
    row.querySelector('.dec').onclick = () => { qty.textContent = Math.max(1, (+qty.textContent) - 1); };
    row.querySelector('.inc').onclick = () => { qty.textContent = Math.min(99, (+qty.textContent) + 1); };
    row.querySelector('.buy').onclick = () => buy(it.name, +qty.textContent);
    list.appendChild(row);
  });
  applyStrings();
}

// ── Your inventory (right panel; drop target for buying) ──
function renderInventory() {
  const wrap = byId('inv-grid'); wrap.innerHTML = '';
  const inv = shop.inv || { items: [], defs: {}, maxSlots: 40 };
  const bySlot = {}; (inv.items || []).forEach(it => { bySlot[it.slot] = it; });
  for (let s = 1; s <= (inv.maxSlots || 40); s++) {
    const cell = document.createElement('div'); cell.className = 'icell';
    const it = bySlot[s];
    if (it) {
      const d = inv.defs[it.name] || {};
      cell.classList.add('has');
      cell.style.setProperty('--cat', RARITY[d.rarity] || CAT[d.category] || 'var(--v-line)');
      if (d.image) cell.style.backgroundImage = `url('https://cfx-nui-v-inventory/html/images/${esc(d.image)}')`;
      else cell.innerHTML = `<span class="ph">${iconFor(it.name)}</span>`;
      if (it.amount > 1) cell.innerHTML += `<span class="amt">${it.amount}</span>`;
    }
    wrap.appendChild(cell);
  }
}

function render() {
  byId('shop-label').textContent = shop.label;
  setBalances(shop.cash, shop.bank);
  renderCatalogue();
  renderInventory();
}

// ── Drag a catalogue item onto your inventory to buy it (pointer-based) ──
let drag = null;
const THRESH = 4;

function onDown(e) {
  if (e.button !== 0) return;
  if (e.target.closest('.buy,.step')) return;         // let buttons work
  const row = e.target.closest('.row'); if (!row) return;
  drag = { name: row.dataset.name, row, startX: e.clientX, startY: e.clientY, active: false, ghost: null };
}
function onMove(e) {
  if (!drag) return;
  if (!drag.active) {
    if (Math.abs(e.clientX - drag.startX) + Math.abs(e.clientY - drag.startY) < THRESH) return;
    drag.active = true;
    drag.row.classList.add('dragging');
    const it = shop.items.find(x => x.name === drag.name) || {};
    const g = document.createElement('div'); g.className = 'drag-ghost';
    if (it.image) g.style.backgroundImage = `url('https://cfx-nui-v-inventory/html/images/${it.image}')`;
    else g.innerHTML = iconFor(drag.name);
    document.body.appendChild(g); drag.ghost = g;
  }
  drag.ghost.style.left = e.clientX + 'px';
  drag.ghost.style.top = e.clientY + 'px';
  const over = document.elementFromPoint(e.clientX, e.clientY);
  byId('inv-grid').classList.toggle('drop-on', !!(over && over.closest('.invview')));
}
async function onUp(e) {
  const d = drag; drag = null;
  if (!d) return;
  d.row.classList.remove('dragging');
  byId('inv-grid').classList.remove('drop-on');
  if (d.ghost) d.ghost.remove();
  if (!d.active) return;
  const over = document.elementFromPoint(e.clientX, e.clientY);
  if (over && over.closest('.invview')) buy(d.name, 1);   // drop on inventory = buy 1
}

window.addEventListener('message', (e) => {
  const d = e.data || {};
  if (d.action === 'open') {
    strings = d.strings || {}; shop = d.shop; setAccount('cash');
    render();
    byId('shop').classList.remove('hidden');
  } else if (d.action === 'close') {
    byId('shop').classList.add('hidden');
  }
});

byId('list').addEventListener('mousedown', onDown);
document.addEventListener('mousemove', onMove);
document.addEventListener('mouseup', onUp);
