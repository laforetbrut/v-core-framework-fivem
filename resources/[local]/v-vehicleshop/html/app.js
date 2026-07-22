// v-vehicleshop — dealership panel
const byId = (id) => document.getElementById(id);
const post = (n, b) => fetch(`https://v-vehicleshop/${n}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(b || {}) }).then(r => r.json()).catch(() => false);
const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const fmt = (n) => '$' + Math.floor(Number(n) || 0).toLocaleString('en-US');

let strings = {}, state = {}, mine = null;
let tab = 'buy', cat = null, picked = null, dragging = false;
const t = (k) => strings[k] || k;
const acct = () => (byId('sacct-bank').checked ? 'bank' : 'cash');

const ERR = { far: 'shop.err_far', nojob: 'shop.err_nojob', notsold: 'shop.err_notsold',
              nostock: 'shop.err_nostock', nolicense: 'shop.err_nolicense', funds: 'shop.err_funds',
              busy: 'shop.err_busy', notyours: 'shop.err_notyours', stillout: 'shop.err_stillout' };

function applyStrings() {
  document.querySelectorAll('[data-i18n]').forEach(el => { el.textContent = t(el.getAttribute('data-i18n')); });
}

function rowsOfTab() {
  if (tab === 'sell') return (mine && mine.rows) || [];
  const rows = state.rows || [];
  return cat ? rows.filter(r => r.cat === cat) : rows;
}

function renderCats() {
  const box = byId('cats');
  box.classList.toggle('hidden', tab !== 'buy');
  if (tab !== 'buy') return;
  const cats = state.cats || [];
  box.innerHTML = [`<button class="cbtn${cat ? '' : ' on'}" data-c="">${esc(t('shop.all'))}</button>`]
    .concat(cats.map(c => `<button class="cbtn${cat === c ? ' on' : ''}" data-c="${esc(c)}">${esc(t('shop.cat_' + c))}</button>`))
    .join('');
  box.querySelectorAll('.cbtn').forEach(b => {
    b.onclick = () => { cat = b.dataset.c || null; picked = null; post('preview', {}); render(); };
  });
}

function renderList() {
  const wrap = byId('list'); wrap.innerHTML = '';
  const rows = rowsOfTab();
  if (!rows.length) {
    wrap.innerHTML = `<div class="empty">${esc(t(tab === 'sell' ? 'shop.nocars' : 'shop.empty'))}</div>`;
    return;
  }

  rows.forEach((r, i) => {
    const el = document.createElement('div');
    const key = tab === 'sell' ? r.plate : r.model;
    el.className = 'crow' + (picked === key ? ' on' : '');
    el.style.setProperty('--i', i);

    if (tab === 'sell') {
      el.innerHTML = `
        <span class="cinfo">
          <span class="cname">${esc(r.label)}</span>
          <span class="cmeta">${esc(r.plate)} · ${esc(t('shop.condition'))} ${r.condition}%</span>
        </span>
        <span class="cprice">${fmt(r.payout)}</span>`;
    } else {
      // a car you cannot legally buy still shows: the missing licence is the information
      const blocked = !r.hasLicense || !r.jobOk;
      el.classList.toggle('blocked', blocked);
      const why = !r.jobOk ? t('shop.needjob') + ' ' + esc(r.job)
                : !r.hasLicense ? t('shop.needlic') + ' ' + esc(t('lic.' + r.license)) : '';
      el.innerHTML = `
        <span class="cinfo">
          <span class="cname">${esc(r.label)}</span>
          <span class="cmeta">${esc(t('shop.cat_' + r.cat))}${r.stock > 0 ? ' · ' + r.stock + ' ' + esc(t('shop.instock')) : ''}${why ? ' · <b class="warn">' + why + '</b>' : ''}</span>
        </span>
        <span class="cprice">${fmt(r.price)}</span>`;
    }

    el.onclick = () => {
      picked = (picked === key) ? null : key;
      if (tab === 'buy') post('preview', picked ? { model: r.model } : {});
      render();
    };
    wrap.appendChild(el);
  });
}

function renderFoot() {
  const rows = rowsOfTab();
  const sel = rows.find(r => (tab === 'sell' ? r.plate : r.model) === picked);
  const buyBtn = byId('buy'), testBtn = byId('test');
  testBtn.classList.toggle('hidden', tab !== 'buy');
  if (tab === 'sell') {
    buyBtn.textContent = t('shop.sellback');
    buyBtn.disabled = !sel;
  } else {
    buyBtn.textContent = t('shop.buy');
    buyBtn.disabled = !sel || !sel.hasLicense || !sel.jobOk;
    testBtn.disabled = !sel;
  }
}

function render() {
  // the panel title is the dealership you are standing in, not the generic word
  byId('stitle').textContent = (state.dealer && state.dealer.label) || t('shop.blip');
  renderCats(); renderList(); renderFoot();
}

function setTab(next) {
  tab = next; picked = null; post('preview', {});
  document.querySelectorAll('.stab').forEach(b => b.classList.toggle('on', b.dataset.t === tab));
  if (tab === 'sell' && !mine) { post('mine').then(res => { mine = res || { rows: [] }; render(); }); }
  render();
}

document.querySelectorAll('.stab').forEach(b => { b.onclick = () => setTab(b.dataset.t); });

// Drag the clear half of the screen to orbit the car, wheel to zoom.
const stage = byId('stage');
stage.addEventListener('mousedown', () => { dragging = true; });
window.addEventListener('mouseup', () => { dragging = false; });
window.addEventListener('mousemove', (e) => {
  if (dragging && picked && tab === 'buy') post('previewRotate', { dx: e.movementX });
});
stage.addEventListener('wheel', (e) => {
  if (picked && tab === 'buy') post('previewZoom', { dz: e.deltaY > 0 ? -1 : 1 });
});

byId('test').onclick = () => { if (picked && tab === 'buy') post('test', { model: picked }); };

byId('buy').onclick = async (e) => {
  if (!picked) return;
  const b = e.currentTarget; b.disabled = true;
  const res = tab === 'sell'
    ? await post('sell', { plate: picked })
    : await post('buy', { model: picked, account: acct() });
  if (res && res.ok) {
    picked = null; mine = null;
    if (tab === 'sell') { post('mine').then(r => { mine = r || { rows: [] }; render(); }); }
  } else {
    b.textContent = t(ERR[res && res.error] || 'shop.err_x');
    b.classList.add('ko');
    setTimeout(() => { b.classList.remove('ko'); render(); }, 1900);
  }
};

byId('close').onclick = () => post('close');
document.addEventListener('keyup', (e) => {
  if (e.key === 'Escape' && !byId('shop').classList.contains('hidden')) post('close');
});

window.addEventListener('message', (e) => {
  const d = e.data || {};
  if (d.action === 'open') {
    strings = d.strings || {}; state = d.data || {};
    mine = null; tab = 'buy'; cat = null; picked = null;
    byId('testbar').classList.add('hidden');
    applyStrings(); setTab('buy');
    byId('shop').classList.remove('hidden');
  } else if (d.action === 'data') {
    state = d.data || {}; render();
  } else if (d.action === 'testTick') {
    // the panel is closed and focus released; only the countdown shows
    byId('testbar').classList.remove('hidden');
    byId('tleft').textContent = d.left + 's';
  } else if (d.action === 'testEnd') {
    byId('testbar').classList.add('hidden');
  } else if (d.action === 'close') {
    byId('shop').classList.add('hidden');
  }
});
