// v-inventory — grid inventory UI
const byId = (id) => document.getElementById(id);
const post = (name, body) => fetch(`https://v-inventory/${name}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body || {}) }).then(r => r.json()).catch(() => false);

const CAT = { food: '#43C46A', medical: '#E5484D', weapon: '#9C99A2', tool: '#F5A623', gadget: '#4AA8FF', money: '#43C46A', misc: '#FF6A1A' };
let strings = {};
let state = null;
let sel = null;          // { container, slot }
let dragSrc = null;      // { container, slot }

const t = (k) => strings[k] || k;
const applyStrings = () => document.querySelectorAll('[data-i18n]').forEach(el => { el.textContent = t(el.getAttribute('data-i18n')); });
const kg = (g) => (Math.round((g / 1000) * 10) / 10);
const def = (name) => (state && state.defs && state.defs[name]) || {};

function itemInContainer(container, slot) {
  const items = container === 'player' ? state.player.items : (state.secondary ? state.secondary.items : []);
  return items.find(it => it.slot === slot) || null;
}

function renderGrid(gridEl, container, items, maxSlots) {
  gridEl.innerHTML = '';
  const bySlot = {};
  items.forEach(it => { bySlot[it.slot] = it; });
  for (let s = 1; s <= maxSlots; s++) {
    const slot = document.createElement('div');
    slot.className = 'slot';
    slot.dataset.container = container;
    slot.dataset.slot = s;
    slot.addEventListener('dragover', (e) => { e.preventDefault(); slot.classList.add('drop-hover'); });
    slot.addEventListener('dragleave', () => slot.classList.remove('drop-hover'));
    slot.addEventListener('drop', (e) => { e.preventDefault(); slot.classList.remove('drop-hover'); onDrop(container, s); });

    const it = bySlot[s];
    if (it) {
      const d = def(it.name);
      const cat = CAT[d.category] || CAT.misc;
      const el = document.createElement('div');
      el.className = 'item' + (sel && sel.container === container && sel.slot === s ? ' selected' : '');
      el.style.setProperty('--cat', cat);
      el.draggable = true;
      el.innerHTML = `<span class="cat-dot"></span><span class="amt">${it.amount}</span><span class="name">${(d.label || it.name)}</span>`;
      el.addEventListener('dragstart', () => { dragSrc = { container, slot: s }; });
      el.addEventListener('click', () => selectItem(container, s));
      slot.appendChild(el);
    }
    gridEl.appendChild(slot);
  }
}

function renderWeight(fillEl, txtEl, weight, maxWeight) {
  const pct = Math.min(100, (weight / maxWeight) * 100);
  fillEl.style.width = pct + '%';
  fillEl.parentElement.classList.toggle('over', weight > maxWeight);
  txtEl.textContent = kg(weight) + ' / ' + kg(maxWeight) + ' kg';
}

function render() {
  if (!state) return;
  renderGrid(byId('grid-player'), 'player', state.player.items, state.maxSlots);
  renderWeight(byId('pw-fill'), byId('pw-txt'), state.player.weight, state.maxWeight);

  const sec = state.secondary;
  byId('col-secondary').classList.toggle('hidden', !sec);
  if (sec) {
    byId('sec-label').textContent = t(sec.label) || sec.label;
    let sw = 0; sec.items.forEach(it => { sw += (def(it.name).weight || 0) * it.amount; });
    renderGrid(byId('grid-secondary'), 'secondary', sec.items, 50);
    renderWeight(byId('sw-fill'), byId('sw-txt'), sw, sec.maxWeight);
  }
  renderActions();
}

function selectItem(container, slot) {
  sel = { container, slot };
  render();
}

function renderActions() {
  const bar = byId('actions');
  const it = sel ? itemInContainer(sel.container, sel.slot) : null;
  if (!it || sel.container !== 'player') { bar.classList.add('hidden'); return; }
  bar.classList.remove('hidden');
  const d = def(it.name);
  byId('sel-info').innerHTML = `<b>${d.label || it.name}</b> × ${it.amount}`;
  const amt = byId('amt');
  amt.max = it.amount; amt.value = Math.min(amt.value, it.amount) || 1;
  byId('amt-val').textContent = amt.value;
  byId('act-use').disabled = d.usable !== 1;
}

async function doAction(name, body) {
  const res = await post(name, body);
  if (res && res.player) { state = res; sel = null; render(); }
}

async function onDrop(toContainer, toSlot) {
  if (!dragSrc) return;
  const src = dragSrc; dragSrc = null;
  if (src.container === toContainer && src.slot === toSlot) return;
  const res = await post('move', { from: src.container, to: toContainer, fromSlot: src.slot, toSlot: toSlot });
  if (res && res.player) { state = res; render(); }
}

// ── Buttons / close ──  (#inv is the full-screen overlay)
const overlay = () => byId('inv');
function closeInv() { overlay().classList.add('hidden'); post('close'); }

byId('amt').oninput = () => { byId('amt-val').textContent = byId('amt').value; };
byId('act-use').onclick = () => { if (sel) doAction('use', { slot: sel.slot }); };
byId('act-give').onclick = () => { if (sel) doAction('give', { slot: sel.slot, amount: +byId('amt').value }); };
byId('act-drop').onclick = () => { if (sel) doAction('drop', { slot: sel.slot, amount: +byId('amt').value }); };
byId('inv-close').onclick = closeInv;
document.addEventListener('keydown', (e) => {
  if ((e.key === 'Escape' || e.key === 'F2') && !overlay().classList.contains('hidden')) closeInv();
});

// ── Messages from Lua ──
window.addEventListener('message', (event) => {
  const d = event.data || {};
  if (d.action === 'open') {
    strings = d.strings || {};
    state = d.state; sel = null;
    applyStrings();
    render();
    overlay().classList.remove('hidden');
  } else if (d.action === 'close') {
    overlay().classList.add('hidden');
  }
});
