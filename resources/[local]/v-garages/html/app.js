// v-garages — garage panel
const byId = (id) => document.getElementById(id);
const post = (n, b) => fetch(`https://v-garages/${n}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(b || {}) }).then(r => r.json()).catch(() => false);
const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const fmt = (n) => '$' + Math.floor(Number(n) || 0).toLocaleString('en-US');

let strings = {}, state = {};
const t = (k) => strings[k] || k;

function applyStrings() {
  document.querySelectorAll('[data-i18n]').forEach(el => { el.textContent = t(el.getAttribute('data-i18n')); });
}

// engine/body are 0..1000 in GTA; show them as a percentage bar
const pct = (v, max) => Math.max(0, Math.min(100, Math.round((Number(v) || 0) / max * 100)));

function bar(label, value) {
  // the fill must carry v-progress__fill — a bare child gets no background from the theme
  return `<span class="stat"><span class="slbl">${esc(label)}</span>
    <span class="v-progress"><i class="v-progress__fill" style="width:${value}%"></i></span>
    <span class="sval">${value}%</span></span>`;
}

function render() {
  const g = state.garage || {};
  byId('gtitle').textContent = g.label || t('gar.title');

  const fee = Number(g.fee) || 0;
  const fr = byId('feerow');
  fr.classList.toggle('hidden', !(g.type === 'impound' && fee > 0));
  fr.innerHTML = `<span class="flbl">${esc(t('gar.fee'))}</span><span class="fval">${fmt(fee)}</span>`;

  const wrap = byId('list'); wrap.innerHTML = '';
  const rows = state.rows || [];
  if (!rows.length) { wrap.innerHTML = `<div class="empty">${esc(t('gar.empty'))}</div>`; return; }

  rows.forEach((r, i) => {
    const el = document.createElement('div');
    el.className = 'vrow'; el.style.setProperty('--i', i);
    el.innerHTML = `
      <span class="vinfo">
        <span class="vname">${esc(r.model)}</span>
        <span class="vplate">${esc(r.plate)}</span>
        <span class="vstats">
          ${bar(t('gar.fuel'), pct(r.fuel, 100))}
          ${bar(t('gar.engine'), pct(r.engine, 1000))}
          ${bar(t('gar.body'), pct(r.body, 1000))}
        </span>
      </span>
      <button class="mini accent vtake">${esc(t('gar.take'))}</button>`;
    el.querySelector('.vtake').onclick = async (e) => {
      const b = e.currentTarget; b.disabled = true;
      const res = await post('take', { plate: r.plate });
      if (!res || !res.ok) {
        b.textContent = t('gar.err_' + ((res && res.error) || 'x'));
        b.classList.add('ko');
        setTimeout(() => { b.textContent = t('gar.take'); b.classList.remove('ko'); b.disabled = false; }, 1800);
      }
    };
    wrap.appendChild(el);
  });
}

byId('close').onclick = () => post('close');
document.addEventListener('keyup', (e) => {
  if (e.key === 'Escape' && !byId('gar').classList.contains('hidden')) post('close');
});

window.addEventListener('message', (e) => {
  const d = e.data || {};
  if (d.action === 'open') {
    strings = d.strings || {}; state = d.data || {};
    applyStrings(); render();
    byId('gar').classList.remove('hidden');
  } else if (d.action === 'data') {
    state = d.data || {}; render();
  } else if (d.action === 'close') {
    byId('gar').classList.add('hidden');
  }
});
