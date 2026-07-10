// v-crafting — workbench UI (recipe list; each row shows owned/required materials + a craft action)
const byId = (id) => document.getElementById(id);
const post = (n, b) => fetch(`https://v-crafting/${n}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(b || {}) }).then(r => r.json()).catch(() => false);

const CAT = { food: '#4E8C5A', drinks: '#2F6F9E', medical: '#C2362F', weapons: '#6B6156', tools: '#C98A2B',
  materials: '#B0895E', ingredients: '#7FB86B', tech: '#2F6F9E', misc: '#FF6A1A' };
const RARITY = { common: '#6B6156', uncommon: '#4E8C5A', rare: '#2F6F9E', epic: '#8A4BD1', legendary: '#FF6A1A', mythic: '#C2362F' };
const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const IMG = (f) => `https://cfx-nui-v-inventory/html/images/${esc(f)}`;
const BOX = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linejoin="round"><path d="M3 7l9-4 9 4v10l-9 4-9-4V7Z"/><path d="M3 7l9 4 9-4M12 11v10"/></svg>';

let strings = {}, station = null;
const t = (k) => strings[k] || k;
const applyStrings = () => document.querySelectorAll('[data-i18n]').forEach(el => { el.textContent = t(el.getAttribute('data-i18n')); });

function close() { byId('craft').classList.add('hidden'); post('close'); }
byId('close').onclick = close;
document.addEventListener('keydown', (e) => { if (e.key === 'Escape' && !byId('craft').classList.contains('hidden')) close(); });

// A recipe is craftable when every input's owned count covers need × amount.
function craftableQty(r) {
  let max = Infinity;
  r.inputs.forEach(i => { max = Math.min(max, Math.floor(i.have / i.need)); });
  return max === Infinity ? 0 : max;
}

function thumb(image, cls) {
  return image ? `<div class="thumb ${cls}" style="background-image:url('${IMG(image)}')"></div>`
               : `<div class="thumb ${cls} ph">${BOX}</div>`;
}

function renderList() {
  const list = byId('list'); list.innerHTML = '';
  station.recipes.forEach((r, i) => {
    const maxQty = craftableQty(r);
    const can = maxQty > 0;
    const row = document.createElement('div');
    row.className = 'row' + (can ? '' : ' locked');
    row.dataset.idx = r.idx;
    row.style.setProperty('--cat', RARITY[r.rarity] || CAT[r.category] || CAT.misc);
    row.style.setProperty('--i', i);

    const mats = r.inputs.map(m => {
      const ok = m.have >= m.need;
      return `<span class="mat ${ok ? '' : 'short'}" title="${esc(m.label)}">` +
        (m.image ? `<i class="mi" style="background-image:url('${IMG(m.image)}')"></i>` : `<i class="mi ph">${BOX}</i>`) +
        `<b>${m.have}</b>/${m.need}</span>`;
    }).join('');

    row.innerHTML =
      thumb(r.image, 'out') +
      `<div class="info">` +
        `<div class="top"><span class="name">${esc(r.label)}</span>${r.count > 1 ? `<span class="mk">×${r.count}</span>` : ''}</div>` +
        `<div class="mats">${mats}</div>` +
      `</div>` +
      `<div class="act">` +
        `<div class="stepper"><button class="step dec" aria-label="Decrease">−</button><span class="qty">1</span><button class="step inc" aria-label="Increase">+</button></div>` +
        `<button class="mk-btn" ${can ? '' : 'disabled'} data-i18n="craft.make">Craft</button>` +
      `</div>` +
      `<div class="bar"><i></i></div>`;

    const qtyEl = row.querySelector('.qty');
    const cap = () => Math.max(1, craftableQty(r));  // recompute (counts change after a craft)
    row.querySelector('.dec').onclick = () => { qtyEl.textContent = Math.max(1, (+qtyEl.textContent) - 1); };
    row.querySelector('.inc').onclick = () => { qtyEl.textContent = Math.min(cap(), (+qtyEl.textContent) + 1); };
    row.querySelector('.mk-btn').onclick = () => make(row, r, +qtyEl.textContent);
    list.appendChild(row);
  });
  applyStrings();
}

let busy = false;
async function make(row, r, amount) {
  if (busy) return;
  amount = Math.max(1, Math.min(craftableQty(r), amount));
  if (amount < 1) return;
  busy = true;
  row.classList.add('working');
  const bar = row.querySelector('.bar > i');
  // Client progress bar for feel; the server is the real authority on completion.
  bar.style.transition = 'none'; bar.style.width = '0%';
  void bar.offsetWidth;
  bar.style.transition = `width ${r.time}ms linear`; bar.style.width = '100%';
  await new Promise(res => setTimeout(res, r.time));

  const resp = await post('craft', { station: station.id, idx: r.idx, amount });
  row.classList.remove('working');
  bar.style.transition = 'none'; bar.style.width = '0%';
  busy = false;
  if (resp && resp.recipes) { station.recipes = resp.recipes; renderList(); }
}

window.addEventListener('message', (e) => {
  const d = e.data || {};
  if (d.action === 'open') {
    strings = d.strings || {}; station = d.station;
    byId('station-label').textContent = station.label;
    renderList();
    byId('craft').classList.remove('hidden');
  } else if (d.action === 'close') {
    byId('craft').classList.add('hidden');
  }
});
