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
const RARITY = { common: '#9C99A2', uncommon: '#43C46A', rare: '#4AA8FF', epic: '#C77DFF', legendary: '#F5A623', mythic: '#E5484D' };
const ICONS = {
  use:    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M13 2 4 14h6l-1 8 9-12h-6l1-8Z"/></svg>',
  give:   '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12h14M13 6l6 6-6 6"/></svg>',
  split:  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><circle cx="6" cy="6" r="3"/><circle cx="6" cy="18" r="3"/><path d="M20 4 8.12 15.88M14.47 14.48 20 20M8.12 8.12 12 12"/></svg>',
  drop:   '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6"/></svg>',
  rename: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 20h9M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4Z"/></svg>',
};

// Equipment (clothing body slots) — cats match v-clothing categories.
const EQ = [
  { group: 'inv.eq.head', slots: ['masks', 'hats', 'glasses'] },
  { group: 'inv.eq.body', slots: ['tops', 'undershirt', 'arms', 'pants', 'shoes'] },
];
const EQ_IC = {
  masks: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6"><path d="M4 8c0-2 3-3 8-3s8 1 8 3v3c0 4-4 8-8 8s-8-4-8-8Z"/><path d="M9 11h.01M15 11h.01"/></svg>',
  hats: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6"><path d="M4 16h16M6 16c0-4 1-9 6-9s6 5 6 9"/></svg>',
  glasses: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6"><circle cx="6" cy="14" r="3"/><circle cx="18" cy="14" r="3"/><path d="M9 13c1-1 5-1 6 0M3 11l2-2M21 11l-2-2"/></svg>',
  tops: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6"><path d="M8 3 4 6l2 3 1-1v12h10V8l1 1 2-3-4-3-3 2Z"/></svg>',
  undershirt: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6"><path d="M8 3 5 6l2 2v13h10V8l2-2-3-3-2 2H10Z"/></svg>',
  arms: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6"><path d="M8 2v6a4 4 0 0 0 8 0V2M9 12v9h6v-9"/></svg>',
  pants: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6"><path d="M6 3h12l-1 18h-4l-1-9-1 9H6Z"/></svg>',
  shoes: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6"><path d="M2 16h13l5 2v2H2ZM5 16V9l4-1 2 3 4 1"/></svg>',
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
  el.innerHTML = '<span class="info"></span><span class="hk"></span><span class="scrim"></span><span class="label"></span><i class="dura"></i>';
  return el;
}
function buildGrid(gridId, inv, count, start) {
  const g = byId(gridId); g.innerHTML = '';
  for (let s = (start || 1); s <= count; s++) g.appendChild(slotEl(inv, s));
}
function buildQuickbar(n) {
  const h = byId('quickbar'); h.innerHTML = '';
  for (let s = 1; s <= n; s++) { const el = slotEl('player', s); el.dataset.hot = s; h.appendChild(el); }
}
function buildSegs(id, n) {
  const b = byId(id); b.innerHTML = '';
  for (let i = 0; i < n; i++) { const s = document.createElement('span'); s.className = 'seg'; b.appendChild(s); }
}

// ── Render ──
function rarityOf(d) { return (d.metadata && d.metadata.rarity) || 'common'; }
function itemLabel(it, d) { return (it.metadata && it.metadata.label) || d.label || it.name; }

function renderSlot(el) {
  const inv = el.dataset.inv, slot = +el.dataset.slot;
  const it = itemAt(inv, slot);
  const info = el.querySelector('.info'); const label = el.querySelector('.label'); const hk = el.querySelector('.hk'); const dura = el.querySelector('.dura');
  hk.textContent = el.dataset.hot || '';
  dura.className = 'dura';
  if (!it) {
    el.removeAttribute('data-item'); el.removeAttribute('data-rar'); el.draggable = false;
    el.style.backgroundImage = ''; el.style.removeProperty('--cat');
    info.innerHTML = ''; label.textContent = ''; return;
  }
  const d = def(it.name); const rar = rarityOf(d);
  el.setAttribute('data-item', it.name); el.setAttribute('data-rar', rar); el.draggable = true;
  el.style.setProperty('--cat', RARITY[rar] || CAT[d.category] || 'var(--v-accent)');
  el.style.backgroundImage = d.image ? `url("images/${d.image}")` : '';
  const tot = ((d.weight || 0) * it.amount) / 1000;
  info.innerHTML = `<b>${it.amount}</b><span>(${tot.toFixed(1)})</span>`;
  label.textContent = itemLabel(it, d);
  const dur = it.metadata && it.metadata.durability;
  if (dur != null) { dura.classList.add('on'); dura.style.width = Math.max(0, Math.min(100, dur)) + '%'; dura.style.background = dur > 55 ? 'var(--v-success)' : dur > 25 ? 'var(--v-accent)' : 'var(--v-danger)'; }
}
function renderGrid(inv) {
  const gid = inv === 'player' ? 'grid-player' : 'grid-secondary';
  byId(gid).querySelectorAll('.slot').forEach(renderSlot);
  if (inv === 'player') byId('quickbar').querySelectorAll('.slot').forEach(renderSlot);
}
function setWeight(prefix, w, max) {
  const segs = byId(prefix + '-seg').querySelectorAll('.seg');
  const on = max > 0 ? Math.round(Math.min(1, w / max) * segs.length) : 0;
  segs.forEach((s, i) => s.classList.toggle('on', i < on));
  byId(prefix + '-seg').classList.toggle('over', w > max);
  byId(prefix + '-wtxt').textContent = (w / 1000).toFixed(2) + ' / ' + (max / 1000).toFixed(2);
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
  // equipment shows on the right when no container is open
  byId('panel-equipment').classList.toggle('hidden', !!sec || !state.equipment);
  if (!sec && state.equipment) renderEquipment();
  applyFilter('player'); applyFilter('secondary');
}

function applyState(s) { if (!s || s.error) return; state = s; render(); }

// ── Equipment (body slots) ──
function buildEquipment() {
  const wrap = byId('equipment'); wrap.innerHTML = '';
  EQ.forEach(g => {
    const grp = document.createElement('div'); grp.className = 'eq-group';
    grp.innerHTML = `<span class="eq-glabel">${t(g.group)}</span>`;
    const row = document.createElement('div'); row.className = 'eq-slots';
    g.slots.forEach(cat => {
      const el = document.createElement('div'); el.className = 'eqslot'; el.dataset.cat = cat;
      el.innerHTML = `<span class="eq-ic">${EQ_IC[cat] || ''}</span><span class="eq-name"></span>`;
      row.appendChild(el);
    });
    grp.appendChild(row); wrap.appendChild(grp);
  });
}
function renderEquipment() {
  const eq = state.equipment || {};
  byId('equipment').querySelectorAll('.eqslot').forEach(el => {
    const worn = eq[el.dataset.cat]; const nameEl = el.querySelector('.eq-name');
    if (worn) { el.classList.add('on'); nameEl.textContent = def(worn.item).label || worn.item; }
    else { el.classList.remove('on'); nameEl.textContent = ''; }
  });
}

// ── Drag & drop (delegated) ──
function onDragStart(e) {
  const el = e.target.closest('.slot,.wallet-chip'); if (!el) return;
  if (el.id === 'wallet') { drag = { inv: 'wallet', slot: 'money', money: true }; el.classList.add('dragging'); return; }
  if (!el.hasAttribute('data-item')) { e.preventDefault(); return; }
  drag = { inv: el.dataset.inv, slot: +el.dataset.slot };
  e.dataTransfer.effectAllowed = 'move'; e.dataTransfer.setData('text', el.dataset.slot);
  el.classList.add('dragging');
}
function onDragOver(e) {
  const el = e.target.closest('.slot,.wallet-chip'); if (!el || !drag) return;
  e.preventDefault();
  const cur = document.querySelector('.drop-hover'); if (cur && cur !== el) cur.classList.remove('drop-hover');
  el.classList.add('drop-hover');
}
function onDragEnd() {
  document.querySelectorAll('.dragging,.drop-hover').forEach(el => el.classList.remove('dragging', 'drop-hover'));
  drag = null;
}

// ── Equipment drag/equip/unequip ──
function onEqOver(e) {
  const el = e.target.closest('.eqslot'); if (!el || !drag || drag.money || drag.inv !== 'player') return;
  const it = itemAt('player', drag.slot); if (!it || def(it.name).category !== 'clothing') return;
  e.preventDefault();
  const cur = document.querySelector('.eqslot.drop-hover'); if (cur && cur !== el) cur.classList.remove('drop-hover');
  el.classList.add('drop-hover');
}
async function onEqDrop(e) {
  const el = e.target.closest('.eqslot'); if (!el || !drag) return;
  e.preventDefault();
  const from = drag; onDragEnd();
  if (from.money || from.inv !== 'player') return;
  const it = itemAt('player', from.slot); if (!it || def(it.name).category !== 'clothing') return;
  applyState(await post('use', { slot: from.slot }));   // using a clothing item equips it (v-clothing)
}
function onEqContext(e) {
  const el = e.target.closest('.eqslot'); if (!el) return;
  e.preventDefault();
  const cat = el.dataset.cat; const worn = (state.equipment || {})[cat]; if (!worn) return;
  const menu = byId('context'); menu.innerHTML = '';
  const li = document.createElement('li'); li.className = 'danger';
  li.innerHTML = `<span class="ci">${ICONS.give}</span><span>${t('inv.unequip')}</span>`;
  li.onclick = async () => { closeContext(); applyState(await post('unequipCloth', { cat })); };
  menu.appendChild(li);
  menu.classList.remove('hidden'); positionFloat(menu, e.clientX, e.clientY);
}
async function onDrop(e) {
  const el = e.target.closest('.slot,.wallet-chip'); if (!el || !drag) return;
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
  const d = def(it.name); const dm = d.metadata || {}; const im = it.metadata || {};
  const rar = rarityOf(d);
  const row = (k, v) => `<div class="row"><span>${k}</span><b>${v}</b></div>`;
  tt.innerHTML = `<div class="tt-top" style="border-left:3px solid ${RARITY[rar] || 'var(--v-line)'}"><div class="tt-img" style="background-image:url('images/${esc(d.image)}')"></div>`
    + `<div><h4>${esc(itemLabel(it, d))}</h4><div class="sub">${esc(it.name)} · <em style="color:${RARITY[rar]}">${t('rar.' + rar)}</em></div></div></div>`
    + `<div class="tt-body">${row(t('inv.weight'), kg((d.weight || 0) * it.amount))}`
    + (it.amount > 1 ? row(t('inv.qty'), it.amount) : '')
    + (im.serial ? row(t('inv.serial'), esc(im.serial)) : '')
    + (im.ammo != null ? row(t('inv.ammo'), im.ammo) : '')
    + (im.durability != null ? row(t('inv.durability'), Math.round(im.durability) + '%') : '')
    + (dm.desc ? `<div class="desc">${esc(dm.desc)}</div>` : '') + `</div>`;
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
  const el = e.target.closest('.slot,.wallet-chip'); if (!el) return;
  e.preventDefault();
  hideTooltip();
  const menu = byId('context'); menu.innerHTML = '';
  const add = (icon, label, fn, danger) => {
    const li = document.createElement('li'); if (danger) li.className = 'danger';
    li.innerHTML = `<span class="ci">${ICONS[icon] || ''}</span><span>${esc(label)}</span>`;
    li.onclick = () => { closeContext(); fn(); }; menu.appendChild(li);
  };
  if (el.id === 'wallet') {
    if ((state.player.cash || 0) <= 0) return;
    add('give', t('inv.give'), giveMoney);
    add('drop', t('inv.drop'), dropMoney, true);
  } else {
    if (!el.hasAttribute('data-item')) return;
    const inv = el.dataset.inv, slot = +el.dataset.slot;
    const it = itemAt(inv, slot); if (!it) return; const d = def(it.name);
    if (inv === 'player' && d.usable == 1) add('use', t('inv.use'), async () => applyState(await post('use', { slot })));
    if (inv === 'player') add('give', t('inv.give'), () => giveItem(slot, it.amount));
    if (it.amount > 1) add('split', t('inv.split'), () => showAmount(it.amount, async (amt) => applyState(await post('move', { from: inv, fromSlot: slot, to: inv, amount: amt }))));
    if (it.name !== 'money') add('rename', t('inv.rename'), () => showRename(itemLabel(it, d), inv, slot));
    if (inv === 'player') add('drop', t('inv.drop'), () => dropItem(inv, slot, it.amount), true);
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

// ── Rename ──
let renameCtx = null;
function showRename(current, inv, slot) {
  renameCtx = { inv, slot };
  const inp = byId('rename-input'); inp.value = current || '';
  byId('rename').classList.remove('hidden'); inp.focus(); inp.select();
}
function closeRename() { byId('rename').classList.add('hidden'); renameCtx = null; }
byId('rename-ok').onclick = async () => { const name = byId('rename-input').value.trim(); const ctx = renameCtx; closeRename(); if (ctx) applyState(await post('rename', { inv: ctx.inv, slot: ctx.slot, name })); };
byId('rename-cancel').onclick = closeRename;
byId('rename-input').addEventListener('keydown', (e) => { if (e.key === 'Enter') byId('rename-ok').click(); });

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
  ['grid-player', 'grid-secondary', 'quickbar'].forEach(id => {
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
  const eq = byId('equipment');
  eq.addEventListener('dragover', onEqOver);
  eq.addEventListener('drop', onEqDrop);
  eq.addEventListener('contextmenu', onEqContext);
  document.addEventListener('mousedown', (e) => { if (!e.target.closest('#context')) closeContext(); });
  document.addEventListener('scroll', closeContext, true);
}

function close() { byId('v-root').classList.add('hidden'); hideTooltip(); closeContext(); closeAmount(); closeRename(); post('close'); }
document.addEventListener('keydown', (e) => {
  if (byId('v-root').classList.contains('hidden')) return;
  if (e.key === 'Escape') {
    if (!byId('amount').classList.contains('hidden')) closeAmount();
    else if (!byId('rename').classList.contains('hidden')) closeRename();
    else close();
  }
});

// ── Messages from Lua ──
window.addEventListener('message', (e) => {
  const d = e.data || {};
  if (d.action === 'open') {
    state = d.state; strings = d.strings || {}; defs = state.defs || {};
    if (!built) { wire(); built = true; }
    buildEquipment();
    const hb = state.hotbar || 5;
    buildQuickbar(hb);
    buildGrid('grid-player', 'player', state.maxSlots || 40, hb + 1);   // main grid = slots after the quick slots
    buildSegs('player-seg', 12);
    if (state.secondary) { buildGrid('grid-secondary', 'secondary', state.secondary.maxSlots || 30, 1); buildSegs('sec-seg', 12); }
    byId('player-search').value = ''; byId('sec-search').value = '';
    applyStrings(); render();
    byId('v-root').classList.remove('hidden');
  } else if (d.action === 'close') {
    byId('v-root').classList.add('hidden'); closeContext(); closeAmount();
  } else if (d.action === 'cash') {
    if (state) { state.player.cash = d.cash; byId('wallet-amt').textContent = money(d.cash); }
  }
});
