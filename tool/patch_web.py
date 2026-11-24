"""Runs on GitHub after `flutter create --platforms web`: Arabic title,
description and right-to-left page for the website."""
import json
import re
from pathlib import Path

TITLE = "سلمان العماد — أجوبة الشيخ سلمان بن صالح العماد"
DESC = ("أجوبة ومقالات وكتب ورسائل الشيخ سلمان بن صالح العماد حفظه الله، "
        "مرتبة على أبواب العقيدة والفقه والآداب، مع البحث بالموضوع.")

index = Path("web/index.html")
h = index.read_text(encoding="utf-8")
h = re.sub(r"<html[^>]*>", '<html lang="ar" dir="rtl">', h, count=1)
h = re.sub(r"<title>.*?</title>", f"<title>{TITLE}</title>", h, count=1, flags=re.S)
h = re.sub(r'<meta name="description" content="[^"]*">', f'<meta name="description" content="{DESC}">', h, count=1)
SITE = "https://www774475437-svg.github.io/alemad/"
if 'property="og:title"' not in h:
    h = h.replace("</head>",
                  f'  <meta property="og:title" content="{TITLE}">\n'
                  f'  <meta property="og:description" content="{DESC}">\n'
                  f'  <meta property="og:image" content="{SITE}icons/Icon-512.png">\n'
                  f'  <meta property="og:url" content="{SITE}">\n'
                  f'  <meta property="og:type" content="website">\n'
                  f'  <meta name="twitter:card" content="summary">\n</head>', 1)
h = h.replace('content="alemad"', 'content="سلمان العماد"')
# A loading screen with the logo, shown until the app draws its first frame.
if 'id="loading"' not in h:
    h = h.replace("<body>", '''<body>
  <style>
    #loading { position: fixed; inset: 0; display: flex; flex-direction: column; align-items: center;
      justify-content: center; background: #5E1B24; z-index: 9; transition: opacity .4s; }
    #loading img { width: 132px; height: 132px; border-radius: 50%; animation: pulse 1.6s ease-in-out infinite; }
    #loading p { color: #fff; font: 16px sans-serif; margin-top: 22px; }
    @keyframes pulse { 0%,100% { transform: scale(1); opacity: 1; } 50% { transform: scale(1.06); opacity: .8; } }
  </style>
  <div id="loading"><img src="icons/Icon-192.png" alt=""><p>جارٍ فتح «سلمان العماد»…</p>
    <button id="retry" style="display:none;margin-top:18px;padding:12px 26px;border:0;border-radius:24px;background:#C9A54C;color:#000;font:bold 16px sans-serif">إعادة التحميل</button>
    <p id="why" style="font-size:12px;opacity:.75;max-width:86%;text-align:center;direction:ltr"></p></div>
  <script>
    (function () {
      var opened = false;
      window.addEventListener('flutter-first-frame', function () {
        opened = true;
        var l = document.getElementById('loading');
        if (l) { l.style.opacity = 0; setTimeout(function () { l.remove(); }, 450); }
      });
      // If the page stays on this screen (an old copy kept by the browser, or
      // an error), offer a clean reload and show what went wrong.
      function fresh() {
        var done = function () { location.replace(location.pathname + '?r=' + Date.now() + location.hash); };
        try {
          var jobs = [];
          if (window.caches) jobs.push(caches.keys().then(function (k) { return Promise.all(k.map(function (n) { return caches.delete(n); })); }));
          if (navigator.serviceWorker) jobs.push(navigator.serviceWorker.getRegistrations().then(function (r) { return Promise.all(r.map(function (x) { return x.unregister(); })); }));
          Promise.all(jobs).then(done, done);
        } catch (e) { done(); }
      }
      var seen = [];
      function stuck(msg) {
        if (opened) return;
        var b = document.getElementById('retry'), w = document.getElementById('why');
        if (b) { b.style.display = 'block'; b.onclick = fresh; }
        if (msg && seen.length < 4) seen.push(String(msg).slice(0, 260));
        if (w) w.textContent = seen.join('  |  ');
      }
      // Say exactly what failed, so a photo of this screen is enough to fix it.
      window.addEventListener('error', function (e) {
        var t = e.target, where = '';
        if (t && t !== window) where = (t.tagName || t.constructor && t.constructor.name || '') + ' ' + (t.src || t.href || t.currentSrc || t.data || '');
        var st = e.error && e.error.stack ? String(e.error.stack).split('\\n').slice(0, 2).join(' ') : '';
        stuck([e.message, e.filename ? e.filename.split('/').pop() + ':' + e.lineno : '', where, st].filter(Boolean).join(' · ') || 'error ?');
      }, true);
      window.addEventListener('unhandledrejection', function (e) {
        var r = e.reason;
        stuck('P: ' + (r && (r.stack || r.message) || r));
      });
      setTimeout(function () { stuck(''); }, 20000);
      // Once, by itself: a first try at a clean reload before asking.
      setTimeout(function () {
        if (opened || /[?&]r=/.test(location.search)) return;
        fresh();
      }, 45000);
    })();
  </script>''', 1)
index.write_text(h, encoding="utf-8")

manifest = Path("web/manifest.json")
data = json.loads(manifest.read_text(encoding="utf-8"))
data.update({"name": "سلمان العماد", "short_name": "سلمان العماد", "description": DESC,
             "background_color": "#5E1B24", "theme_color": "#5E1B24", "dir": "rtl", "lang": "ar"})
manifest.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
print("Web patched")

# Site icons (pre-made from the logo in tool/web_icons/)
import shutil
for name in ["Icon-192.png", "Icon-512.png", "Icon-maskable-192.png", "Icon-maskable-512.png"]:
    shutil.copy(f"tool/web_icons/{name}", f"web/icons/{name}")
shutil.copy("tool/web_icons/favicon.png", "web/favicon.png")
print("Web icons copied")
