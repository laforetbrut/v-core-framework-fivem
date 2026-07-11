// v-target — interaction eye NUI (display-only; selection happens in Lua via keys/LMB)
const byId = (id) => document.getElementById(id);
const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

// Small icon set (stroke svgs), keyed by the `icon` name options pass.
const ICONS = {
  trunk: 'M4 9h16v9H4zM4 9l2-4h12l2 4M9 13h6',
  box: 'M3 7l9-4 9 4v10l-9 4-9-4V7ZM3 7l9 4 9-4M12 11v10',
  search: 'M11 4a7 7 0 1 0 0 14 7 7 0 0 0 0-14ZM20 20l-4-4',
  wrench: 'M14 6a4 4 0 0 0-5 5L4 16l4 4 5-5a4 4 0 0 0 5-5l-3 3-2-2 3-3a4 4 0 0 0-2-2Z',
  shield: 'M12 3l7 3v5c0 5-3 8-7 10-4-2-7-5-7-10V6l7-3Z',
  dot: 'M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8Z',
};
const svg = (name) => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="${ICONS[name] || ICONS.dot}"/></svg>`;

function renderOptions(list) {
  const wrap = byId('opts');
  wrap.innerHTML = '';
  const has = Array.isArray(list) && list.length > 0;
  byId('reticle').classList.toggle('hot', has);
  if (!has) { wrap.classList.add('empty'); return; }
  wrap.classList.remove('empty');
  list.forEach((o) => {
    const row = document.createElement('div');
    row.className = 'opt';
    row.style.setProperty('--i', o.n - 1);
    row.innerHTML =
      `<span class="key">${o.n}</span>` +
      `<span class="ico">${svg(o.icon)}</span>` +
      `<span class="lbl">${esc(o.label)}</span>`;
    wrap.appendChild(row);
  });
}

window.addEventListener('message', (e) => {
  const d = e.data || {};
  if (d.action === 'eyeon') { byId('eye').classList.remove('hidden'); renderOptions([]); }
  else if (d.action === 'eyeoff') { byId('eye').classList.add('hidden'); renderOptions([]); }
  else if (d.action === 'options') { renderOptions(d.options || []); }
});
