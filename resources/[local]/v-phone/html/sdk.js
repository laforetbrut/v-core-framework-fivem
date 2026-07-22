/* ============================================================
   v-phone — app SDK
   ============================================================

   Ship an app in one HTML file. No build step, no framework, no bundler:

     <link rel="stylesheet" href="https://cfx-nui-v-phone/style.css">
     <script src="https://cfx-nui-v-phone/sdk.js"><\/script>
     (the escaped slash above is deliberate: an unescaped closing script tag here
      would end any <script> tag it was pasted into)
     <script>
       Phone.ready(function (me) {
         Phone.title('Notes');
         Phone.ui.render(
           Phone.ui.group([
             Phone.ui.row({ title: 'My number', value: me.number }),
             Phone.ui.row({ title: 'Write one', chevron: true, data: { act: 'new' } }),
           ], { header: 'Notes' })
         );
         Phone.ui.on('[data-act="new"]', 'click', function () { Phone.toast('Hello'); });
       });
     <\/script>

   Two objects are exported:

     PhoneUI   the component kit. Always defined, and it is the SAME object the
               built-in apps draw themselves with — one definition, so a
               third-party app cannot drift out of looking native.

     Phone     the bridge to the phone and the server. Only defined inside an app
               frame, because outside one there is nothing to talk to.

   Every call returns a Promise. The phone answers on the same channel it was
   asked, so an app never has to wire up its own message plumbing.
*/
(function (root) {
  'use strict';

  // ══ Escaping ═══════════════════════════════════════════════
  // Everything the kit renders goes through this. An app that interpolates a
  // player's name into a template must not be able to inject markup with it.
  const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

  // ══ Icons ══════════════════════════════════════════════════
  const ICONS = {
    phone: 'M6.5 2.5l3.2 5-2.2 2.2a13.5 13.5 0 0 0 6.8 6.8l2.2-2.2 5 3.2-2 4.2c-8.6.5-17.4-8.3-16.9-16.9z',
    messages: 'M12 3c-5 0-9 3.4-9 7.6 0 2.4 1.3 4.5 3.3 5.9l-.9 3.9 4.2-2.2c.8.2 1.6.3 2.4.3 5 0 9-3.4 9-7.9S17 3 12 3Z',
    contacts: 'M12 3a4 4 0 1 0 0 8 4 4 0 0 0 0-8ZM4 21a8 8 0 0 1 16 0',
    bank: 'M3 10h18L12 4 3 10ZM5 10v8M10 10v8M14 10v8M19 10v8M3 20h18',
    garage: 'M3 20V9l9-5 9 5v11M7 20v-7h10v7M7 16h10',
    wallet: 'M3 7h15a2 2 0 0 1 2 2v9H3zM3 7V5h13M17 12h3v3h-3z',
    jobs: 'M4 8h16v12H4zM9 8V6a2 2 0 0 1 2-2h2a2 2 0 0 1 2 2v2M4 13h16',
    settings: 'M12 9a3 3 0 1 0 0 6 3 3 0 0 0 0-6ZM19.4 13a7.6 7.6 0 0 0 0-2l2-1.5-2-3.4-2.4 1a7.6 7.6 0 0 0-1.7-1L14.9 3H9.1l-.4 2.6a7.6 7.6 0 0 0-1.7 1l-2.4-1-2 3.4L4.6 11a7.6 7.6 0 0 0 0 2l-2 1.5 2 3.4 2.4-1a7.6 7.6 0 0 0 1.7 1L9.1 21h5.8l.4-2.6a7.6 7.6 0 0 0 1.7-1l2.4 1 2-3.4Z',
    camera: 'M4 8h3l2-3h6l2 3h3v12H4zM12 10a4 4 0 1 0 0 8 4 4 0 0 0 0-8Z',
    hangup: 'M2 11c5.6-4.6 14.4-4.6 20 0l-2.4 3.4-4.2-1.2v-2.4a13 13 0 0 0-6.8 0v2.4l-4.2 1.2z',
    answer: 'M6.5 2.5l3.2 5-2.2 2.2a13.5 13.5 0 0 0 6.8 6.8l2.2-2.2 5 3.2-2 4.2c-8.6.5-17.4-8.3-16.9-16.9z',
    mute: 'M12 4v16l-5-4H3V8h4l5-4ZM17 9l4 6M21 9l-4 6',
    speaker: 'M12 4v16l-5-4H3V8h4l5-4ZM16 9a4 4 0 0 1 0 6M18.5 6.5a8 8 0 0 1 0 11',
    keypad: 'M6 5h.01M12 5h.01M18 5h.01M6 11h.01M12 11h.01M18 11h.01M6 17h.01M12 17h.01M18 17h.01',
    add: 'M12 5v14M5 12h14',
    chevron: 'M9 4l7 8-7 8',
    send: 'M4 12l16-8-6 8 6 8z',
    del: 'M9 6h11v12H9L3 12zM17 9l-5 6M12 9l5 6',
    moon: 'M20 14A8.5 8.5 0 0 1 10 4a8.5 8.5 0 1 0 10 10Z',
    sun: 'M12 6a6 6 0 1 0 0 12 6 6 0 0 0 0-12ZM12 1v2M12 21v2M4.2 4.2l1.4 1.4M18.4 18.4l1.4 1.4M1 12h2M21 12h2M4.2 19.8l1.4-1.4M18.4 5.6l1.4-1.4',
    wall: 'M4 5h16v14H4zM4 15l4-4 3 3 4-5 5 6',
    note: 'M5 3h9l5 5v13H5zM14 3v5h5M8 12h8M8 16h6',
    star: 'M12 3l2.7 5.9 6.3.7-4.7 4.3 1.3 6.3L12 17l-5.6 3.2 1.3-6.3L3 9.6l6.3-.7z',
    map: 'M9 4L3 6v14l6-2 6 2 6-2V4l-6 2zM9 4v14M15 6v14',
    cart: 'M4 6h16l-1.5 9H6zM6 15l-1 4h13M9 21h.01M17 21h.01',
    house: 'M4 11l8-7 8 7v9H4zM10 20v-6h4v6',
    shield: 'M12 3l7 3v5c0 5-3 8-7 10-4-2-7-5-7-10V6l7-3Z',
    fuel: 'M4 21V5a2 2 0 0 1 2-2h6a2 2 0 0 1 2 2v16M3 21h12M4 11h10M17 8l3 3v7a2 2 0 0 1-4 0V9',
    wrench: 'M14 6a4 4 0 0 0-5 5L4 16l4 4 5-5a4 4 0 0 0 5-5l-3 3-2-2 3-3a4 4 0 0 0-2-2Z',
    id: 'M3 5h18v14H3zM8 11a2 2 0 1 0 0-4 2 2 0 0 0 0 4ZM5 16c.6-2 5-2 6 0M14 9h4M14 13h4',
    calc: 'M5 3h14v18H5zM8 7h8M8 11h.01M12 11h.01M16 11h.01M8 15h.01M12 15h.01M16 15h4',
    trash: 'M4 7h16M9 7V4h6v3M6 7l1 14h10l1-14M10 11v6M14 11v6',
    store: 'M4 8h16l-1.5 12h-13zM4 8l2-4h12l2 4M9 12a3 3 0 0 0 6 0',
    heart: 'M12 20s-7-4.4-7-9.4A4.6 4.6 0 0 1 12 7a4.6 4.6 0 0 1 7 3.6c0 5-7 9.4-7 9.4Z',
    check: 'M20 6L9 17l-5-5',
    folder: 'M3 6h6l2 2h10v11H3z',
    cloud: 'M7 18a4 4 0 0 1 0-8 5.5 5.5 0 0 1 10.6 1.5A3.5 3.5 0 0 1 17 18Z',
    rain: 'M7 15a4 4 0 0 1 0-8 5.5 5.5 0 0 1 10.6 1.5A3.5 3.5 0 0 1 17 15M8 18l-1 3M12 18l-1 3M16 18l-1 3',
    snow: 'M7 15a4 4 0 0 1 0-8 5.5 5.5 0 0 1 10.6 1.5A3.5 3.5 0 0 1 17 15M8 19h.01M12 20h.01M16 19h.01',
    search: 'M11 4a7 7 0 1 0 0 14 7 7 0 0 0 0-14ZM20 20l-4-4',
    dot: 'M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8Z',
  };
  const FILLED = { phone: 1, messages: 1, hangup: 1, answer: 1, send: 1, star: 1 };

  const svg = (n) => {
    const d = ICONS[n] || ICONS.dot;
    return FILLED[n]
      ? '<svg viewBox="0 0 24 24" fill="currentColor"><path d="' + d + '"/></svg>'
      : '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" ' +
        'stroke-linecap="round" stroke-linejoin="round"><path d="' + d + '"/></svg>';
  };

  // ══ Component kit ══════════════════════════════════════════
  // Every helper returns an HTML STRING. An app is a template, not a component
  // tree, because somebody writing their first app should not have to learn a
  // framework before they can draw a list.
  const UI = {
    esc: esc,
    svg: svg,
    icons: ICONS,

    /** A grouped, inset list. `rows` is an array of UI.row() strings. */
    group: function (rows, opts) {
      const o = opts || {};
      return (o.header ? '<div class="grouphead">' + esc(o.header) + '</div>' : '') +
        '<div class="group">' + (Array.isArray(rows) ? rows.join('') : rows) + '</div>' +
        (o.footer ? '<div class="groupfoot">' + esc(o.footer) + '</div>' : '');
    },

    /**
     * One row. Everything is optional except `title`.
     *   icon / avatar   leading tile, or a circle with the first letter
     *   subtitle        second line
     *   value           trailing text; `tone: 'pos' | 'neg'`, `mono: true`
     *   badge / time    trailing pill or timestamp
     *   toggle          an iOS switch (true / false)
     *   chevron         the disclosure arrow
     *   data            { k: v } becomes data-k="v", for your click handler
     */
    row: function (o) {
      const lead = o.icon
        ? '<span class="ricon">' + svg(o.icon) + '</span>'
        : (o.avatar ? '<span class="rav">' + esc(String(o.avatar).slice(0, 1).toUpperCase()) + '</span>' : '');
      const tail =
        (o.badge ? '<span class="rbadge">' + esc(o.badge) + '</span>' : '') +
        (o.time ? '<span class="rtime">' + esc(o.time) + '</span>' : '') +
        (o.value !== undefined ? '<span class="rval ' + (o.tone || '') + ' ' + (o.mono ? 'num' : '') + '">' + esc(o.value) + '</span>' : '') +
        (o.toggle !== undefined ? '<span class="sw ' + (o.toggle ? 'on' : '') + '"><i></i></span>' : '') +
        (o.chevron ? '<span class="rchev">' + svg('chevron') + '</span>' : '');
      let attrs = '';
      const data = o.data || {};
      for (const k in data) attrs += ' data-' + k + '="' + esc(data[k]) + '"';
      return '<button class="row ' + (lead ? 'lead' : '') + '" type="button"' + attrs + '>' + lead +
        '<span class="rmain"><span class="rt">' + esc(o.title) + '</span>' +
        (o.subtitle ? '<span class="rs">' + esc(o.subtitle) + '</span>' : '') +
        '</span>' + tail + '</button>';
    },

    bigNumber: function (label, value, sub) {
      return '<div class="bignum"><div class="bl">' + esc(label) + '</div>' +
        '<div class="bv">' + esc(value) + '</div>' +
        (sub ? '<div class="bs">' + esc(sub) + '</div>' : '') + '</div>';
    },

    /** style: '' (accent) | 'tinted' | 'plain' | 'destructive' */
    button: function (label, id, style) {
      return '<button class="bigbtn ' + (style || '') + '" id="' + esc(id) + '" type="button">' +
        esc(label) + '</button>';
    },

    field: function (id, placeholder, value, attrs) {
      return '<input class="field" id="' + esc(id) + '" placeholder="' + esc(placeholder) +
        '" value="' + esc(value || '') + '" ' + (attrs || '') + ' />';
    },

    empty: function (text, icon) {
      return '<div class="empty">' + (icon ? svg(icon) : '') + '<div>' + esc(text) + '</div></div>';
    },

    /** Replace the app body. Inside a frame this is the document body. */
    render: function (html) {
      const host = document.getElementById('appbody') || document.body;
      host.innerHTML = html;
      return host;
    },

    /** Delegate an event to everything matching a selector, now and after a re-render. */
    on: function (selector, event, handler) {
      const host = document.getElementById('appbody') || document.body;
      host.addEventListener(event, function (e) {
        const el = e.target.closest ? e.target.closest(selector) : null;
        if (el && host.contains(el)) handler(e, el);
      });
    },
  };

  root.PhoneUI = UI;

  // ══ Bridge ═════════════════════════════════════════════════
  // Only inside an app frame. Outside one, `Phone` is deliberately undefined
  // rather than a stub that silently does nothing.
  if (root.parent === root) return;

  let seq = 0;
  const pending = {};

  root.addEventListener('message', function (e) {
    const d = e.data || {};
    if (d.__phone !== 'reply' || !pending[d.id]) return;
    const resolve = pending[d.id];
    delete pending[d.id];
    resolve(d.payload);
  });

  function send(op, data) {
    return new Promise(function (resolve) {
      const id = ++seq;
      pending[id] = resolve;
      root.parent.postMessage({ __phone: 'sdk', id: id, op: op, data: data || {} }, '*');
      // A phone that went away must not leave the app waiting for ever.
      setTimeout(function () {
        if (pending[id]) { delete pending[id]; resolve({ error: 'timeout' }); }
      }, 10000);
    });
  }

  const Phone = {
    ui: UI,

    /** Runs once the phone has answered with who this player is. */
    ready: function (fn) {
      send('me').then(function (me) {
        document.body.classList.add('inframe');
        fn(me || {});
      });
    },

    /** The title drawn in the phone's navigation bar. */
    title: function (text) { return send('title', { title: text }); },
    close: function () { return send('close'); },

    /** A transient message at the bottom of the screen. */
    toast: function (text) { return send('toast', { text: text }); },

    /** A banner at the top, and an entry in the lock-screen stack. */
    notify: function (title, body) { return send('notify', { title: title, body: body }); },

    /** The red count on this app's home-screen icon. 0 clears it. */
    badge: function (count) { return send('badge', { count: count }); },

    /**
     * Call one of YOUR OWN server callbacks.
     *
     *   Phone.request('save', { text })   ->  V.Callback('notes:save', ...)
     *
     * The full name is composed in Lua as `<yourAppId>:<method>` and the app id
     * comes from the phone, not from this message. An app therefore cannot reach
     * `v-banking:withdraw` by asking for it: there is no way to spell it. If your
     * app needs another module, call that module from your own server callback,
     * where you can check whatever you like first.
     */
    request: function (method, data) { return send('request', { method: method, payload: data }); },

    /** Fire one of your own server events, named `<yourAppId>:<event>`. */
    emit: function (event, data) { return send('emit', { event: event, payload: data }); },

    /** Per app, per character, persisted server-side. */
    storage: {
      get: function (key) { return send('storage', { op: 'get', key: key }); },
      set: function (key, value) { return send('storage', { op: 'set', key: key, value: value }); },
      all: function () { return send('storage', { op: 'all' }); },
    },

    /** The player's own contact list, read only. */
    contacts: function () { return send('contacts'); },

    /** Send a message as the player. Goes through the same path the Messages app uses. */
    message: function (number, body) { return send('message', { number: number, body: body }); },

    /** Start a call. Routed and validated by the server, exactly like the dialler. */
    call: function (number) { return send('call', { number: number }); },
  };

  root.Phone = Phone;
})(window);
