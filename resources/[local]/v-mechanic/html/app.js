// v-mechanic — diagnostics & repair panel
const byId = (id) => document.getElementById(id);
const post = (n, b) => fetch(`https://v-mechanic/${n}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(b || {}) }).then(r => r.json()).catch(() => false);
const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const fmt = (n) => '$' + Math.floor(Number(n) || 0).toLocaleString('en-US');
const km = (n) => Math.floor(Number(n) || 0).toLocaleString('en-US') + ' km';

let strings = {}, state = {}, filter = 'all';
const t = (k) => strings[k] || k;
const acct = () => (byId('macct-bank').checked ? 'bank' : 'cash');

function applyStrings() {
  document.querySelectorAll('[data-i18n]').forEach(el => { el.textContent = t(el.getAttribute('data-i18n')); });
}

// A condition maps to one of four bands; the colour is the diagnosis at a glance.
function band(c) {
  if (c >= 80) return 'good';
  if (c >= 50) return 'fair';
  if (c >= 25) return 'poor';
  return 'crit';
}

function renderDash() {
  const overdue = (state.mileage - state.service) > state.interval;
  byId('mtitle').textContent = (state.shop && state.shop.label) || t('mech.title');
  byId('msub').textContent = `${state.model || ''} · ${state.plate || ''}`;
  byId('dash').innerHTML = `
    <span class="dcell"><span class="dk">${esc(t('mech.odo'))}</span><span class="dv">${km(state.mileage)}</span></span>
    <span class="dcell${overdue ? ' warn' : ''}">
      <span class="dk">${esc(t('mech.since_service'))}</span>
      <span class="dv">${km(state.mileage - state.service)}${overdue ? ' !' : ''}</span>
    </span>
    <span class="dcell"><span class="dk">${esc(t('mech.drivetrain'))}</span>
      <span class="dv">${state.ev ? esc(t('mech.electric')) : esc(t('mech.combustion'))}</span></span>
    <span class="dcell"><span class="dk">${esc(t('mech.kits'))}</span><span class="dv">${state.kit || 0}</span></span>`;
}

function renderParts() {
  const wrap = byId('plist'); wrap.innerHTML = '';
  let rows = state.parts || [];
  if (filter === 'worn') rows = rows.filter(p => p.condition < 80);
  if (!rows.length) { wrap.innerHTML = `<div class="empty">${esc(t('mech.allgood'))}</div>`; return; }

  rows.forEach((p, i) => {
    const el = document.createElement('div');
    el.className = 'prow'; el.style.setProperty('--i', i);
    const inShop = !!state.shop;
    const canReplace = inShop && p.have > 0 && p.condition < 99;
    // a field patch is deliberately limited: it tops a part up, it does not renew it
    const canPatch = !inShop && (state.kit || 0) > 0 && p.condition < 55 && p.condition >= 15;
    el.innerHTML = `
      <span class="pinfo">
        <span class="pname">${esc(t(p.i18n))} <i class="paff">${esc(t('mech.aff_' + p.affects))}</i></span>
        <span class="pbar">
          <span class="v-progress"><i class="v-progress__fill ${band(p.condition)}" style="width:${p.condition}%"></i></span>
          <span class="pval ${band(p.condition)}">${p.condition}%</span>
        </span>
        <span class="pmeta">${esc(t('mech.stock'))} <b>${p.have}</b> &middot; ${esc(t('mech.labour'))} ${fmt(p.labour)}</span>
      </span>
      <span class="pacts">
        ${inShop ? `<button class="mini accent prep"${canReplace ? '' : ' disabled'}>${esc(t('mech.replace'))}</button>` : ''}
        ${!inShop ? `<button class="mini ppatch"${canPatch ? '' : ' disabled'}>${esc(t('mech.patch'))}</button>` : ''}
      </span>`;

    const rep = el.querySelector('.prep');
    if (rep && canReplace) rep.onclick = async (e) => {
      const b = e.currentTarget; b.disabled = true;
      const res = await post('replace', { part: p.key, account: acct() });
      if (!res || !res.ok) {
        b.textContent = t('mech.err_' + ((res && res.error) || 'x'));
        b.classList.add('ko');
        setTimeout(() => { b.textContent = t('mech.replace'); b.classList.remove('ko'); b.disabled = false; }, 1800);
      }
    };
    const pat = el.querySelector('.ppatch');
    if (pat && canPatch) pat.onclick = async (e) => {
      const b = e.currentTarget; b.disabled = true;
      const res = await post('patch', { part: p.key });
      if (!res || !res.ok) {
        b.textContent = t('mech.err_' + ((res && res.error) || 'x'));
        b.classList.add('ko');
        setTimeout(() => { b.textContent = t('mech.patch'); b.classList.remove('ko'); b.disabled = false; }, 1800);
      }
    };
    wrap.appendChild(el);
  });
}

function render() {
  renderDash(); renderParts();
  byId('service').classList.toggle('hidden', !state.shop);
}

document.querySelectorAll('.fbtn').forEach(b => {
  b.onclick = () => {
    document.querySelectorAll('.fbtn').forEach(x => x.classList.remove('on'));
    b.classList.add('on'); filter = b.dataset.f; renderParts();
  };
});

byId('service').onclick = async (e) => {
  const b = e.currentTarget; b.disabled = true;
  const res = await post('service', { account: acct() });
  if (!res || !res.ok) { b.classList.add('ko'); setTimeout(() => b.classList.remove('ko'), 1500); }
  b.disabled = false;
};

byId('close').onclick = () => post('close');
document.addEventListener('keyup', (e) => {
  if (e.key === 'Escape' && !byId('mech').classList.contains('hidden')) post('close');
});

window.addEventListener('message', (e) => {
  const d = e.data || {};
  if (d.action === 'open') {
    strings = d.strings || {}; state = d.data || {}; filter = 'all';
    applyStrings(); render();
    byId('mech').classList.remove('hidden');
  } else if (d.action === 'data') {
    state = d.data || {}; render();
  } else if (d.action === 'close') {
    byId('mech').classList.add('hidden');
  }
});
