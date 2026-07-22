// v-cityhall — job desk logic
const byId = (id) => document.getElementById(id);
const post = (n, b) => fetch(`https://v-cityhall/${n}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(b || {}) }).then(r => r.json()).catch(() => false);
const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const fmt = (n) => '$' + Math.floor(Number(n) || 0).toLocaleString('en-US');

let strings = {}, state = {};
const t = (k) => strings[k] || k;

const ERR = { far: 'cityhall.err_far', whitelisted: 'cityhall.err_wl', already: 'cityhall.err_alr', funds: 'cityhall.err_fund' };

function applyStrings() {
  document.querySelectorAll('[data-i18n]').forEach(el => { el.textContent = t(el.getAttribute('data-i18n')); });
}

function flash(btn, ok, msg) {
  btn.classList.add(ok ? 'ok' : 'ko');
  if (msg) { btn.dataset.old = btn.textContent; btn.textContent = msg; }
  setTimeout(() => {
    btn.classList.remove('ok', 'ko');
    if (btn.dataset.old) { btn.textContent = btn.dataset.old; delete btn.dataset.old; }
  }, 1600);
}

function render() {
  byId('cur-job').textContent = [state.label, state.grade].filter(Boolean).join(' · ') || '—';
  byId('resign').classList.toggle('hidden', (state.current || 'unemployed') === 'unemployed');

  const wrap = byId('list'); wrap.innerHTML = '';
  const jobs = state.jobs || [];
  if (!jobs.length) { wrap.innerHTML = `<div class="empty">${esc(t('cityhall.empty'))}</div>`; return; }

  jobs.forEach((j, i) => {
    const mine = j.name === state.current;
    const row = document.createElement('div');
    row.className = 'jrow' + (mine ? ' mine' : '');
    row.style.setProperty('--i', i);
    row.innerHTML = `
      <span class="jmark type-${esc(j.type || 'civ')}"></span>
      <span class="jinfo">
        <span class="jname">${esc(j.label)}</span>
        <span class="jmeta">${esc(j.grade || '')} · ${esc(t('cityhall.salary'))} ${fmt(j.salary)} · ${j.ranks} ${esc(t('cityhall.ranks'))}</span>
      </span>
      <button class="mini accent jtake"${mine ? ' disabled' : ''}>${esc(t('cityhall.take'))}</button>`;

    if (!mine) row.querySelector('.jtake').onclick = async (e) => {
      const b = e.currentTarget;
      b.disabled = true;
      const res = await post('take', { job: j.name });
      if (res && res.ok) { flash(b, true); }
      else { flash(b, false, t(ERR[res && res.error] || 'cityhall.err')); b.disabled = false; }
    };
    wrap.appendChild(row);
  });
}

byId('close').onclick = () => post('close');
byId('resign').onclick = async (e) => {
  const b = e.currentTarget;
  b.disabled = true;
  const res = await post('resign');
  if (!res || !res.ok) flash(b, false, t(ERR[res && res.error] || 'cityhall.err'));
  b.disabled = false;
};

document.addEventListener('keyup', (e) => {
  if (e.key === 'Escape' && !byId('hall').classList.contains('hidden')) post('close');
});

window.addEventListener('message', (e) => {
  const d = e.data || {};
  if (d.action === 'open') {
    strings = d.strings || {};
    state = d.data || {};
    applyStrings(); render();
    byId('hall').classList.remove('hidden');
  } else if (d.action === 'data') {
    state = d.data || {};
    render();
  } else if (d.action === 'close') {
    byId('hall').classList.add('hidden');
  }
});
