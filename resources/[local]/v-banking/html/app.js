// v-banking — Fleeca UI
const byId = (id) => document.getElementById(id);
const fmt = (n) => '$' + Math.floor(Number(n) || 0).toLocaleString('en-US');
let strings = {};
let currentTab = 'deposit';

const t = (k) => strings[k] || k;
const applyStrings = () => document.querySelectorAll('[data-i18n]').forEach(el => { el.textContent = t(el.getAttribute('data-i18n')); });

function post(name, body) {
  return fetch(`https://v-banking/${name}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body || {}) })
    .then(r => r.json()).catch(() => false);
}

function showMsg(text, kind) {
  const m = byId('msg');
  m.textContent = text || '';
  m.className = 'msg' + (kind ? ' ' + kind : '');
}

function render(data) {
  byId('bank-amt').textContent = fmt(data.bank);
  byId('cash-amt').textContent = fmt(data.cash);
  const list = byId('tx-list');
  list.innerHTML = '';
  const txs = data.transactions || [];
  if (!txs.length) { list.innerHTML = `<div class="tx-empty">${t('bank.empty')}</div>`; return; }
  txs.forEach(tx => {
    const positive = tx.type === 'deposit' || tx.type === 'transfer_in';
    const row = document.createElement('div');
    row.className = 'tx';
    const date = (tx.created_at || '').toString().replace('T', ' ').slice(0, 16);
    row.innerHTML =
      `<div class="l"><span class="k">${t('tx.' + tx.type)}</span><span class="d">${date}${tx.label ? ' · ' + escapeHtml(tx.label) : ''}</span></div>` +
      `<span class="a ${positive ? 'plus' : 'minus'}">${positive ? '+' : '−'}${fmt(tx.amount)}</span>`;
    list.appendChild(row);
  });
}

function escapeHtml(s) { const d = document.createElement('div'); d.textContent = String(s); return d.innerHTML; }

function setTab(tab) {
  currentTab = tab;
  document.querySelectorAll('.tab').forEach(b => b.classList.toggle('on', b.getAttribute('data-tab') === tab));
  byId('target-field').classList.toggle('hidden', tab !== 'transfer');
  showMsg('');
}

function close() { byId('bank').classList.add('hidden'); post('close'); }

document.querySelectorAll('.tab').forEach(b => b.onclick = () => setTab(b.getAttribute('data-tab')));
byId('close').onclick = close;
byId('bank').addEventListener('mousedown', (e) => { if (e.target.id === 'bank') close(); });
document.addEventListener('keydown', (e) => { if (e.key === 'Escape' && !byId('bank').classList.contains('hidden')) close(); });

byId('confirm').onclick = async () => {
  const amount = parseInt(byId('amount').value, 10);
  if (!amount || amount <= 0) { showMsg(t('bank.amount'), 'err'); return; }
  let res;
  if (currentTab === 'transfer') res = await post('transfer', { amount, target: byId('target').value.trim() });
  else res = await post(currentTab, { amount });

  if (!res) { showMsg(t('bank.err_funds'), 'err'); return; }
  if (res.error) { showMsg(res.error === 'target' ? t('bank.err_target') : t('bank.err_funds'), 'err'); return; }
  render(res);
  byId('amount').value = '';
  showMsg((t('bank.ok_' + currentTab) || '').replace('%s', fmt(amount).slice(1)), 'ok');
};

window.addEventListener('message', (e) => {
  const d = e.data || {};
  if (d.action === 'open') {
    strings = d.strings || {};
    applyStrings();
    setTab('deposit');
    render(d.data || { bank: 0, cash: 0, transactions: [] });
    byId('bank').classList.remove('hidden');
    byId('amount').value = '';
    showMsg('');
  } else if (d.action === 'close') {
    byId('bank').classList.add('hidden');
  }
});
