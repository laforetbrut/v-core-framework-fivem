// v-inventory — quasar/ox-style grid. Server-authoritative: every action posts to
// Lua and re-renders from the returned state. Native HTML5 drag & drop, delegated
// listeners, single tooltip/context/amount singletons. CEF-103 safe.
const byId = (id) => document.getElementById(id);
const post = (n, b) => fetch(`https://v-inventory/${n}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(b || {}) }).then(r => r.json()).catch(() => false);
const money = (n) => '$' + Math.floor(Number(n) || 0).toLocaleString('en-US');
const kg = (g) => (g >= 1000 ? (g / 1000).toFixed(1) + ' kg' : Math.round(g) + ' g');

const CAT = {
  money: '#43C46A', general: '#FF9354', food: '#43C46A', drinks: '#4AA8FF', medical: '#E5484D',
  weapons: '#9C99A2', tools: '#F5A623', materials: '#B0895E', ingredients: '#7FB86B', drugs: '#C77DFF',
  smokes: '#8C8C8C', tech: '#4AA8FF', jewelry: '#F5C542', mechanic: '#F5A623', misc: '#FF6A1A',
};

let state = null, strings = {}, defs = {};
let maps = { player: {}, secondary: {} };
let drag = null;            // { inv, slot, money? }
let built = false;

const t = (k) => strings[k] || k;
const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

function applyStrings() {
  document.querySelectorAll('[data-i18n]').forEach(el => { el.textContent = t(el.getAttribute('data-i18n')); });
  document.querySelectorAll('[data-i18n-ph]').forEach(el => { el.placeholder = t(el.getAttribute('data-i18n-ph')); });
}

// ── State → slot maps ──
function rebuildMaps() {
  maps = { player: {}, secondary: {} };
  (state.player.items || []).forEach(it => { maps.player[it.slot] = it; });
  if (state.secondary) (state.secondary.items || []).forEach(it => { maps.secondary[it.slot] = it; });
}
const itemAt = (inv, slot) => (maps[inv] || {})[slot];
const def = (name) => defs[name] || { label: name, weight: 0, category: 'misc', image: '', stackable: 1, usable: 0, metadata: {} };

// ── Build fixed slot grids once ──
function slotEl(inv, slot) {
  const el = document.createElement('div');
  el.className = 'slot'; el.dataset.inv = inv; el.dataset.slot = slot;
  el.innerHTML = '<span class="hk"></span><span class="count"></span><span class="scrim"></span><span class="label"></span>';
  return el;
}
function buildGrid(gridId, inv, count) {
  const g = byId(gridId); g.innerHTML = '';
  for (let s = 1; s <= count; s++) g.appendChild(slotEl(inv, s));
}
function buildHotbar(n) {
  const h = byId('hotbar'); h.innerHTML = '';
  for (let s = 1; s <= n; s++) { const el = slotEl('player', s); el.dataset.hot = s; h.appendChild(el); }
}

// ── Render ──
function renderSlot(el) {
  const inv = el.dataset.inv, slot = +el.dataset.slot;
  const it = itemAt(inv, slot);
  const count = el.querySelector('.count'); const label = el.querySelector('.label');
  if (!it) {
    el.removeAttribute('data-item'); el.draggable = false; el.style.backgroundImage = ''; el.style.removeProperty('--cat');
    count.textContent = ''; label.textContent = ''; return;
  }
  const d = def(it.name);
  el.setAttribute('data-item', it.name); el.draggable = true;
  el.style.setProperty('--cat', CAT[d.category] || 'var(--v-accent)');
  el.style.backgroundImage = d.image ? `url("images/${d.image}")` : '';
  count.textContent = it.amount > 1 ? it.amount : '';
  label.textContent = d.label || it.name;
}
function renderGrid(inv) {
  const gid = inv === 'player' ? 'grid-player' : 'grid-secondary';
  byId(gid).querySelectorAll('.slot').forEach(renderSlot);
  if (inv === 'player') byId('hotbar').querySelectorAll('.slot').forEach(renderSlot);
}
function setWeight(prefix, w, max) {
  const pct = max > 0 ? Math.min(100, (w / max) * 100) : 0;
  byId(prefix + '-wfill').style.width = pct + '%';
  byId(prefix + '-wbar').classList.toggle('over', w > max);
  byId(prefix + '-wtxt').textContent = kg(w) + ' / ' + kg(max);
}
function render() {
  rebuildMaps();
  renderGrid('player');
  byId('wallet-amt').textContent = money(state.player.cash);
  setWeight('player', state.player.weight, state.maxWeight);
  const sec = state.secondary;
  byId('panel-secondary').classList.toggle('hidden', !sec);
  if (sec) {
    byId('sec-label').textContent = t(sec.label || 'inv.stash');
    renderGrid('secondary');
    let w = 0; (sec.items || []).forEach(it => { w += (def(it.name).weight || 0) * it.amount; });
    setWeight('sec', w, sec.maxWeight || 0);
  }
  byId('hotbar').querySelectorAll('.slot').forEach(el => { el.querySelector('.hk').textContent = el.dataset.hot; });
  applyFilter('player'); applyFilter('secondary');
}

function applyState(s) { if (!s || s.error) return; state = s; render(); }

// ── Drag & drop (delegated) ──
function onDragStart(e) {
  const el = e.target.closest('.slot,.wallet'); if (!el) return;
  if (el.id === 'wallet') { drag = { inv: 'wallet', slot: 'money', money: true }; el.classList.add('dragging'); return; }
  if (!el.hasAttribute('data-item')) { e.preventDefault(); return; }
  drag = { inv: el.dataset.inv, slot: +el.dataset.slot };
  e.dataTransfer.effectAllowed = 'move'; e.dataTransfer.setData('text', el.dataset.slot);
  el.classList.add('dragging');
}
function onDragOver(e) {
  const el = e.target.closest('.slot,.wallet'); if (!el || !drag) return;
  e.preventDefault();
  const cur = document.querySelector('.drop-hover'); if (cur && cur !== el) cur.classList.remove('drop-hover');
  el.classList.add('drop-hover');
}
function onDragEnd() {
  document.querySelectorAll('.dragging,.drop-hover').forEach(el => el.classList.remove('dragging', 'drop-hover'));
  drag = null;
}
async function onDrop(e) {
  const el = e.target.closest('.slot,.wallet'); if (!el || !drag) return;
  e.preventDefault();
  const from = drag;
  const to = el.id === 'wallet' ? { inv: 'wallet', slot: 'money' } : { inv: el.dataset.inv, slot: +el.dataset.slot };
  const shift = e.shiftKey;
  onDragEnd();
  if (from.inv === to.inv && from.slot === to.slot) return;

  // Cash: wallet -> a container needs an amount
  if (from.money) {
    if (to.inv === 'secondary') showAmount(state.player.cash, async (amt) => applyState(await post('move', { from: 'wallet', to: 'secondary', amount: amt })));
    return;
  }
  const src = itemAt(from.inv, from.slot); if (!src) return;
  const doMove = async (amt) => applyState(await post('move', { from: from.inv, fromSlot: from.slot, to: to.inv, toSlot: to.slot, amount: amt }));
  if (shift && src.amount > 1) showAmount(src.amount, doMove); else doMove(src.amount);
}

// ── Tooltip ──
function onHover(e) {
  const el = e.target.closest('.slot'); const tt = byId('tooltip');
  if (!el || !el.hasAttribute('data-item')) return;
  const it = itemAt(el.dataset.inv, +el.dataset.slot); if (!it) return;
  const d = def(it.name); const meta = d.metadata || {};
  tt.innerHTML = `<h4>${esc(d.label || it.name)}</h4><div class="sub">${esc(it.name)}</div>`
    + `<div class="row">${t('inv.weight')}: ${kg((d.weight || 0) * it.amount)}</div>`
    + (it.amount > 1 ? `<div class="row">${t('inv.qty')}: ${it.amount}</div>` : '')
    + (meta.desc ? `<div class="desc">${esc(meta.desc)}</div>` : '');
  tt.classList.remove('hidden');
  positionFloat(tt, e.clientX + 16, e.clientY + 16);
}
function positionFloat(el, x, y) {
  const r = el.getBoundingClientRect();
  el.style.left = Math.max(6, Math.min(x, window.innerWidth - r.width - 8)) + 'px';
  el.style.top = Math.max(6, Math.min(y, window.innerHeight - r.height - 8)) + 'px';
}
document.addEventListener('mousemove', (e) => {
  const tt = byId('tooltip');
  if (!tt.classList.contains('hidden')) positionFloat(tt, e.clientX + 16, e.clientY + 16);
});
function hideTooltip() { byId('tooltip').classList.add('hidden'); }

// ── Context menu ──
function onContext(e) {
  const el = e.target.closest('.slot,.wallet'); if (!el) return;
  e.preventDefault();
  hideTooltip();
  const menu = byId('context'); menu.innerHTML = '';
  const add = (label, fn, danger) => {
    const li = document.createElement('li'); if (danger) li.className = 'danger';
    li.innerHTML = `<span>${esc(label)}</span>`;
    li.onclick = () => { closeContext(); fn(); }; menu.appendChild(li);
  };
  if (el.id === 'wallet') {
    if ((state.player.cash || 0) <= 0) return;
    add(t('inv.give'), giveMoney);
    add(t('inv.drop'), dropMoney, true);
  } else {
    if (!el.hasAttribute('data-item')) return;
    const inv = el.dataset.inv, slot = +el.dataset.slot;
    const it = itemAt(inv, slot); if (!it) return; const d = def(it.name);
    if (inv === 'player' && d.usable == 1) add(t('inv.use'), async () => applyState(await post('use', { slot })));
    if (inv === 'player') add(t('inv.give'), () => giveItem(slot, it.amount));
    if (inv === 'player') add(t('inv.drop'), () => dropItem(inv, slot, it.amount), true);
    if (it.amount > 1) add(t('inv.split'), () => showAmount(it.amount, async (amt) => applyState(await post('move', { from: inv, fromSlot: slot, to: inv, amount: amt }))));
  }
  menu.classList.remove('hidden');
  positionFloat(menu, e.clientX, e.clientY);
}
function closeContext() { byId('context').classList.add('hidden'); }

// ── Money / item give-drop ──
function giveMoney() { showAmount(state.player.cash, async (amt) => applyState(await post('give', { money: true, amount: amt }))); }
function dropMoney() { showAmount(state.player.cash, async (amt) => applyState(await post('drop', { money: true, amount: amt }))); }
function giveItem(slot, max) {
  if (max > 1) showAmount(max, async (amt) => applyState(await post('give', { slot, amount: amt })));
  else post('give', { slot, amount: 1 }).then(applyState);
}
function dropItem(inv, slot, max) {
  if (max > 1) showAmount(max, async (amt) => applyState(await post('drop', { inv, slot, amount: amt })));
  else post('drop', { inv, slot, amount: 1 }).then(applyState);
}

// ── Amount picker ──
let amountCb = null;
function showAmount(max, cb) {
  amountCb = cb; max = Math.max(1, Math.floor(max));
  const inp = byId('amount-input'), rng = byId('amount-range');
  inp.max = max; inp.value = max; rng.max = max; rng.value = max;
  byId('amount-title').textContent = t('inv.amount') + ' (1 – ' + max + ')';
  byId('amount').classList.remove('hidden'); inp.focus(); inp.select();
}
function closeAmount() { byId('amount').classList.add('hidden'); amountCb = null; }
byId('amount-input').oninput = () => { byId('amount-range').value = byId('amount-input').value; };
byId('amount-range').oninput = () => { byId('amount-input').value = byId('amount-range').value; };
byId('amount-ok').onclick = () => { const v = Math.max(1, Math.min(+byId('amount-input').max, parseInt(byId('amount-input').value, 10) || 1)); const cb = amountCb; closeAmount(); if (cb) cb(v); };
byId('amount-cancel').onclick = closeAmount;

// ── Search filter ──
function applyFilter(inv) {
  const box = byId(inv === 'player' ? 'player-search' : 'sec-search'); if (!box) return;
  const q = (box.value || '').trim().toLowerCase();
  const gid = inv === 'player' ? 'grid-player' : 'grid-secondary';
  byId(gid).querySelectorAll('.slot').forEach(el => {
    if (!q) { el.classList.remove('filtered-out'); return; }
    const it = itemAt(el.dataset.inv, +el.dataset.slot);
    const hit = it && ((def(it.name).label || '').toLowerCase().includes(q) || it.name.toLowerCase().includes(q));
    el.classList.toggle('filtered-out', !hit);
  });
}
let fdeb;
byId('player-search').oninput = () => { clearTimeout(fdeb); fdeb = setTimeout(() => applyFilter('player'), 60); };
byId('sec-search').oninput = () => { clearTimeout(fdeb); fdeb = setTimeout(() => applyFilter('secondary'), 60); };

// ── Double-click to use ──
function onDblClick(e) {
  const el = e.target.closest('.slot'); if (!el || el.dataset.inv !== 'player' || !el.hasAttribute('data-item')) return;
  const it = itemAt('player', +el.dataset.slot); if (it && def(it.name).usable == 1) post('use', { slot: +el.dataset.slot }).then(applyState);
}

// ── Wire delegated listeners once ──
function wire() {
  ['grid-player', 'grid-secondary', 'hotbar'].forEach(id => {
    const g = byId(id);
    g.addEventListener('dragstart', onDragStart);
    g.addEventListener('dragover', onDragOver);
    g.addEventListener('drop', onDrop);
    g.addEventListener('dragend', onDragEnd);
    g.addEventListener('dblclick', onDblClick);
    g.addEventListener('contextmenu', onContext);
    g.addEventListener('mouseover', onHover);
    g.addEventListener('mouseout', hideTooltip);
  });
  const w = byId('wallet');
  w.addEventListener('dragstart', onDragStart);
  w.addEventListener('dragover', onDragOver);
  w.addEventListener('drop', onDrop);
  w.addEventListener('dragend', onDragEnd);
  w.addEventListener('contextmenu', onContext);
  document.addEventListener('mousedown', (e) => { if (!e.target.closest('#context')) closeContext(); });
  document.addEventListener('scroll', closeContext, true);
}

function close() { byId('v-root').classList.add('hidden'); hideTooltip(); closeContext(); closeAmount(); post('close'); }
document.addEventListener('keydown', (e) => {
  if (byId('v-root').classList.contains('hidden')) return;
  if (e.key === 'Escape') { if (!byId('amount').classList.contains('hidden')) closeAmount(); else close(); }
});

// ── Messages from Lua ──
window.addEventListener('message', (e) => {
  const d = e.data || {};
  if (d.action === 'open') {
    state = d.state; strings = d.strings || {}; defs = state.defs || {};
    if (!built) { wire(); built = true; }
    buildGrid('grid-player', 'player', state.maxSlots || 40);
    buildHotbar(state.hotbar || 5);
    if (state.secondary) buildGrid('grid-secondary', 'secondary', state.secondary.maxSlots || 30);
    byId('player-search').value = ''; byId('sec-search').value = '';
    applyStrings(); render();
    byId('v-root').classList.remove('hidden');
  } else if (d.action === 'close') {
    byId('v-root').classList.add('hidden'); closeContext(); closeAmount();
  } else if (d.action === 'cash') {
    if (state) { state.player.cash = d.cash; byId('wallet-amt').textContent = money(d.cash); }
  }
});
