// v-ui | theme.js — included by every NUI page in the framework.
//
// A NUI page can only talk to the resource that owns it, so v-ui cannot message
// v-inventory's page directly. What it CAN do is regenerate `theme-vars.css`, which every
// page links; this script re-fetches that stylesheet when the theme changes so the new
// palette lands without anyone reopening a menu.
(function () {
  var LINK_ID = 'v-ui-vars';

  function ensureLink() {
    var l = document.getElementById(LINK_ID);
    if (!l) {
      l = document.createElement('link');
      l.id = LINK_ID;
      l.rel = 'stylesheet';
      l.href = 'https://cfx-nui-v-ui/theme-vars.css';
      document.head.appendChild(l);
    }
    return l;
  }

  function apply(version) {
    var l = ensureLink();
    // a new href is the only reliable way to make CEF drop a cached stylesheet
    l.href = 'https://cfx-nui-v-ui/theme-vars.css?v=' + (version || 0);
  }

  // The owning resource forwards v-ui's version to its own page.
  window.addEventListener('message', function (e) {
    var d = e.data || {};
    if (d.action === 'v-ui:theme') apply(d.version);
  });

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function () { ensureLink(); });
  } else {
    ensureLink();
  }
})();
