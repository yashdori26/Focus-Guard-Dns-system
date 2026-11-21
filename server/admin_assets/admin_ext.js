/* FocusDNS Admin — extension layer: themes, charts, hotkeys, QR provisioning, categories, telescope v2 */
(function () {
  'use strict';

  const $ = (s, r) => (r || document).querySelector(s);
  const $$ = (s, r) => Array.from((r || document).querySelectorAll(s));
  const esc = (v) => String(v == null ? '' : v).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const store = {
    get(k, d) { try { const v = localStorage.getItem('fdns.' + k); return v == null ? d : JSON.parse(v); } catch (e) { return d; } },
    set(k, v) { try { localStorage.setItem('fdns.' + k, JSON.stringify(v)); } catch (e) {} },
  };
  const css = (name) => getComputedStyle(document.documentElement).getPropertyValue(name).trim();

  /* =============================== Toasts =============================== */
  function toast(msg, isErr) {
    let host = $('#toast-host');
    if (!host) { host = document.createElement('div'); host.id = 'toast-host'; document.body.appendChild(host); }
    const t = document.createElement('div');
    t.className = 'toast' + (isErr ? ' err' : '');
    t.textContent = msg;
    host.appendChild(t);
    setTimeout(() => { t.style.opacity = '0'; t.style.transition = 'opacity .3s'; setTimeout(() => t.remove(), 320); }, 3200);
  }
  window.alert = (m) => toast(String(m));
  window.fdnsToast = toast;

  async function api(path, method, body) {
    const opt = { method: method || 'GET', headers: { 'Content-Type': 'application/json' } };
    if (body !== undefined) opt.body = JSON.stringify(body);
    const res = await fetch(path, opt);
    if (res.status === 401) { if (typeof showAuth === 'function') showAuth(); throw new Error('unauthorized'); }
    return res.json();
  }

  /* =============================== Theme =============================== */
  function applyTheme(t) {
    document.documentElement.setAttribute('data-theme', t);
    store.set('theme', t);
    const b = $('#theme-btn'); if (b) b.textContent = t === 'light' ? '☾' : '☀';
    Charts.redraw();
  }
  function toggleTheme() { applyTheme(store.get('theme', 'dark') === 'dark' ? 'light' : 'dark'); }
  document.documentElement.setAttribute('data-theme', store.get('theme', matchMedia('(prefers-color-scheme: light)').matches ? 'light' : 'dark'));

  /* =============================== Charts =============================== */
  const MAX_POINTS = 720;               // 720 samples * 5s = 1h
  const SAMPLE_MS = 5000;
  const series = store.get('series', []);   // {t, qps, total, blocked}
  let range = store.get('range', 300);      // seconds
  let lastTotals = null;

  const Charts = {
    redraw() { drawTraffic(); drawDonut(); },
  };

  function visibleSeries() {
    const cutoff = Date.now() - range * 1000;
    return series.filter(p => p.t >= cutoff);
  }

  function setupCanvas(cv) {
    const dpr = window.devicePixelRatio || 1;
    const r = cv.getBoundingClientRect();
    if (!r.width) return null;
    cv.width = Math.round(r.width * dpr); cv.height = Math.round(r.height * dpr);
    const ctx = cv.getContext('2d'); ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    return { ctx, w: r.width, h: r.height };
  }

  function drawTraffic() {
    const cv = $('#traffic-canvas'); if (!cv) return;
    const c = setupCanvas(cv); if (!c) return;
    const { ctx, w, h } = c;
    ctx.clearRect(0, 0, w, h);
    const pts = visibleSeries();
    const ink = css('--ink'), red = css('--vermilion'), border = css('--border');
    const padL = 34, padB = 18, padT = 8, padR = 6;
    const cw = w - padL - padR, ch = h - padT - padB;

    // d(total)/dt as queries-per-interval, blocked likewise
    const rows = [];
    for (let i = 1; i < pts.length; i++) {
      const dt = Math.max(1, (pts[i].t - pts[i - 1].t) / 1000);
      const dq = pts[i].total - pts[i - 1].total, db = pts[i].blocked - pts[i - 1].blocked;
      rows.push({ t: pts[i].t, q: dq >= 0 ? dq / dt : 0, b: db >= 0 ? db / dt : 0 });
    }
    cv._rows = rows; cv._geo = { padL, padT, cw, ch, w, h };
    const max = Math.max(1, ...rows.map(r => r.q)) * 1.15;

    ctx.strokeStyle = border; ctx.lineWidth = 1; ctx.fillStyle = css('--dimmed'); ctx.font = '10px JetBrains Mono, monospace';
    for (let g = 0; g <= 3; g++) {
      const y = padT + ch - (ch * g / 3);
      ctx.beginPath(); ctx.moveTo(padL, y); ctx.lineTo(w - padR, y); ctx.stroke();
      ctx.fillText((max * g / 3).toFixed(max < 5 ? 1 : 0), 2, y + 3);
    }
    if (rows.length < 2) {
      ctx.fillStyle = css('--muted'); ctx.font = '12px Plus Jakarta Sans, sans-serif';
      ctx.fillText('Collecting samples…', padL + 10, padT + ch / 2);
      return;
    }
    const X = i => padL + (cw * i / (rows.length - 1));
    const Y = v => padT + ch - (ch * Math.min(v, max) / max);

    function line(key, color, fillAlpha) {
      ctx.beginPath();
      rows.forEach((r, i) => { const x = X(i), y = Y(r[key]); if (i === 0) ctx.moveTo(x, y); else {
        const px = X(i - 1), py = Y(rows[i - 1][key]), mx = (px + x) / 2;
        ctx.bezierCurveTo(mx, py, mx, y, x, y);
      } });
      ctx.strokeStyle = color; ctx.lineWidth = 2; ctx.stroke();
      ctx.lineTo(X(rows.length - 1), padT + ch); ctx.lineTo(X(0), padT + ch); ctx.closePath();
      const g = ctx.createLinearGradient(0, padT, 0, padT + ch);
      g.addColorStop(0, color + fillAlpha); g.addColorStop(1, color + '00');
      ctx.fillStyle = g; ctx.fill();
    }
    line('q', hex(ink), '38');
    line('b', hex(red), '55');

    ctx.fillStyle = css('--dimmed'); ctx.font = '10px JetBrains Mono, monospace';
    const f = t => new Date(t).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: range <= 300 ? '2-digit' : undefined });
    ctx.fillText(f(rows[0].t), padL, h - 4);
    const last = f(rows[rows.length - 1].t); ctx.fillText(last, w - padR - ctx.measureText(last).width, h - 4);

    if (cv._hover != null) {
      const i = cv._hover, x = X(i);
      ctx.strokeStyle = css('--border-bright'); ctx.beginPath(); ctx.moveTo(x, padT); ctx.lineTo(x, padT + ch); ctx.stroke();
      [['q', ink], ['b', red]].forEach(([k, col]) => { ctx.fillStyle = col; ctx.beginPath(); ctx.arc(x, Y(rows[i][k]), 3.5, 0, 7); ctx.fill(); });
    }
  }
  // normalise "rgb(...)" / "#abc" css values to #rrggbb so alpha suffixes work
  function hex(c) {
    c = c.trim();
    if (/^#[0-9a-f]{6}$/i.test(c)) return c;
    if (/^#[0-9a-f]{3}$/i.test(c)) return '#' + c.slice(1).split('').map(x => x + x).join('');
    const m = c.match(/\d+/g); if (!m) return '#888888';
    return '#' + m.slice(0, 3).map(n => (+n).toString(16).padStart(2, '0')).join('');
  }

  function bindTrafficHover() {
    const cv = $('#traffic-canvas'), tip = $('#traffic-tip'); if (!cv) return;
    cv.addEventListener('mousemove', e => {
      const rows = cv._rows, g = cv._geo; if (!rows || rows.length < 2) return;
      const r = cv.getBoundingClientRect(), x = e.clientX - r.left;
      const i = Math.max(0, Math.min(rows.length - 1, Math.round((x - g.padL) / g.cw * (rows.length - 1))));
      cv._hover = i; drawTraffic();
      const row = rows[i];
      tip.style.opacity = 1; tip.style.left = (g.padL + g.cw * i / (rows.length - 1)) + 'px'; tip.style.top = '30px';
      tip.textContent = `${new Date(row.t).toLocaleTimeString()} · ${row.q.toFixed(2)} q/s · ${row.b.toFixed(2)} blocked/s`;
    });
    cv.addEventListener('mouseleave', () => { cv._hover = null; tip.style.opacity = 0; drawTraffic(); });
  }

  let lastMetrics = null;
  function drawDonut() {
    const cv = $('#donut-canvas'); if (!cv) return;
    const c = setupCanvas(cv); if (!c) return;
    const { ctx, w, h } = c; ctx.clearRect(0, 0, w, h);
    const m = lastMetrics || {};
    const total = Math.max(0, m.total_queries_today || 0);
    const blocked = Math.min(total, m.total_blocked_today || 0);
    const cached = Math.min(total - blocked, m.cache_hits || 0);
    const resolved = Math.max(0, total - blocked - cached);
    const parts = [
      ['Resolved upstream', resolved, css('--ink')],
      ['Served from cache', cached, css('--blue')],
      ['Blocked', blocked, css('--vermilion')],
    ];
    const sum = parts.reduce((a, p) => a + p[1], 0);
    const cx = w / 2, cy = h / 2, R = Math.min(w, h) / 2 - 6, r = R * 0.64;
    if (!sum) {
      ctx.strokeStyle = css('--border'); ctx.lineWidth = R - r; ctx.beginPath(); ctx.arc(cx, cy, (R + r) / 2, 0, 7); ctx.stroke();
    } else {
      let a = -Math.PI / 2;
      parts.forEach(p => {
        const sweep = p[1] / sum * Math.PI * 2; if (!sweep) return;
        ctx.beginPath(); ctx.strokeStyle = p[2]; ctx.lineWidth = R - r;
        ctx.arc(cx, cy, (R + r) / 2, a, a + Math.max(0.001, sweep - 0.02)); ctx.stroke(); a += sweep;
      });
    }
    ctx.fillStyle = css('--ink'); ctx.textAlign = 'center'; ctx.font = '800 20px Plus Jakarta Sans, sans-serif';
    ctx.fillText(sum ? (blocked / sum * 100).toFixed(1) + '%' : '—', cx, cy + 3);
    ctx.fillStyle = css('--muted'); ctx.font = '600 10px Plus Jakarta Sans, sans-serif'; ctx.fillText('BLOCKED', cx, cy + 18);
    ctx.textAlign = 'start';
    const lg = $('#donut-legend');
    if (lg) lg.innerHTML = parts.map(p => `<div><span><i style="background:${p[2]}"></i>${p[0]}</span><b class="mono">${p[1].toLocaleString()}</b></div>`).join('');
  }

  async function sample() {
    try {
      const m = await fetch('/api/admin/metrics').then(r => r.ok ? r.json() : null);
      setConn(!!m);
      if (!m) return;
      lastMetrics = m;
      const now = Date.now();
      const pt = { t: now, qps: m.qps, total: m.total_queries_today, blocked: m.total_blocked_today };
      if (lastTotals && pt.total < lastTotals.total) { series.length = 0; } // daily rollover
      lastTotals = pt;
      series.push(pt);
      if (series.length > MAX_POINTS) series.splice(0, series.length - MAX_POINTS);
      store.set('series', series.slice(-MAX_POINTS));
      degradedCheck(m);
      drawTraffic(); drawDonut();
    } catch (e) { setConn(false); }
  }

  function degradedCheck(m) {
    const dot = $('#status-dot'), txt = $('#status-text'); if (!dot || m.emergency_bypass) return;
    const degraded = m.signatures_count === 0;
    dot.classList.toggle('degraded', degraded);
    if (degraded) txt.textContent = 'DEGRADED · NO SIGNATURES';
  }

  function setConn(ok) {
    const p = $('#conn-pill'); if (!p) return;
    p.className = 'conn-pill ' + (ok ? 'live' : 'down'); p.textContent = ok ? '● LIVE' : '● OFFLINE';
  }

  /* ========================= Upstream latency bars ========================= */
  window.runBenchmark = async function () {
    const btn = $('#benchmark-btn'), box = $('#benchmark-results');
    btn.disabled = true; btn.textContent = 'Benchmarking…';
    box.innerHTML = '<p style="color:var(--muted);font-size:13px">Probing upstream resolvers…</p>';
    try {
      const d = await api('/api/admin/upstream/benchmark', 'POST', {});
      const valid = d.results.filter(r => r.latency_ms >= 0);
      const top = Math.max(100, ...valid.map(r => r.latency_ms));
      const best = valid.length ? Math.min(...valid.map(r => r.latency_ms)) : -1;
      box.innerHTML = d.results.map(r => {
        const to = r.latency_ms < 0;
        const cls = to ? 'lat-bad' : r.latency_ms < 25 ? 'lat-good' : r.latency_ms < 70 ? 'lat-mid' : 'lat-bad';
        const pct = to ? 100 : Math.max(4, r.latency_ms / top * 100);
        return `<div class="lat-row"><div class="lat-top"><span><strong>${esc(r.name)}</strong> <span class="mono" style="color:var(--muted);font-size:11.5px">${esc(r.host)}</span>${r.latency_ms === best ? ' <span class="badge badge-allowed">FASTEST</span>' : ''}</span><b class="mono">${to ? 'TIMEOUT' : r.latency_ms + ' ms'}</b></div><div class="lat-track"><div class="lat-fill ${cls}" data-w="${pct}"></div></div></div>`;
      }).join('');
      requestAnimationFrame(() => $$('.lat-fill', box).forEach(el => el.style.width = el.dataset.w + '%'));
    } catch (e) { box.innerHTML = '<p style="color:var(--vermilion)">Benchmark probe failed.</p>'; }
    finally { btn.disabled = false; btn.textContent = '⚡ Run Latency Benchmark'; }
  };

  /* ============================ Category shields ============================ */
  const CATEGORIES = [
    { id: 'adult', name: 'Adult content', icon: '🔞', domains: ['pornhub.com', 'xvideos.com', 'xnxx.com', 'xhamster.com', 'redtube.com', 'youporn.com', 'onlyfans.com'] },
    { id: 'gambling', name: 'Gambling & betting', icon: '🎰', domains: ['bet365.com', 'draftkings.com', 'fanduel.com', 'stake.com', 'pokerstars.com', '1xbet.com', 'betway.com'] },
    { id: 'social', name: 'Social media', icon: '💬', domains: ['facebook.com', 'instagram.com', 'tiktok.com', 'twitter.com', 'x.com', 'snapchat.com', 'reddit.com'] },
    { id: 'dating', name: 'Dating', icon: '💘', domains: ['tinder.com', 'bumble.com', 'hinge.co', 'okcupid.com', 'match.com', 'grindr.com'] },
    { id: 'gaming', name: 'Gaming', icon: '🎮', domains: ['steampowered.com', 'epicgames.com', 'roblox.com', 'twitch.tv', 'leagueoflegends.com', 'fortnite.com'] },
    { id: 'streaming', name: 'Video streaming', icon: '📺', domains: ['youtube.com', 'netflix.com', 'primevideo.com', 'hotstar.com', 'disneyplus.com', 'hulu.com'] },
  ];
  let denySet = new Set();

  function buildCategories() {
    const pane = $('#pane-emergency'); if (!pane || $('#cat-card')) return;
    const card = document.createElement('div');
    card.className = 'card'; card.id = 'cat-card'; card.style.marginTop = '20px';
    card.innerHTML = `<h3 style="font-size:15px;margin-bottom:4px">Category Shields</h3>
      <p style="font-size:12.5px;color:var(--muted)">One-tap global enforcement. Each shield adds its domain set to the Global Denylist for every profile.</p>
      <div class="cat-grid" id="cat-grid"></div>`;
    pane.appendChild(card);
    refreshCategories();
  }
  async function refreshCategories() {
    try { const d = await api('/api/admin/global-rules'); denySet = new Set((d.rules && d.rules.denylist) || []); } catch (e) { return; }
    const grid = $('#cat-grid'); if (!grid) return;
    grid.innerHTML = CATEGORIES.map(c => {
      const hit = c.domains.filter(x => denySet.has(x)).length, on = hit === c.domains.length;
      return `<div class="cat-card ${on ? 'on' : ''}"><div><div class="cat-name">${c.icon} ${esc(c.name)}</div><div class="cat-sub">${hit}/${c.domains.length} domains blocked</div></div>
        <label class="switch"><input type="checkbox" ${on ? 'checked' : ''} data-cat="${c.id}"><span class="slider"></span></label></div>`;
    }).join('');
    $$('input[data-cat]', grid).forEach(i => i.addEventListener('change', () => setCategory(i.dataset.cat, i.checked)));
  }
  async function setCategory(id, on) {
    const c = CATEGORIES.find(x => x.id === id); if (!c) return;
    try {
      await Promise.all(c.domains.map(d => on
        ? (denySet.has(d) ? null : api('/api/admin/global-rules', 'POST', { list_type: 'deny', domain: d }))
        : (denySet.has(d) ? api(`/api/admin/global-rules/deny/${encodeURIComponent(d)}`, 'DELETE') : null)));
      toast(`${c.name} shield ${on ? 'enabled' : 'disabled'}`);
    } catch (e) { toast('Failed to update shield', true); }
    refreshCategories();
    if (typeof loadGlobalRules === 'function') loadGlobalRules();
  }

  /* ===================== Zero-touch QR provisioning ===================== */
  const CHECKSUM = '4a24cd80388b818606eb02eb55b650c4035787207dd6551724d2968a07a9e163';
  function buildBundle() {
    const o = {
      'android.app.extra.PROVISIONING_DEVICE_ADMIN_COMPONENT_NAME': 'com.focusdns.app/.FocusDeviceAdminReceiver',
      'android.app.extra.PROVISIONING_DEVICE_ADMIN_SIGNATURE_CHECKSUM': ($('#qr-checksum') || {}).value || CHECKSUM,
      'android.app.extra.PROVISIONING_DEVICE_ADMIN_PACKAGE_DOWNLOAD_LOCATION': ($('#qr-apk') || {}).value || '',
      'android.app.extra.PROVISIONING_ADMIN_EXTRAS_BUNDLE': {
        server_url: location.origin,
        tenant_id: ($('#qr-tenant') || {}).value || 'default',
        enforce_strict_uninstall_lock: !!($('#qr-strict') || {}).checked,
      },
      'android.app.extra.PROVISIONING_LEAVE_ALL_SYSTEM_APPS_ENABLED': true,
      'android.app.extra.PROVISIONING_SKIP_ENCRYPTION': false,
    };
    const ssid = ($('#qr-ssid') || {}).value;
    if (ssid) {
      o['android.app.extra.PROVISIONING_WIFI_SSID'] = ssid;
      const pw = ($('#qr-wifipw') || {}).value;
      if (pw) { o['android.app.extra.PROVISIONING_WIFI_PASSWORD'] = pw; o['android.app.extra.PROVISIONING_WIFI_SECURITY_TYPE'] = 'WPA'; }
    }
    if (!o['android.app.extra.PROVISIONING_DEVICE_ADMIN_PACKAGE_DOWNLOAD_LOCATION']) delete o['android.app.extra.PROVISIONING_DEVICE_ADMIN_PACKAGE_DOWNLOAD_LOCATION'];
    return o;
  }
  let qrLibPromise = null;
  function loadQrLib() {
    if (window.qrcode) return Promise.resolve(true);
    if (!qrLibPromise) qrLibPromise = new Promise(res => {
      const s = document.createElement('script');
      s.src = 'https://cdn.jsdelivr.net/npm/qrcode-generator@1.4.4/qrcode.min.js';
      s.onload = () => res(!!window.qrcode); s.onerror = () => res(false);
      document.head.appendChild(s);
    });
    return qrLibPromise;
  }
  async function renderQr() {
    const frame = $('#qr-frame'); if (!frame) return;
    const text = JSON.stringify(buildBundle());
    $('#qr-json').value = JSON.stringify(buildBundle(), null, 2);
    const ok = await loadQrLib();
    if (ok) {
      try {
        const q = window.qrcode(0, 'L'); q.addData(text); q.make();
        frame.innerHTML = q.createSvgTag({ cellSize: 4, margin: 0, scalable: true });
        return;
      } catch (e) { /* payload too large */ }
    }
    frame.innerHTML = `<div class="qr-fallback">QR library unavailable offline or payload too large. Copy the JSON below and paste into any QR generator:<br><br>${esc(text)}</div>`;
  }
  function buildQrModal() {
    if ($('#qr-modal')) return;
    const m = document.createElement('div');
    m.id = 'qr-modal'; m.className = 'modal-backdrop';
    m.innerHTML = `<div class="modal-box qr-modal-box" style="max-height:92vh;overflow:auto">
      <h3 class="modal-title">Zero-Touch Device Enrollment</h3>
      <p style="font-size:13px;color:var(--muted)">On a factory-reset Android device, tap the welcome screen 6 times and scan this QR to enroll as Device Owner.</p>
      <div class="qr-frame" id="qr-frame"></div>
      <div class="field"><label>APK download URL</label><input id="qr-apk" class="input-box mono" placeholder="https://your-host/focusdns.apk"></div>
      <div class="field"><label>Tenant ID</label><input id="qr-tenant" class="input-box mono" value="default"></div>
      <div class="field"><label>Signature checksum (SHA-256, URL-safe base64 or hex)</label><input id="qr-checksum" class="input-box mono" value="${CHECKSUM}"></div>
      <div style="display:grid;grid-template-columns:1fr 1fr;gap:10px"><div class="field"><label>Wi-Fi SSID (optional)</label><input id="qr-ssid" class="input-box"></div><div class="field"><label>Wi-Fi password</label><input id="qr-wifipw" type="password" class="input-box"></div></div>
      <div class="check-row"><span>Lock uninstall (Strict Mode)</span><label class="switch"><input type="checkbox" id="qr-strict" checked><span class="slider"></span></label></div>
      <div class="field"><label>Provisioning JSON</label><textarea id="qr-json" class="input-box mono" rows="6" readonly style="resize:vertical;font-size:11.5px"></textarea></div>
      <div class="modal-actions"><button class="btn btn-subtle" id="qr-copy">Copy JSON</button><button class="btn btn-primary" id="qr-close">Done</button></div></div>`;
    document.body.appendChild(m);
    m.addEventListener('click', e => { if (e.target === m) closeQr(); });
    $('#qr-close').onclick = closeQr;
    $('#qr-copy').onclick = () => { navigator.clipboard.writeText($('#qr-json').value).then(() => toast('Provisioning JSON copied')); };
    ['qr-apk', 'qr-tenant', 'qr-checksum', 'qr-ssid', 'qr-wifipw', 'qr-strict'].forEach(id => $('#' + id).addEventListener('input', renderQr));
  }
  function openQr() { buildQrModal(); $('#qr-modal').style.display = 'flex'; renderQr(); }
  function closeQr() { const m = $('#qr-modal'); if (m) m.style.display = 'none'; }
  window.openQrProvisioning = openQr;

  /* ============================ Fleet search ============================ */
  function buildFleetTools() {
    const hdr = $('#pane-fleet .pane-header'); if (!hdr || $('#fleet-search')) return;
    const old = hdr.querySelector('button'); if (!old) return;
    const bar = document.createElement('div'); bar.className = 'toolbar';
    bar.innerHTML = `<div class="search-box"><input id="fleet-search" class="input-box" placeholder="Search profiles…"></div>
      <button class="btn btn-subtle btn-sm" id="qr-open-btn">📱 Enroll Device (QR)</button>`;
    old.replaceWith(bar);
    const add = document.createElement('button');
    add.className = 'btn btn-primary btn-sm'; add.textContent = '+ Provision Profile';
    add.onclick = () => window.openNewProfileModal();
    bar.appendChild(add);
    $('#qr-open-btn').onclick = openQr;
    $('#fleet-search').addEventListener('input', e => {
      const q = e.target.value.toLowerCase();
      $$('#profiles-table-body tr').forEach(tr => { tr.style.display = tr.textContent.toLowerCase().includes(q) ? '' : 'none'; });
    });
  }

  /* ============================ Telescope v2 ============================ */
  const tele = { rows: [], filter: 'all', q: '', paused: false, total: 0, blocked: 0, src: null, open: null };
  const TELE_MAX = 200;

  function teleBadge(ev) {
    if (ev.status === 'blocked') return '<span class="badge badge-blocked">BLOCKED</span>';
    if (ev.reason && String(ev.reason).includes('RAM Cache')) return '<span class="badge badge-cache">CACHE 0ms</span>';
    if (ev.status === 'error') return '<span class="badge badge-warning">ERROR</span>';
    return '<span class="badge badge-allowed">ALLOWED</span>';
  }
  function teleMatch(r) {
    if (tele.filter === 'blocked' && r.status !== 'blocked') return false;
    if (tele.filter === 'allowed' && r.status === 'blocked') return false;
    if (tele.q) { const s = tele.q; if (!((r.domain || '') + ' ' + (r.client_ip || '') + ' ' + (r.reason || '') + ' ' + (r.qtype || '')).toLowerCase().includes(s)) return false; }
    return true;
  }
  function renderTele() {
    const tb = $('#telescope-table-body'); if (!tb) return;
    const rows = tele.rows.filter(teleMatch).slice(0, 80);
    if (!rows.length) { tb.innerHTML = `<tr><td colspan="6" style="text-align:center;color:var(--muted)">${tele.rows.length ? 'No queries match the filter.' : 'Waiting for live queries…'}</td></tr>`; }
    else tb.innerHTML = rows.map(r => `<tr class="clickable ${r._new ? 'tele-row-new' : ''}" data-id="${r._id}">
      <td style="font-size:11.5px;color:var(--muted)">${esc(r._time)}</td><td class="mono"><strong>${esc(r.domain || '-')}</strong></td>
      <td class="mono">${esc(r.qtype || 'A')}</td><td>${teleBadge(r)}</td>
      <td style="font-size:12px;color:var(--muted)">${esc(r.reason || '-')}</td><td class="mono" style="font-size:11.5px">${esc(r.client_ip || '127.0.0.1')}</td></tr>
      ${tele.open === r._id ? `<tr class="row-detail"><td colspan="6">${esc(JSON.stringify(r, (k, v) => k.startsWith('_') ? undefined : v, 2))}</td></tr>` : ''}`).join('');
    rows.forEach(r => r._new = false);
    const s = $('#tele-stats');
    if (s) s.innerHTML = `<span>Seen <b>${tele.total.toLocaleString()}</b></span><span>Blocked <b>${tele.blocked.toLocaleString()}</b></span><span>Block rate <b>${tele.total ? (tele.blocked / tele.total * 100).toFixed(1) : '0.0'}%</b></span>${tele.paused ? '<span style="color:var(--amber)"><b>PAUSED</b></span>' : ''}`;
  }
  let teleId = 0, renderQueued = false;
  function queueTele() { if (renderQueued) return; renderQueued = true; requestAnimationFrame(() => { renderQueued = false; renderTele(); }); }

  window.startTelescope = function () {
    if (tele.src) tele.src.close();
    tele.src = new EventSource(`/api/admin/stream?anonymize=${!!window.anonymizeIps}`);
    tele.src.onmessage = (event) => {
      if (tele.paused) return;
      let ev; try { ev = JSON.parse(event.data); } catch (e) { return; }
      ev._id = ++teleId; ev._time = new Date().toLocaleTimeString(); ev._new = true;
      tele.rows.unshift(ev); if (tele.rows.length > TELE_MAX) tele.rows.length = TELE_MAX;
      tele.total++; if (ev.status === 'blocked') tele.blocked++;
      queueTele();
    };
    tele.src.onerror = () => setConn(false);
  };
  window.toggleStreamPause = function () {
    tele.paused = !tele.paused;
    const b = $('#pause-stream-btn'); if (b) b.textContent = tele.paused ? 'Resume Stream' : 'Pause Stream';
    renderTele();
  };
  window.clearTelescope = function () { tele.rows = []; tele.total = 0; tele.blocked = 0; tele.open = null; renderTele(); };
  window.toggleMaskIp = function () { window.anonymizeIps = $('#mask-ip-toggle').checked; window.startTelescope(); };

  function buildTeleTools() {
    const pane = $('#pane-telescope'); if (!pane || $('#tele-search')) return;
    const holder = document.createElement('div');
    holder.innerHTML = `<div class="toolbar" style="margin-bottom:12px">
        <div class="search-box"><input id="tele-search" class="input-box" placeholder="Filter domain, IP, reason…  ( / )"></div>
        <div class="verdict-filters" id="tele-filters"><button data-f="all" class="active">All</button><button data-f="blocked">Blocked</button><button data-f="allowed">Allowed</button></div>
        <button class="btn btn-subtle btn-sm" id="tele-export">⬇ Export CSV</button></div><div class="tele-stats" id="tele-stats"></div>`;
    const tableWrap = $('.table-container', pane);
    pane.insertBefore(holder, tableWrap);
    $('#tele-search').addEventListener('input', e => { tele.q = e.target.value.toLowerCase(); renderTele(); });
    $('#tele-filters').addEventListener('click', e => {
      const b = e.target.closest('button'); if (!b) return;
      tele.filter = b.dataset.f; $$('#tele-filters button').forEach(x => x.classList.toggle('active', x === b)); renderTele();
    });
    $('#tele-export').onclick = () => {
      const lines = ['time,domain,type,status,reason,client_ip'].concat(tele.rows.filter(teleMatch).map(r =>
        [r._time, r.domain, r.qtype || 'A', r.status, r.reason, r.client_ip].map(v => '"' + String(v == null ? '' : v).replace(/"/g, '""') + '"').join(',')));
      const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob([lines.join('\n')], { type: 'text/csv' }));
      a.download = 'focusdns_queries.csv'; a.click(); setTimeout(() => URL.revokeObjectURL(a.href), 1000);
    };
    $('#telescope-table-body').addEventListener('click', e => {
      const tr = e.target.closest('tr.clickable'); if (!tr) return;
      const id = +tr.dataset.id; tele.open = tele.open === id ? null : id; renderTele();
    });
    renderTele();
  }

  /* ============================ Mission Control charts ============================ */
  function buildChartPanel() {
    const pane = $('#pane-mission-control'); if (!pane || $('#traffic-canvas')) return;
    const wrap = document.createElement('div'); wrap.className = 'chart-grid';
    wrap.innerHTML = `<div class="card chart-card"><div class="chart-head"><span class="chart-title">Query throughput</span>
        <div class="range-pills" id="range-pills"><button data-r="300">5m</button><button data-r="900">15m</button><button data-r="3600">1h</button></div></div>
        <div class="chart-wrap"><canvas id="traffic-canvas"></canvas><div class="chart-tip" id="traffic-tip"></div></div>
        <div class="legend"><span><i style="background:var(--ink)"></i>Total q/s</span><span><i style="background:var(--vermilion)"></i>Blocked q/s</span></div></div>
      <div class="card chart-card"><div class="chart-head"><span class="chart-title">Today's traffic mix</span></div>
        <div class="donut-box"><canvas id="donut-canvas"></canvas><div class="donut-legend" id="donut-legend"></div></div></div>`;
    const snap = pane.querySelector('.card[style*="margin-top"]');
    pane.insertBefore(wrap, snap || null);
    $$('#range-pills button').forEach(b => {
      b.classList.toggle('active', +b.dataset.r === range);
      b.onclick = () => { range = +b.dataset.r; store.set('range', range); $$('#range-pills button').forEach(x => x.classList.toggle('active', x === b)); drawTraffic(); };
    });
    bindTrafficHover();
  }

  /* ============================ Nav: indicator, drawer, hotkeys ============================ */
  const TABS = ['mission-control', 'feeds', 'upstream', 'emergency', 'fleet', 'telescope', 'maintenance'];
  let currentTab = 'mission-control';
  function moveIndicator() {
    const nav = $('.nav-tabs'); if (!nav) return;
    let ind = $('.nav-indicator', nav); if (!ind) { ind = document.createElement('div'); ind.className = 'nav-indicator'; nav.appendChild(ind); }
    const a = $('.tab-btn.active', nav); if (!a) return;
    ind.style.left = a.offsetLeft + 'px'; ind.style.width = a.offsetWidth + 'px';
  }
  function wrapSwitchTab() {
    const orig = window.switchTab;
    window.switchTab = function (name) {
      currentTab = name;
      orig(name);
      document.body.classList.remove('drawer-open');
      store.set('tab', name);
      moveIndicator();
      if (name === 'mission-control') setTimeout(() => { drawTraffic(); drawDonut(); }, 30);
      if (name === 'emergency') refreshCategories();
    };
    // exact tab matching (original uses substring on label which mis-selects)
    window.switchTab = (function (inner) {
      return function (name) {
        inner(name);
        const btns = $$('.tab-btn');
        btns.forEach(b => b.classList.remove('active'));
        const i = TABS.indexOf(name); if (btns[i]) btns[i].classList.add('active');
        moveIndicator();
      };
    })(window.switchTab);
  }

  function decorateTabs() {
    $$('.tab-btn').forEach((b, i) => {
      if (!b.querySelector('.kbd')) { const k = document.createElement('span'); k.className = 'kbd'; k.textContent = i + 1; b.appendChild(k); }
    });
  }

  function decorateHeader() {
    const brand = $('.brand-section'); if (brand && !$('.hamburger')) {
      const h = document.createElement('button'); h.className = 'icon-btn hamburger'; h.textContent = '☰'; h.setAttribute('aria-label', 'Menu');
      h.onclick = () => document.body.classList.toggle('drawer-open'); brand.prepend(h);
      const bd = document.createElement('div'); bd.id = 'drawer-backdrop'; bd.onclick = () => document.body.classList.remove('drawer-open'); document.body.appendChild(bd);
    }
    const hc = $('.header-center'); if (hc && !$('#conn-pill')) { const p = document.createElement('span'); p.id = 'conn-pill'; p.className = 'conn-pill'; p.textContent = '● …'; hc.appendChild(p); }
    const act = $('.header-actions'); if (act && !$('#theme-btn')) {
      const k = document.createElement('button'); k.className = 'icon-btn'; k.id = 'cmdk-btn'; k.textContent = '⌘'; k.title = 'Command palette (Ctrl+K)'; k.onclick = openPalette;
      const t = document.createElement('button'); t.className = 'icon-btn'; t.id = 'theme-btn'; t.title = 'Toggle theme (T)'; t.onclick = toggleTheme;
      act.prepend(t); act.prepend(k);
      t.textContent = store.get('theme', 'dark') === 'light' ? '☾' : '☀';
    }
  }

  /* ---------------- Command palette ---------------- */
  const COMMANDS = [
    ...[['Mission Control', 'mission-control'], ['Threat Feeds', 'feeds'], ['Upstream Engine', 'upstream'], ['Emergency & Overrides', 'emergency'], ['Fleet & Profiles', 'fleet'], ['Live Telescope', 'telescope'], ['Maintenance', 'maintenance']]
      .map(([n, id], i) => ({ name: 'Go to ' + n, hint: String(i + 1), run: () => window.switchTab(id) })),
    { name: 'Toggle light / dark theme', hint: 'T', run: toggleTheme },
    { name: 'Toggle emergency bypass', hint: '', run: () => window.toggleBypassQuick() },
    { name: 'Sync threat feeds now', hint: '', run: () => { window.switchTab('feeds'); window.syncFeedsNow(); } },
    { name: 'Run upstream latency benchmark', hint: '', run: () => { window.switchTab('upstream'); window.runBenchmark(); } },
    { name: 'Enroll device (QR)', hint: '', run: openQr },
    { name: 'Provision new profile', hint: '', run: () => { window.switchTab('fleet'); window.openNewProfileModal(); } },
    { name: 'Download database backup', hint: '', run: () => { location.href = '/api/admin/backup'; } },
    { name: 'Pause / resume telescope', hint: 'Space', run: () => window.toggleStreamPause() },
    { name: 'Show keyboard shortcuts', hint: '?', run: openHelp },
    { name: 'Sign out', hint: '', run: () => window.handleLogout() },
  ];
  let palSel = 0, palItems = COMMANDS;
  function buildPalette() {
    if ($('#cmdk')) return;
    const m = document.createElement('div'); m.id = 'cmdk'; m.className = 'modal-backdrop';
    m.innerHTML = '<div class="cmdk-box"><input id="cmdk-input" placeholder="Type a command…" autocomplete="off"><div class="cmdk-list" id="cmdk-list"></div></div>';
    document.body.appendChild(m);
    m.addEventListener('click', e => { if (e.target === m) closePalette(); });
    $('#cmdk-input').addEventListener('input', e => { filterPalette(e.target.value); });
    $('#cmdk-input').addEventListener('keydown', e => {
      if (e.key === 'ArrowDown') { palSel = Math.min(palItems.length - 1, palSel + 1); paintPalette(); e.preventDefault(); }
      else if (e.key === 'ArrowUp') { palSel = Math.max(0, palSel - 1); paintPalette(); e.preventDefault(); }
      else if (e.key === 'Enter') { const c = palItems[palSel]; if (c) { closePalette(); c.run(); } }
    });
    $('#cmdk-list').addEventListener('click', e => { const el = e.target.closest('.cmdk-item'); if (el) { const c = palItems[+el.dataset.i]; closePalette(); c.run(); } });
  }
  function filterPalette(q) {
    q = q.toLowerCase().trim();
    palItems = !q ? COMMANDS : COMMANDS.filter(c => { let i = 0; const n = c.name.toLowerCase(); for (const ch of q) { i = n.indexOf(ch, i); if (i < 0) return false; i++; } return true; });
    palSel = 0; paintPalette();
  }
  function paintPalette() {
    const l = $('#cmdk-list');
    l.innerHTML = palItems.length ? palItems.map((c, i) => `<div class="cmdk-item ${i === palSel ? 'sel' : ''}" data-i="${i}"><span>${esc(c.name)}</span>${c.hint ? `<span class="kbd">${esc(c.hint)}</span>` : ''}</div>`).join('') : '<div class="cmdk-empty">No matching commands</div>';
    const s = $('.cmdk-item.sel', l); if (s) s.scrollIntoView({ block: 'nearest' });
  }
  function openPalette() { buildPalette(); $('#cmdk').style.display = 'flex'; $('#cmdk-input').value = ''; filterPalette(''); $('#cmdk-input').focus(); }
  function closePalette() { const m = $('#cmdk'); if (m) m.style.display = 'none'; }

  function openHelp() {
    let m = $('#help-modal');
    if (!m) {
      m = document.createElement('div'); m.id = 'help-modal'; m.className = 'modal-backdrop';
      m.innerHTML = `<div class="modal-box"><h3 class="modal-title">Keyboard shortcuts</h3><div class="help-grid">
        <span class="kbd">1</span><span>… <span class="kbd">7</span> Switch tab</span>
        <span class="kbd">/</span><span>Focus search on current tab</span>
        <span class="kbd">Space</span><span>Pause / resume Live Telescope</span>
        <span class="kbd">T</span><span>Toggle Obsidian / Warm Stone theme</span>
        <span class="kbd">Ctrl K</span><span>Command palette</span>
        <span class="kbd">?</span><span>This help</span>
        <span class="kbd">Esc</span><span>Close dialogs</span></div>
        <div class="modal-actions"><button class="btn btn-primary" onclick="this.closest('.modal-backdrop').style.display='none'">Close</button></div></div>`;
      document.body.appendChild(m); m.addEventListener('click', e => { if (e.target === m) m.style.display = 'none'; });
    }
    m.style.display = 'flex';
  }

  function inField(e) { const t = e.target; return t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' || t.isContentEditable); }
  document.addEventListener('keydown', e => {
    if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'k') { e.preventDefault(); if (dashboardVisible()) openPalette(); return; }
    if (e.key === 'Escape') {
      closePalette(); closeQr(); document.body.classList.remove('drawer-open');
      $$('.modal-backdrop').forEach(m => m.style.display = 'none'); return;
    }
    if (inField(e) || e.ctrlKey || e.metaKey || e.altKey || !dashboardVisible()) return;
    if (e.key >= '1' && e.key <= '7') { window.switchTab(TABS[+e.key - 1]); }
    else if (e.key === '/') { e.preventDefault(); const f = { fleet: '#fleet-search', telescope: '#tele-search' }[currentTab]; if (f) $(f).focus(); else openPalette(); }
    else if (e.key === ' ' && currentTab === 'telescope') { e.preventDefault(); window.toggleStreamPause(); }
    else if (e.key.toLowerCase() === 't') toggleTheme();
    else if (e.key === '?') openHelp();
  });
  function dashboardVisible() { const d = $('#dashboard-screen'); return d && getComputedStyle(d).display !== 'none'; }

  /* ============================ Boot ============================ */
  function boot() {
    decorateHeader(); decorateTabs(); buildChartPanel(); buildFleetTools(); buildTeleTools(); buildCategories();
    wrapSwitchTab();
    applyTheme(store.get('theme', document.documentElement.getAttribute('data-theme') || 'dark'));
    window.addEventListener('resize', () => { moveIndicator(); Charts.redraw(); });
    setTimeout(moveIndicator, 60);
    if (document.fonts && document.fonts.ready) document.fonts.ready.then(moveIndicator);
    const saved = store.get('tab', null);
    if (saved && TABS.includes(saved) && !location.search.includes('tab=')) window.switchTab(saved);
    sample(); setInterval(sample, SAMPLE_MS);
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot); else boot();
})();
