// v-fuel — pump panel
const byId = (id) => document.getElementById(id);
const post = (n, b) => fetch(`https://v-fuel/${n}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(b || {}) }).then(r => r.json()).catch(() => false);
const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const fmt = (n) => '$' + Math.floor(Number(n) || 0).toLocaleString('en-US');
// unit prices are per litre and have cents: flooring them would show $1 for $1.65
const fmt2 = (n) => '$' + (Number(n) || 0).toFixed(2);

let strings = {}, state = {}, chosen = null;
const t = (k) => strings[k] || k;

function applyStrings() {
  document.querySelectorAll('[data-i18n]').forEach(el => { el.textContent = t(el.getAttribute('data-i18n')); });
}

// How many litres the tank can still take. Without a vehicle we fall back to the
// station's own maximum so the slider is never a single unusable step.
function missing() {
  const v = state.vehicle;
  if (!v || !v.tank) return 60;
  return Math.max(1, Math.round(v.tank * (100 - (v.fuel || 0)) / 100));
}

function priceOf(key) {
  const ty = (state.types || []).find(x => x.key === key);
  return ty ? Number(ty.price) || 0 : 0;
}

function updateTotal() {
  const l = Number(byId('litres').value) || 0;
  byId('lval').textContent = l;
  byId('total').textContent = fmt(Math.ceil(l * priceOf(chosen)));
}

function renderVehicle() {
  const v = state.vehicle, box = byId('veh');
  if (!v) { box.innerHTML = `<span class="vnone">${esc(t('fuel.novehicle'))}</span>`; return; }
  const accepts = (state.types || []).find(x => x.key === v.accepts);
  box.innerHTML = `
    <span class="vname">${esc(v.model)}</span>
    <span class="vplate">${esc(v.plate)}</span>
    <span class="vgauge">
      <span class="v-progress"><i class="v-progress__fill" style="width:${Math.round(v.fuel || 0)}%"></i></span>
      <span class="vpct">${Math.round(v.fuel || 0)}% · ${v.tank} L</span>
    </span>
    <span class="vaccepts">${esc(t('fuel.accepts'))} <b>${esc(accepts ? t(accepts.i18n) : v.accepts)}</b></span>`;
}

function renderTypes() {
  const wrap = byId('types'); wrap.innerHTML = '';
  const v = state.vehicle;
  (state.types || []).forEach((ty, i) => {
    // premium is accepted wherever regular is — same pump family, higher octane
    const fits = !v || ty.key === v.accepts || (v.accepts === 'regular' && ty.key === 'premium');
    const b = document.createElement('button');
    b.className = 'ftype' + (chosen === ty.key ? ' on' : '') + (fits ? '' : ' bad');
    b.style.setProperty('--i', i);
    b.style.setProperty('--fc', ty.color || '#c8a55a');
    b.innerHTML = `<span class="fdot"></span>
      <span class="fname">${esc(t(ty.i18n))}</span>
      ${ty.octane ? `<span class="foct">${ty.octane}</span>` : ''}
      <span class="fprice">${fmt2(ty.price)}<i>/L</i></span>
      ${fits ? '' : `<span class="fwarn">${esc(t('fuel.mismatch'))}</span>`}`;
    b.onclick = () => { chosen = ty.key; renderTypes(); updateTotal(); };
    wrap.appendChild(b);
  });
}

function render() {
  byId('ftitle').textContent = (state.station && state.station.label) || t('fuel.title');
  if (!chosen && (state.types || []).length) {
    const v = state.vehicle;
    const match = v && (state.types.find(x => x.key === v.accepts));
    chosen = (match || state.types[0]).key;
  }
  const max = missing();
  const sl = byId('litres');
  sl.max = max; sl.value = Math.min(Number(sl.value) || max, max);
  renderVehicle(); renderTypes(); updateTotal();
  byId('can').classList.toggle('hidden', !state.jerry);
}

byId('litres').oninput = updateTotal;
byId('full').onclick = () => { byId('litres').value = missing(); updateTotal(); };

byId('go').onclick = async () => {
  const l = Number(byId('litres').value) || 0;
  if (!chosen || l <= 0) return;
  byId('go').disabled = true;
  await post('pump', { type: chosen, litres: l, account: byId('acct-bank').checked ? 'bank' : 'cash' });
};

byId('can').onclick = async (e) => {
  const b = e.currentTarget; b.disabled = true;
  const res = await post('fillCan');
  if (res && res.ok) { state.cash = res.cash; state.bank = res.bank; }
  else { b.classList.add('ko'); setTimeout(() => b.classList.remove('ko'), 1400); }
  b.disabled = false;
};

byId('close').onclick = () => post('close');
document.addEventListener('keyup', (e) => {
  if (e.key === 'Escape' && !byId('fuel').classList.contains('hidden')) post('close');
});

window.addEventListener('message', (e) => {
  const d = e.data || {};
  if (d.action === 'open') {
    strings = d.strings || {}; state = d.data || {}; chosen = null;
    byId('go').disabled = false;
    byId('pumpbar').classList.add('hidden');
    applyStrings(); render();
    byId('fuel').classList.remove('hidden');
  } else if (d.action === 'pumping') {
    // the panel is already closed and focus released; only the gauge shows
    byId('pumpbar').classList.remove('hidden');
    byId('pfill').style.width = Math.round((d.litres / Math.max(1, d.want)) * 100) + '%';
    byId('pval').textContent = d.litres.toFixed(1) + ' L';
  } else if (d.action === 'pumpDone') {
    byId('pumpbar').classList.add('hidden');
  } else if (d.action === 'close') {
    byId('fuel').classList.add('hidden');
  }
});
