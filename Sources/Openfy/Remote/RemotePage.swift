/// The phone remote's web app: one self-contained page (no external files), built for iPhone
/// Safari and "Add to Home Screen". It polls /api/state once a second and sends commands as POSTs.
enum RemotePage {
    static let manifest = #"""
    {"name":"Openfy Remote","short_name":"Openfy","display":"standalone","orientation":"portrait",
     "background_color":"#0b0b0c","theme_color":"#0b0b0c",
     "icons":[{"src":"/icon.png","sizes":"180x180","type":"image/png"}]}
    """#

    static let html = #"""
    <!doctype html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover, user-scalable=no">
    <meta name="apple-mobile-web-app-capable" content="yes">
    <meta name="mobile-web-app-capable" content="yes">
    <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
    <meta name="apple-mobile-web-app-title" content="Openfy">
    <meta name="theme-color" content="#0b0b0c">
    <link rel="apple-touch-icon" href="/icon.png">
    <link rel="manifest" href="/manifest.webmanifest">
    <title>Openfy</title>
    <style>
    :root {
      --bg: #0b0b0c; --text: #f0f0f0; --secondary: #949494; --tertiary: #616161;
      --surface: rgba(255,255,255,.06); --hairline: rgba(255,255,255,.08);
      --hires: #e6c480; --perfect: #73dc94;
      --top: env(safe-area-inset-top, 0px); --bottom: env(safe-area-inset-bottom, 0px);
      color-scheme: dark;
    }
    * { box-sizing: border-box; -webkit-tap-highlight-color: transparent; }
    html, body { margin: 0; height: 100%; background: var(--bg); color: var(--text); overflow: hidden;
      font: 15px/1.35 -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif;
      -webkit-user-select: none; user-select: none; -webkit-font-smoothing: antialiased; }
    button { font: inherit; color: inherit; background: none; border: 0; padding: 0; cursor: pointer;
      touch-action: manipulation; }
    svg { display: block; }

    #bg { position: fixed; inset: -20%; background-size: cover; background-position: center;
      filter: blur(70px) saturate(1.5); opacity: 0; transform: scale(1.1); transition: opacity .8s; }
    #bg.on { opacity: .5; }
    #shade { position: fixed; inset: 0;
      background: linear-gradient(180deg, rgba(11,11,12,.25) 0%, rgba(11,11,12,.55) 45%, rgba(11,11,12,.92) 100%); }

    main { position: fixed; inset: 0; bottom: calc(58px + var(--bottom)); }
    .view { position: absolute; inset: 0; display: none; padding: calc(var(--top) + 14px) 22px 18px; }
    .view.active { display: flex; flex-direction: column; }
    .scroll { overflow-y: auto; -webkit-overflow-scrolling: touch; margin: 0 -22px; padding: 0 22px 12px; flex: 1; }
    h1 { font-size: 28px; font-weight: 750; letter-spacing: -.02em; margin: 6px 0 14px; }

    /* Now Playing */
    #playing { justify-content: center; gap: 0; }
    .cover-wrap { position: relative; margin: 0 auto; aspect-ratio: 1; border-radius: 10px; overflow: hidden;
      width: min(100%, calc(100dvh - 58px - var(--top) - var(--bottom) - 385px));
      background: rgba(255,255,255,.05); box-shadow: 0 18px 50px rgba(0,0,0,.55);
      transition: transform .35s cubic-bezier(.3,.7,.4,1); }
    .paused .cover-wrap { transform: scale(.9); }
    .cover-wrap img { position: absolute; inset: 0; width: 100%; height: 100%; object-fit: cover;
      opacity: 0; transition: opacity .45s; }
    .cover-wrap img.on { opacity: 1; }
    #nocover { position: absolute; inset: 0; display: grid; place-items: center; color: var(--tertiary); }
    .meta { margin-top: 26px; min-height: 64px; }
    #title { font-size: 21px; font-weight: 700; letter-spacing: -.01em; white-space: nowrap; overflow: hidden;
      text-overflow: ellipsis; }
    #artist { font-size: 16px; color: rgba(240,240,240,.62); margin-top: 2px; white-space: nowrap; overflow: hidden;
      text-overflow: ellipsis; }
    #quality { font-size: 11px; font-weight: 650; letter-spacing: .04em; color: var(--secondary); margin-top: 6px;
      text-transform: uppercase; }
    #quality.hires { color: var(--hires); }

    .slider { position: relative; height: 34px; touch-action: none; cursor: pointer; }
    .slider .bar { position: absolute; left: 0; right: 0; top: 50%; height: 4px; margin-top: -2px; border-radius: 3px;
      background: rgba(255,255,255,.18); overflow: hidden; transition: height .15s, margin-top .15s; }
    .slider .fill { position: absolute; inset: 0; right: auto; width: 0; background: rgba(255,255,255,.8); }
    .slider.drag .bar { height: 8px; margin-top: -4px; }
    .slider.drag .fill { background: #fff; }
    .seek { margin-top: 10px; }
    .times { display: flex; justify-content: space-between; margin-top: -4px; font-size: 11.5px; font-weight: 550;
      color: var(--secondary); font-variant-numeric: tabular-nums; }

    .transport { display: flex; align-items: center; justify-content: space-between; margin: 14px -6px 0; }
    .transport button { width: 54px; height: 54px; display: grid; place-items: center; border-radius: 50%;
      transition: transform .12s, opacity .2s; }
    .transport button:active { transform: scale(.88); }
    .transport .small { width: 44px; height: 44px; color: var(--secondary); position: relative; }
    .transport .small.on { color: var(--text); }
    .transport .small.on::after { content: ""; position: absolute; bottom: 4px; left: 50%; width: 4px; height: 4px;
      margin-left: -2px; border-radius: 50%; background: currentColor; }
    #play { width: 74px; height: 74px; background: #fff; color: #000; box-shadow: 0 8px 24px rgba(0,0,0,.4); }
    button:disabled { opacity: .35; }

    .volume { display: flex; align-items: center; gap: 12px; margin-top: 16px; color: var(--secondary); }
    .volume .slider { flex: 1; }
    #device { text-align: center; font-size: 12px; color: var(--secondary); margin-top: 8px; min-height: 16px; }
    #device .dot { display: inline-block; width: 6px; height: 6px; border-radius: 50%; background: var(--perfect);
      margin-right: 6px; vertical-align: 1px; }

    /* Lists */
    .row { display: flex; align-items: center; gap: 12px; padding: 7px 0; width: 100%; text-align: left; }
    .row:active { opacity: .6; }
    .row img, .row .ph { width: 46px; height: 46px; border-radius: 5px; object-fit: cover; flex: none;
      background: rgba(255,255,255,.06); }
    .row .txt { flex: 1; min-width: 0; }
    .row .t { font-size: 15px; font-weight: 550; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
    .row .a { font-size: 13px; color: var(--secondary); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
    .row .d { font-size: 12px; color: var(--tertiary); font-variant-numeric: tabular-nums; }
    .empty { color: var(--secondary); text-align: center; margin-top: 40%; font-size: 15px; }
    .empty small { display: block; color: var(--tertiary); margin-top: 4px; font-size: 13px; }

    #search { width: 100%; height: 38px; border: 0; border-radius: 10px; background: var(--surface); color: var(--text);
      font: inherit; font-size: 16px; padding: 0 12px; margin-bottom: 14px; outline: none; -webkit-user-select: text; }
    #search::placeholder { color: var(--tertiary); }
    .grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 18px 14px; }
    @media (min-width: 600px) { .grid { grid-template-columns: repeat(3, minmax(0, 1fr)); } }
    .tile { text-align: left; min-width: 0; }
    .tile:active { opacity: .6; }
    .tile .art { position: relative; aspect-ratio: 1; border-radius: 7px; overflow: hidden; background: rgba(255,255,255,.06);
      box-shadow: 0 6px 18px rgba(0,0,0,.35); }
    .tile .art img { width: 100%; height: 100%; object-fit: cover; display: block; }
    .tile .now { position: absolute; right: 7px; bottom: 7px; width: 26px; height: 26px; border-radius: 50%;
      background: rgba(0,0,0,.6); display: grid; place-items: center; color: #fff; }
    .tile .t { font-size: 14px; font-weight: 600; margin-top: 7px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
    .tile .a { font-size: 12.5px; color: var(--secondary); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }

    .pane { display: flex; flex-direction: column; flex: 1; min-height: 0; }
    .pane[hidden] { display: none; }
    .back { display: flex; align-items: center; gap: 2px; font-size: 16px; color: var(--text); opacity: .85;
      height: 36px; margin: -4px 0 4px -6px; align-self: flex-start; padding-right: 10px; }
    .back:active { opacity: .5; }
    .dhead { text-align: center; padding-top: 4px; }
    .dcover { width: 62%; max-width: 280px; margin: 0 auto; aspect-ratio: 1; border-radius: 8px; overflow: hidden;
      background: rgba(255,255,255,.06); box-shadow: 0 14px 40px rgba(0,0,0,.5); }
    .dcover img { width: 100%; height: 100%; object-fit: cover; display: block; }
    #dTitle { font-size: 21px; font-weight: 700; letter-spacing: -.01em; margin-top: 16px; }
    #dSub { font-size: 14px; color: var(--secondary); margin-top: 3px; }
    #dQuality { font-size: 10.5px; font-weight: 650; letter-spacing: .05em; color: var(--tertiary); margin-top: 6px;
      text-transform: uppercase; }
    .dbuttons { display: flex; gap: 12px; margin: 16px 0 10px; }
    .pill { flex: 1; height: 44px; border-radius: 12px; background: var(--surface); display: flex; align-items: center;
      justify-content: center; gap: 7px; font-size: 15px; font-weight: 650; }
    .pill:active { opacity: .6; }
    .pill.primary { background: #fff; color: #000; }
    .disc { font-size: 11px; font-weight: 700; letter-spacing: .08em; color: var(--tertiary); text-transform: uppercase;
      margin: 16px 0 4px; }
    .trow { display: flex; align-items: center; gap: 12px; width: 100%; text-align: left; padding: 11px 0;
      border-bottom: 1px solid var(--hairline); }
    .trow:active { opacity: .55; }
    .trow .n { width: 22px; flex: none; text-align: center; font-size: 14px; color: var(--tertiary);
      font-variant-numeric: tabular-nums; display: grid; place-items: center; }
    .trow .txt { flex: 1; min-width: 0; }
    .trow .t { font-size: 15.5px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
    .trow .a { font-size: 12.5px; color: var(--secondary); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
    .trow .d { font-size: 13px; color: var(--tertiary); font-variant-numeric: tabular-nums; }
    .trow.on .t { font-weight: 700; }
    .trow.on .n { color: var(--text); }
    .eq rect { transform-origin: bottom; transform-box: fill-box; animation: eq .9s ease-in-out infinite alternate; }
    .eq rect:nth-child(2) { animation-delay: -.35s; }
    .eq rect:nth-child(3) { animation-delay: -.65s; }
    @keyframes eq { from { transform: scaleY(.3); } to { transform: scaleY(1); } }
    .paused .eq rect { animation-play-state: paused; }
    #artist, .cover-wrap { cursor: pointer; }

    nav { position: fixed; left: 0; right: 0; bottom: 0; height: calc(58px + var(--bottom)); padding-bottom: var(--bottom);
      display: flex; background: rgba(14,14,15,.82); -webkit-backdrop-filter: blur(24px) saturate(1.6);
      backdrop-filter: blur(24px) saturate(1.6); border-top: 1px solid var(--hairline); }
    nav button { flex: 1; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 3px;
      font-size: 10.5px; font-weight: 550; color: var(--tertiary); }
    nav button.active { color: var(--text); }

    #banner { position: fixed; left: 16px; right: 16px; top: calc(var(--top) + 10px); padding: 11px 14px; border-radius: 12px;
      background: rgba(60,40,20,.92); color: #f6dcb4; font-size: 13.5px; text-align: center; z-index: 10;
      transform: translateY(-160%); transition: transform .3s; -webkit-backdrop-filter: blur(20px); }
    #banner.on { transform: none; }
    </style>
    </head>
    <body class="paused">
    <div id="bg"></div><div id="shade"></div>

    <main>
      <section id="playing" class="view active">
        <div class="cover-wrap">
          <div id="nocover"><svg width="64" height="64" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.1"><circle cx="12" cy="12" r="9.5"/><circle cx="12" cy="12" r="2.5"/></svg></div>
          <img id="coverA" alt=""><img id="coverB" alt="">
        </div>
        <div class="meta">
          <div id="title">Nothing playing</div>
          <div id="artist">Pick something in Albums</div>
          <div id="quality"></div>
        </div>
        <div class="seek">
          <div class="slider" id="seek"><div class="bar"><div class="fill"></div></div></div>
          <div class="times"><span id="elapsed">0:00</span><span id="remaining">0:00</span></div>
        </div>
        <div class="transport">
          <button id="shuffle" class="small" aria-label="Shuffle"><svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M3 7h3c2.2 0 3.4 1.1 4.6 2.9l2.8 4.2C14.6 15.9 15.8 17 18 17h3M3 17h3c1.5 0 2.5-.5 3.4-1.4M14.6 8.4C15.5 7.5 16.5 7 18 7h3M18.5 4.5 21 7l-2.5 2.5M18.5 14.5 21 17l-2.5 2.5"/></svg></button>
          <button id="prev" aria-label="Previous" disabled><svg width="34" height="34" viewBox="0 0 24 24" fill="currentColor" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"><path d="M20.5 6.8v10.4L12.6 12zM11.4 6.8v10.4L3.5 12z"/></svg></button>
          <button id="play" aria-label="Play" disabled><svg id="playIcon" width="30" height="30" viewBox="0 0 24 24" fill="currentColor"><path d="M8 5.6v12.8c0 .8.9 1.3 1.6.9l10.2-6.4c.6-.4.6-1.3 0-1.7L9.6 4.8C8.9 4.3 8 4.8 8 5.6z"/></svg></button>
          <button id="next" aria-label="Next" disabled><svg width="34" height="34" viewBox="0 0 24 24" fill="currentColor" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"><path d="M3.5 6.8v10.4l7.9-5.2zM12.6 6.8v10.4l7.9-5.2z"/></svg></button>
          <button id="repeat" class="small" aria-label="Repeat"><svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M17 2.5 20 5.5 17 8.5M4 11.5v-1a5 5 0 0 1 5-5h11M7 21.5l-3-3 3-3M20 12.5v1a5 5 0 0 1-5 5H4"/><text id="repeatOne" x="12" y="15.2" font-size="7.5" font-weight="800" text-anchor="middle" fill="currentColor" stroke="none" font-family="-apple-system, system-ui" style="display:none">1</text></svg></button>
        </div>
        <div class="volume">
          <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><path d="M3.5 9.2h3.3L11 5.6v12.8l-4.2-3.6H3.5z"/></svg>
          <div class="slider" id="volume"><div class="bar"><div class="fill"></div></div></div>
          <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M3.5 9.2h3.3L11 5.6v12.8l-4.2-3.6H3.5z" fill="currentColor" stroke="none"/><path d="M14.5 9.2a4 4 0 0 1 0 5.6M17.4 6.4a8 8 0 0 1 0 11.2"/></svg>
        </div>
        <div id="device"></div>
      </section>

      <section id="queue" class="view">
        <h1>Up Next</h1>
        <div class="scroll" id="queueList"></div>
      </section>

      <section id="albums" class="view">
        <div class="pane" id="albumList">
          <h1>Albums</h1>
          <input id="search" type="search" placeholder="Search albums and artists" autocomplete="off" autocorrect="off" spellcheck="false">
          <div class="scroll"><div class="grid" id="albumGrid"></div></div>
        </div>
        <div class="pane" id="albumDetail" hidden>
          <button class="back" id="back"><svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M15 5l-7 7 7 7"/></svg>Albums</button>
          <div class="scroll" id="detailScroll">
            <div class="dhead">
              <div class="dcover"><img id="dArt" alt=""></div>
              <div id="dTitle"></div>
              <div id="dSub"></div>
              <div id="dQuality"></div>
            </div>
            <div class="dbuttons">
              <button class="pill primary" id="dPlay"><svg width="15" height="15" viewBox="0 0 24 24" fill="currentColor"><path d="M7 4.8v14.4c0 .8.9 1.3 1.6.9l11.3-7.2c.6-.4.6-1.3 0-1.7L8.6 3.9C7.9 3.5 7 4 7 4.8z"/></svg>Play</button>
              <button class="pill" id="dShuffle"><svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.1" stroke-linecap="round" stroke-linejoin="round"><path d="M3 7h3c2.2 0 3.4 1.1 4.6 2.9l2.8 4.2C14.6 15.9 15.8 17 18 17h3M3 17h3c1.5 0 2.5-.5 3.4-1.4M14.6 8.4C15.5 7.5 16.5 7 18 7h3M18.5 4.5 21 7l-2.5 2.5M18.5 14.5 21 17l-2.5 2.5"/></svg>Shuffle</button>
            </div>
            <div id="dTracks"></div>
          </div>
        </div>
      </section>
    </main>

    <nav>
      <button data-view="playing" class="active"><svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M9 18V5.5l11-2V16"/><circle cx="6.5" cy="18" r="2.5"/><circle cx="17.5" cy="16" r="2.5"/></svg>Playing</button>
      <button data-view="queue"><svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M9 6h12M9 12h12M9 18h12"/><circle cx="4" cy="6" r=".8" fill="currentColor"/><circle cx="4" cy="12" r=".8" fill="currentColor"/><circle cx="4" cy="18" r=".8" fill="currentColor"/></svg>Up Next</button>
      <button data-view="albums"><svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"><rect x="3.5" y="3.5" width="7" height="7" rx="1.5"/><rect x="13.5" y="3.5" width="7" height="7" rx="1.5"/><rect x="3.5" y="13.5" width="7" height="7" rx="1.5"/><rect x="13.5" y="13.5" width="7" height="7" rx="1.5"/></svg>Albums</button>
    </nav>
    <div id="banner"></div>

    <script>
    "use strict";
    const $ = id => document.getElementById(id);
    const params = new URLSearchParams(location.search);
    let token = params.get("t") || "";
    try {
      if (token) localStorage.setItem("openfy.t", token); else token = localStorage.getItem("openfy.t") || "";
    } catch (e) {}

    const PLAY = '<path d="M8 5.6v12.8c0 .8.9 1.3 1.6.9l10.2-6.4c.6-.4.6-1.3 0-1.7L9.6 4.8C8.9 4.3 8 4.8 8 5.6z"/>';
    const PAUSE = '<rect x="6" y="4.5" width="4.2" height="15" rx="1.3"/><rect x="13.8" y="4.5" width="4.2" height="15" rx="1.3"/>';
    const BARS = '<svg width="13" height="13" viewBox="0 0 24 24" fill="currentColor"><rect x="3" y="9" width="4" height="12" rx="1"/><rect x="10" y="3" width="4" height="18" rx="1"/><rect x="17" y="12" width="4" height="9" rx="1"/></svg>';

    const art = (key, size) => `/art/${encodeURIComponent(key)}?s=${size}&t=${encodeURIComponent(token)}`;
    const fmt = s => {
      s = Math.max(0, Math.floor(s || 0));
      const h = Math.floor(s / 3600), m = Math.floor(s / 60) % 60, sec = String(s % 60).padStart(2, "0");
      return h ? `${h}:${String(m).padStart(2, "0")}:${sec}` : `${m}:${sec}`;
    };
    const el = (tag, cls, text) => {
      const e = document.createElement(tag);
      if (cls) e.className = cls;
      if (text != null) e.textContent = text;
      return e;
    };
    const fold = s => (s || "").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "");

    // ---- Networking ----
    let seq = 0, applied = 0, failures = 0;
    async function api(path, method, query) {
      const q = new URLSearchParams(Object.assign({}, query || {}, { t: token }));
      const res = await fetch(`/api/${path}?${q}`, { method: method || "GET", cache: "no-store" });
      if (res.status === 401) { const e = new Error("auth"); e.auth = true; throw e; }
      if (!res.ok) throw new Error(String(res.status));
      return res.json();
    }
    function failed(e) {
      failures++;
      if (e && e.auth) banner("This link no longer works. Scan the new code in Openfy on your Mac.");
      else if (failures >= 2) banner("Can’t reach Openfy. Make sure it’s open on your Mac and you’re on the same Wi-Fi.");
    }
    function banner(text) {
      const b = $("banner");
      if (text) { b.textContent = text; b.classList.add("on"); } else b.classList.remove("on");
    }
    let polling = false;
    async function refresh() {
      if (polling) return;
      polling = true;
      const my = ++seq;
      try { const s = await api("state"); if (my > applied) apply(s, my); }
      catch (e) { failed(e); }
      finally { polling = false; }
    }
    async function command(name, query) {
      const my = ++seq;
      try { const s = await api(name, "POST", query); if (my > applied) apply(s, my); }
      catch (e) { failed(e); }
    }
    setInterval(() => { if (!document.hidden) refresh(); }, 1000);
    document.addEventListener("visibilitychange", () => { if (!document.hidden) refresh(); });
    window.addEventListener("pageshow", refresh);

    // ---- Sliders (tap or drag anywhere on the bar) ----
    function slider(root, onInput, onCommit) {
      const fill = root.querySelector(".fill");
      let value = 0, dragging = false;
      const at = e => { const r = root.getBoundingClientRect(); return Math.min(1, Math.max(0, (e.clientX - r.left) / r.width)); };
      const set = v => { value = v; fill.style.width = (v * 100) + "%"; };
      root.addEventListener("pointerdown", e => {
        dragging = true; root.setPointerCapture(e.pointerId); root.classList.add("drag");
        set(at(e)); onInput && onInput(value);
      });
      root.addEventListener("pointermove", e => { if (dragging) { set(at(e)); onInput && onInput(value); } });
      const end = () => { if (!dragging) return; dragging = false; root.classList.remove("drag"); onCommit(value); };
      root.addEventListener("pointerup", end);
      root.addEventListener("pointercancel", end);
      return { set: v => { if (!dragging) set(v); }, get dragging() { return dragging; } };
    }

    // ---- State ----
    let state = null, stateAt = 0, holdVolumeUntil = 0, coverKey = undefined, front = "coverA";
    let queueSig = "", albumsLoaded = false, albums = [];

    function apply(s, my) {
      applied = my; failures = 0; banner(null);
      state = s; stateAt = performance.now();
      const t = s.track;
      document.body.classList.toggle("paused", !s.playing);
      $("playIcon").innerHTML = s.playing ? PAUSE : PLAY;
      $("play").setAttribute("aria-label", s.playing ? "Pause" : "Play");
      for (const id of ["play", "prev", "next"]) $(id).disabled = !t;
      $("title").textContent = t ? t.title : "Nothing playing";
      $("artist").textContent = t ? [t.artist, t.album].filter(Boolean).join(" — ") : "Pick something in Albums";
      $("quality").textContent = t ? t.quality : "";
      $("quality").classList.toggle("hires", !!(t && t.hiRes));
      document.title = t ? `${t.title} · ${t.artist}` : "Openfy";
      setCover(t && t.art);

      $("shuffle").classList.toggle("on", s.shuffle);
      $("repeat").classList.toggle("on", s.repeat !== "off");
      $("repeatOne").style.display = s.repeat === "one" ? "" : "none";
      if (performance.now() > holdVolumeUntil) volume.set(s.volume);

      const dev = $("device");
      dev.textContent = "";
      if (s.device) {
        if (s.bitPerfect) dev.appendChild(el("span", "dot"));
        dev.appendChild(document.createTextNode(s.device + (s.bitPerfect ? " · Bit-perfect" : "")
          + (s.volumeKind === "app" ? " · Openfy volume" : "")));
      }
      renderQueue(s);
      if (albumsLoaded) markPlayingAlbum();
      markDetail();
    }

    function setCover(key) {
      if (key === coverKey) return;
      coverKey = key;
      const bg = $("bg");
      $("nocover").style.display = key ? "none" : "";
      if (!key) { $("coverA").classList.remove("on"); $("coverB").classList.remove("on"); bg.classList.remove("on"); return; }
      const back = front === "coverA" ? "coverB" : "coverA";
      const img = $(back), url = art(key, "l");
      img.onload = () => {
        if (coverKey !== key) return;
        img.classList.add("on"); $(front).classList.remove("on"); front = back;
        bg.style.backgroundImage = `url("${url}")`; bg.classList.add("on");
      };
      img.src = url;
    }

    function renderQueue(s) {
      const list = s.upNext || [];
      const sig = (s.index ?? "") + "|" + list.map(r => r.i + r.title).join("|");
      if (sig === queueSig) return;
      queueSig = sig;
      const box = $("queueList");
      box.textContent = "";
      if (!list.length) {
        const e = el("div", "empty", "Nothing up next");
        e.appendChild(el("small", null, "Play an album to fill the queue"));
        box.appendChild(e);
        return;
      }
      for (const r of list) {
        const row = el("button", "row");
        if (r.art) { const img = el("img"); img.loading = "lazy"; img.src = art(r.art, "t"); row.appendChild(img); }
        else row.appendChild(el("div", "ph"));
        const txt = el("div", "txt");
        txt.appendChild(el("div", "t", r.title));
        txt.appendChild(el("div", "a", r.artist));
        row.appendChild(txt);
        row.appendChild(el("div", "d", fmt(r.duration)));
        row.onclick = () => { command("jump", { v: r.i }); show("playing"); };
        box.appendChild(row);
      }
    }

    // ---- Albums ----
    async function loadAlbums() {
      try { albums = await api("albums"); albumsLoaded = true; renderAlbums(); } catch (e) { failed(e); }
    }
    function renderAlbums() {
      const q = fold($("search").value).trim().split(/\s+/).filter(Boolean);
      const grid = $("albumGrid");
      grid.textContent = "";
      const shown = albums.filter(a => { const h = fold(a.title + " " + a.artist + " " + (a.year || "")); return q.every(w => h.includes(w)); });
      if (!shown.length) { grid.appendChild(el("div", "empty", albums.length ? "No matches" : "No albums yet")); return; }
      for (const a of shown) {
        const tile = el("button", "tile");
        tile.dataset.id = a.id;
        const box = el("div", "art");
        if (a.art) { const img = el("img"); img.loading = "lazy"; img.src = art(a.art, "t"); box.appendChild(img); }
        tile.appendChild(box);
        tile.appendChild(el("div", "t", a.title));
        tile.appendChild(el("div", "a", a.year ? `${a.artist} · ${a.year}` : a.artist));
        tile.onclick = () => openAlbum(a.id);
        grid.appendChild(tile);
      }
      markPlayingAlbum();
    }
    function markPlayingAlbum() {
      const id = state && state.track && state.track.albumID;
      for (const tile of $("albumGrid").children) {
        const box = tile.querySelector && tile.querySelector(".art");
        if (!box) continue;
        const badge = box.querySelector(".now");
        if (tile.dataset.id === id && !badge) { const b = el("div", "now"); b.innerHTML = BARS; box.appendChild(b); }
        else if (tile.dataset.id !== id && badge) badge.remove();
      }
    }
    $("search").addEventListener("input", renderAlbums);

    // ---- Album page ----
    let detail = null;
    const EQ = '<svg class="eq" width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><rect x="3" y="6" width="4.5" height="15" rx="1"/><rect x="9.75" y="3" width="4.5" height="18" rx="1"/><rect x="16.5" y="9" width="4.5" height="12" rx="1"/></svg>';
    async function openAlbum(id) {
      if (!id) return;
      show("albums", true);
      let a;
      try { a = await api("album", "GET", { id }); } catch (e) { failed(e); return; }
      detail = a;
      $("dArt").src = a.art ? art(a.art, "l") : "";
      $("dArt").style.visibility = a.art ? "" : "hidden";
      $("dTitle").textContent = a.title;
      const mins = Math.round(a.duration / 60);
      $("dSub").textContent = [a.artist, a.year, `${a.tracks.length} songs`, mins >= 60 ? `${Math.floor(mins / 60)} hr ${mins % 60} min` : `${mins} min`].filter(Boolean).join(" · ");
      $("dQuality").textContent = a.quality || "";
      const box = $("dTracks");
      box.textContent = "";
      let disc = null;
      a.tracks.forEach((t, i) => {
        if (a.discCount > 1 && t.disc !== disc) { disc = t.disc; box.appendChild(el("div", "disc", `Disc ${disc || 1}`)); }
        const row = el("button", "trow");
        row.dataset.i = i;
        row.appendChild(el("div", "n", String(t.n || i + 1)));
        const txt = el("div", "txt");
        txt.appendChild(el("div", "t", t.title));
        if (t.artist) txt.appendChild(el("div", "a", t.artist));
        row.appendChild(txt);
        row.appendChild(el("div", "d", fmt(t.duration)));
        row.onclick = () => { markDetail(i); command("album", { id: a.id, start: i }); };
        box.appendChild(row);
      });
      $("albumList").hidden = true;
      $("albumDetail").hidden = false;
      $("detailScroll").scrollTop = 0;
      markDetail();
    }
    // Highlights the playing song (or `pending`, right after a tap).
    function markDetail(pending) {
      if (!detail) return;
      const t = state && state.track;
      const playing = pending != null ? pending : (t && t.albumID === detail.id ? t.albumIndex : -1);
      for (const row of $("dTracks").querySelectorAll(".trow")) {
        const i = +row.dataset.i, on = i === playing, n = row.querySelector(".n");
        if (on === row.classList.contains("on")) continue;
        row.classList.toggle("on", on);
        if (on) n.innerHTML = EQ; else n.textContent = String(detail.tracks[i].n || i + 1);
      }
    }
    function closeAlbum() {
      detail = null;
      $("albumDetail").hidden = true;
      $("albumList").hidden = false;
    }
    $("back").onclick = closeAlbum;
    $("dPlay").onclick = () => { if (detail) { markDetail(0); command("album", { id: detail.id }); } };
    $("dShuffle").onclick = () => { if (detail) command("album", { id: detail.id, shuffle: 1 }); };
    // Tap the cover or "Artist — Album" on the Playing screen to open that album.
    const openCurrent = () => { const t = state && state.track; if (t && t.albumID) openAlbum(t.albumID); };
    $("artist").onclick = openCurrent;
    document.querySelector(".cover-wrap").onclick = openCurrent;

    // ---- Tabs ----
    function show(view, keepDetail) {
      const was = document.querySelector(".view.active");
      // Tapping Albums again while an album is open goes back to the grid.
      if (view === "albums" && !keepDetail && was && was.id === "albums" && detail) closeAlbum();
      for (const v of document.querySelectorAll(".view")) v.classList.toggle("active", v.id === view);
      for (const b of document.querySelectorAll("nav button")) b.classList.toggle("active", b.dataset.view === view);
      if (view === "albums" && (!albumsLoaded || !albums.length)) loadAlbums();
    }
    for (const b of document.querySelectorAll("nav button")) b.onclick = () => show(b.dataset.view);

    // ---- Controls ----
    $("play").onclick = () => {
      if (state) { state.position = currentPosition(); stateAt = performance.now(); state.playing = !state.playing;
        document.body.classList.toggle("paused", !state.playing); $("playIcon").innerHTML = state.playing ? PAUSE : PLAY; }
      command("toggle");
    };
    $("next").onclick = () => command("next");
    $("prev").onclick = () => command("prev");
    $("shuffle").onclick = () => command("shuffle");
    $("repeat").onclick = () => command("repeat");

    const seek = slider($("seek"), v => {
      const d = state && state.track ? state.track.duration : 0;
      $("elapsed").textContent = fmt(v * d); $("remaining").textContent = "-" + fmt(d - v * d);
    }, v => {
      if (!state || !state.track) return;
      const target = v * state.track.duration;
      state.position = target; stateAt = performance.now();
      command("seek", { v: target.toFixed(2) });
    });

    let lastVolumeSent = 0, volumeTimer = null;
    const volume = slider($("volume"), v => {
      holdVolumeUntil = performance.now() + 1500;
      const now = performance.now();
      clearTimeout(volumeTimer);
      if (now - lastVolumeSent > 120) { lastVolumeSent = now; command("volume", { v: v.toFixed(3) }); }
      else volumeTimer = setTimeout(() => { lastVolumeSent = performance.now(); command("volume", { v: v.toFixed(3) }); }, 120);
    }, v => {
      clearTimeout(volumeTimer);
      holdVolumeUntil = performance.now() + 1500;
      command("volume", { v: v.toFixed(3) });
    });

    // ---- Position, interpolated between polls ----
    function currentPosition() {
      if (!state || !state.track) return 0;
      let p = state.position + (state.playing ? (performance.now() - stateAt) / 1000 : 0);
      return Math.min(Math.max(0, p), state.track.duration);
    }
    let lastShown = -1;
    function frame() {
      if (state && !seek.dragging) {
        const d = state.track ? state.track.duration : 0, p = currentPosition();
        seek.set(d ? p / d : 0);
        const whole = Math.floor(p) + d * 1000;
        if (whole !== lastShown) { lastShown = whole; $("elapsed").textContent = fmt(p); $("remaining").textContent = d ? "-" + fmt(d - p) : "0:00"; }
      }
      requestAnimationFrame(frame);
    }
    requestAnimationFrame(frame);

    if (!token) banner("Open this page with the link or QR code from Openfy on your Mac.");
    else refresh();
    </script>
    </body>
    </html>
    """#
}
