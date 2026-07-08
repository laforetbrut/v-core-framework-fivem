// v-hud — money HUD renderer
const fmt = (n) => '$' + Math.floor(Number(n) || 0).toLocaleString('en-US');
const byId = (id) => document.getElementById(id);

let last = { cash: 0, bank: 0 };

function setVal(id, value, delta) {
  const el = byId(id);
  el.textContent = fmt(value);
  if (delta && delta !== 0) {
    el.classList.remove('flash-up', 'flash-down');
    void el.offsetWidth;                 // restart the animation
    el.classList.add(delta > 0 ? 'flash-up' : 'flash-down');
  }
}

window.addEventListener('message', (event) => {
  const data = event.data || {};

  if (data.action === 'show') {
    setVal('cash', data.cash);
    setVal('bank', data.bank);
    last = { cash: data.cash, bank: data.bank };
    byId('hud').classList.remove('hidden');

  } else if (data.action === 'money') {
    setVal('cash', data.cash, data.cash - last.cash);
    setVal('bank', data.bank, data.bank - last.bank);
    last = { cash: data.cash, bank: data.bank };

  } else if (data.action === 'hide') {
    byId('hud').classList.add('hidden');
  }
});
