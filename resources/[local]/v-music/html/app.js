// v-music - the audio side. The server decides what plays and where; this page holds one
// <audio> per source and the Lua side feeds it a volume as the listener walks.
//
// The pool lives outside the panel on purpose: closing the UI must not stop the music.
(() => {
  const $ = id => document.getElementById(id);
  const root = $('music');
  const pool = $('pool');
  const players = new Map();       // sourceId -> HTMLAudioElement
  let S = {}, D = {}, kind = 'boombox', target = null;

  const t = k => S[k] || k;
  const ENT = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' };
  const esc = s => String(s === null || s === undefined ? '' : s).replace(/[&<>"']/g, c => ENT[c]);

  function post(name, body) {
    const res = location.hostname.replace(/^cfx-nui-/, '');
    return fetch('https://' + res + '/' + name, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(body || {}),
    }).catch(() => {});
  }

  // ── Audio ──────────────────────────────────────────────────────────────────
  function ensure(id) {
    let a = players.get(id);
    if (!a) {
      a = new Audio();
      a.preload = 'auto';
      a.volume = 0;
      pool.appendChild(a);
      players.set(id, a);
    }
    return a;
  }

  function setSource(id, url, offset, paused) {
    const a = ensure(id);
    if (a.dataset.url !== url) {
      a.dataset.url = url;
      a.src = url;
    }
    // Seek to where the world already is. A player arriving late joins mid-track rather
    // than restarting it for everybody, which is the whole point of syncing by timestamp.
    const seek = () => {
      try { if (Number.isFinite(offset) && offset > 0) a.currentTime = offset; } catch (e) {}
    };
    if (a.readyState >= 1) seek(); else a.addEventListener('loadedmetadata', seek, { once: true });

    if (paused) {
      a.pause();
    } else {
      const p = a.play();
      // A rejection here is normal until CEF has allowed audio, and for a dead URL.
      // Neither deserves a console error every time somebody walks past a boombox.
      if (p && p.catch) p.catch(() => {});
    }
  }

  function stop(id) {
    const a = players.get(id);
    if (!a) return;
    try { a.pause(); a.src = ''; } catch (e) {}
    a.remove();
    players.delete(id);
  }

  function stopAll() {
    for (const id of Array.from(players.keys())) stop(id);
  }

  // ── Panel ──────────────────────────────────────────────────────────────────
  function render() {
    $('m-title').textContent = t('mus.title');
    $('m-sub').textContent = t('mus.' + kind);
    $('m-lbl').textContent = t('mus.playing');
    $('m-play').textContent = t('mus.play');
    $('m-url').placeholder = t('mus.url');
    $('m-hint').textContent = t('mus.hint');

    const list = D.sources || [];
    const box = $('m-list');
    if (!list.length) {
      box.innerHTML = `<div class="empty-note">${esc(t('mus.none'))}</div>`;
      return;
    }

    const frag = document.createDocumentFragment();
    for (const s of list) {
      const el = document.createElement('div');
      el.className = 'src';
      el.innerHTML =
        `<div class="src__main">` +
          `<div class="src__kind">${esc(t('mus.' + s.kind))}</div>` +
          `<div class="src__url">${esc(s.title || s.url || '')}</div>` +
        `</div>` +
        `<input class="src__vol" type="range" min="0" max="100" value="${Math.round((s.volume || 0.6) * 100)}" />` +
        `<button class="btn ghost" data-a="${s.paused ? 'resume' : 'pause'}">` +
          `${esc(s.paused ? t('mus.resume') : t('mus.pause'))}</button>` +
        `<button class="btn ghost" data-a="stop">${esc(t('mus.stop'))}</button>`;

      el.querySelectorAll('[data-a]').forEach(b =>
        b.addEventListener('click', () => post('control', { id: s.id, action: b.dataset.a })));
      // `change` rather than `input`: dragging a slider would otherwise post on every
      // pixel, and each post is a server round trip.
      el.querySelector('.src__vol').addEventListener('change', ev =>
        post('control', { id: s.id, action: 'volume', volume: Number(ev.target.value) / 100 }));
      frag.appendChild(el);
    }
    box.replaceChildren(frag);
  }

  window.addEventListener('message', ev => {
    const d = ev.data || {};
    switch (d.action) {
      case 'source':  setSource(d.id, d.url, Number(d.offset) || 0, d.paused === true); break;
      case 'volume': {
        const a = players.get(d.id);
        if (a) a.volume = Math.max(0, Math.min(1, Number(d.volume) || 0));
        break;
      }
      case 'stop':    stop(d.id); break;
      case 'stopAll': stopAll(); break;
      case 'open':
        S = d.strings || S;
        D = d.data || {};
        kind = d.kind || 'boombox';
        target = d.target || null;
        render();
        root.classList.remove('hidden');
        break;
      case 'close':
        root.classList.add('hidden');
        break;
    }
  });

  $('m-close').addEventListener('click', () => { root.classList.add('hidden'); post('close'); });
  $('m-play').addEventListener('click', () => {
    const url = ($('m-url').value || '').trim();
    if (!url) return;
    post('play', { kind, id: target, url });
    $('m-url').value = '';
  });
  document.addEventListener('keyup', e => {
    if (e.key === 'Escape' && !root.classList.contains('hidden')) {
      root.classList.add('hidden');
      post('close');
    }
  });
})();
