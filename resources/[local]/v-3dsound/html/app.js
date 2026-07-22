// v-3dsound — the audio side of custom files. CEF has no notion of world space, so the
// client has already turned distance into a volume by the time a message arrives here.
(() => {
  // A pool rather than one element per sound: creating an Audio per shot leaks handles,
  // and a burst of overlapping sounds is exactly what a gunfight is.
  const POOL_SIZE = 8;
  const pool = [];
  let next = 0;

  for (let i = 0; i < POOL_SIZE; i++) {
    const a = new Audio();
    a.preload = 'auto';
    pool.push(a);
  }

  function play(file, volume) {
    const a = pool[next];
    next = (next + 1) % POOL_SIZE;
    try {
      a.pause();
      a.currentTime = 0;
      a.src = file;
      a.volume = Math.max(0, Math.min(1, Number(volume) || 0));
      // A rejected promise here is normal: CEF refuses playback until the page has been
      // allowed audio, and a missing file rejects too. Neither is worth a console error
      // on every shot.
      const p = a.play();
      if (p && p.catch) p.catch(() => {});
    } catch (e) { /* a broken source must never take the page down */ }
  }

  function stopAll() {
    for (const a of pool) {
      try { a.pause(); a.currentTime = 0; } catch (e) { /* nothing to stop */ }
    }
  }

  window.addEventListener('message', ev => {
    const d = ev.data || {};
    if (d.action === 'play' && d.file) play(d.file, d.volume);
    else if (d.action === 'stopAll') stopAll();
  });
})();
