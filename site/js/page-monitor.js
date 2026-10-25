/* Page 3 - Monitoring: HISTORICAL replay of the evaluation week, plus an alert explorer.
   At simulated time t, only alerts with timestamp <= t are shown. Not a live feed. */
"use strict";
(function () {
  const RP = window.RP;
  const mo = { i: 0, timer: null, speed: 1000, onlyProd: false, tab: "replay", pick: null, f: { type: [], sev: "", prod: "", from: null, to: null } };
  const stop = () => { if (mo.timer) clearInterval(mo.timer); mo.timer = null; };

  RP.pages.monitor = {
    render(host, S) {
      stop();
      const rp = RP.rows(S.raw.replay).map((r) => ({ ...r, t: RP.day(r.dt) * 24 + r.hour }));
      this.rp = rp; this.byPD = new Map();
      for (const r of rp) { const k = r.product_id + "|" + r.dt; if (!this.byPD.has(k)) this.byPD.set(k, []); this.byPD.get(k).push(r); }
      for (const v of this.byPD.values()) v.sort((a, b) => a.hour - b.hour);
      this.times = [...new Set(rp.map((r) => r.t))].sort((a, b) => a - b);
      this.alerts = RP.rows(S.raw.alerts).map((a) => ({ ...a, t: RP.day(a.dt) * 24 + a.hour }));
      const six = this.times.findIndex((t) => t % 24 === 6);
      this.start = six >= 0 ? six : 0; mo.i = this.start;
      const days = [...new Set(this.times.map((t) => Math.floor(t / 24)))];
      const opts = RP.productOptions(S);
      host.innerHTML = `<div class="tabs" role="tablist"><button role="tab" data-tab="replay" class="active">Historical hourly replay</button><button role="tab" data-tab="explorer">Alert explorer</button></div>
      <div data-pane="replay">
        <div class="rp-banner replay">${RP.icon("clock")}<div><strong>Historical replay — not a live feed.</strong> Hour-by-hour records from the evaluation week are revealed in timestamp order. Expected values come from forecasts made before that week; alerts use only data up to the simulated time. RetailPulse is not connected to a till or stock system.</div></div>
        <div class="grid g-3-9"><div class="side" style="position:static;max-height:none">
          <div class="clock" id="mo-clock"></div>
          <div class="btn-row"><button class="btn btn-primary" id="mo-play">${RP.icon("play")} Play</button><button class="btn btn-outline" id="mo-pause">${RP.icon("pause")} Pause</button><button class="btn btn-outline" id="mo-reset">${RP.icon("reset")} Reset</button></div>
          <div class="field"><label for="mo-speed">Speed</label><select id="mo-speed" class="inp"><option value="2000">1 hour / 2 s</option><option value="1000" selected>1 hour / s</option><option value="500">2 hours / s</option><option value="250">4 hours / s</option></select></div>
          <div class="field"><label for="mo-step">Timeline (hour of the replay week)</label><input type="range" class="range" id="mo-step" min="0" max="${this.times.length - 1}" step="1" value="${mo.i}"><span class="sub" id="mo-steplab"></span></div>
          <div class="field"><label for="mo-day">Jump to day (06:00)</label><select id="mo-day" class="inp"><option value="">Choose a day…</option>${days.map((d) => `<option value="${d}">${RP.fmtDay(d, "a d b")}</option>`).join("")}</select></div>
          <div class="field"><label for="mo-product">Product to watch</label><select id="mo-product" class="inp"></select></div>
          <label class="check"><input type="checkbox" id="mo-only"> Show alerts for this product only</label>
          <div class="facts" id="mo-now"></div></div>
          <div>${RP.card('<span id="mo-title"></span>', '<span id="mo-sub"></span>', null, `<div id="mo-plot" class="plot" style="height:340px"></div><div id="mo-note"></div>`)}<div style="height:1rem"></div>
            ${RP.card('Alerts raised so far', '<span id="mo-sofar-sub"></span>', null, `<div class="legend"><span class="l-crit">Critical: out of stock in a peak hour</span><span class="l-warn">Warning: outside the expected range for 3+ hours</span><span class="l-info">Info: out of stock outside peak hours</span></div><div id="mo-sofar"></div>` + RP.note("Click an alert to open that product on that day."))}</div></div>
      </div>
      <div data-pane="explorer" hidden>
        <div class="filters-row">
          <div class="field"><label for="mo-ftype">Alert type</label><select id="mo-ftype" class="inp"></select></div>
          <div class="field"><label for="mo-fsev">Severity / risk category</label><select id="mo-fsev" class="inp"><option value="">All</option><option>Critical</option><option>Warning</option><option>Info</option><option>Anomaly</option></select></div>
          <div class="field"><label for="mo-fprod">Product</label><select id="mo-fprod" class="inp"></select></div>
          <div class="field"><label>Period</label><div class="daterange"><input type="date" id="mo-ffrom" class="inp" aria-label="From"><span>to</span><input type="date" id="mo-fto" class="inp" aria-label="To"></div></div></div>
        <div class="grid g-8-4">${RP.card("Alerts and anomalies", '<span id="mo-ex-sub"></span>', null, `<div id="mo-ex"></div><div id="mo-ex-note"></div>`)}${RP.card("Alert detail", null, null, `<div id="mo-detail" class="detail"><p class="sub">Click an alert to see why it was raised.</p></div>`)}</div>
      </div>`;
      RP.options(RP.$("#mo-product", host), opts, RP.st.product);
      RP.options(RP.$("#mo-fprod", host), [["", "All products"], ...opts], "");
      RP.$$(".tabs button", host).forEach((b) => b.addEventListener("click", () => {
        mo.tab = b.dataset.tab; RP.$$(".tabs button", host).forEach((x) => x.classList.toggle("active", x === b));
        RP.$$("[data-pane]", host).forEach((p) => (p.hidden = p.dataset.pane !== mo.tab));
        if (mo.tab === "explorer") this.explorer(host, S); window.dispatchEvent(new Event("resize"));
      }));
      RP.$("#mo-play", host).addEventListener("click", () => this.play(host, S));
      RP.$("#mo-pause", host).addEventListener("click", () => { stop(); this.clock(host, S); });
      RP.$("#mo-reset", host).addEventListener("click", () => { stop(); mo.i = this.start; this.tick(host, S); });
      RP.$("#mo-speed", host).addEventListener("change", (e) => { mo.speed = Number(e.target.value); if (mo.timer) { stop(); this.play(host, S); } });
      RP.$("#mo-step", host).addEventListener("input", (e) => { stop(); mo.i = Number(e.target.value); this.tick(host, S); });
      RP.$("#mo-day", host).addEventListener("change", (e) => { if (!e.target.value) return; const i = this.times.indexOf(Number(e.target.value) * 24 + 6); if (i >= 0) { stop(); mo.i = i; this.tick(host, S); } });
      RP.$("#mo-product", host).addEventListener("change", (e) => { RP.st.product = Number(e.target.value); RP.invalidate("monitor"); this.tick(host, S); });
      RP.$("#mo-only", host).addEventListener("change", (e) => { mo.onlyProd = e.target.checked; this.sofar(host, S); });
      for (const id of ["mo-ftype", "mo-fsev", "mo-fprod", "mo-ffrom", "mo-fto"]) RP.$("#" + id, host).addEventListener("change", () => this.explorer(host, S));
      this.tick(host, S);
    },
    onShow(host, S) { RP.$("#mo-product", host).value = RP.st.product; this.tick(host, S); if (mo.tab === "explorer") this.explorer(host, S); },
    now() { return this.times[Math.min(mo.i, this.times.length - 1)]; },
    play(host, S) {
      stop();
      mo.timer = setInterval(() => {
        if (!RP.$("#mo-clock")) return stop();
        if (mo.i >= this.times.length - 1) { stop(); this.clock(host, S); return; }
        mo.i++; this.tick(host, S);
      }, mo.speed);
      this.clock(host, S);
    },
    fmtT(t) { return RP.fmtDay(Math.floor(t / 24), "a d b Y") + ", " + RP.pad2(t % 24) + ":00"; },
    clock(host, S) {
      const t = this.now(), playing = !!mo.timer;
      const sp = { 2000: "1 h / 2 s", 1000: "1 h / s", 500: "2 h / s", 250: "4 h / s" }[mo.speed];
      const c = RP.$("#mo-clock", host);
      c.className = "clock" + (playing ? " playing" : "");
      c.innerHTML = `<span class="k">Simulated time</span><strong>${this.fmtT(t)}</strong><span class="live">HISTORICAL REPLAY</span><span class="st">${playing ? `replaying at ${sp}…` : "paused"}</span>`;
      RP.$("#mo-step", host).value = mo.i;
      RP.$("#mo-steplab", host).textContent = `Hour ${mo.i + 1} of ${this.times.length} · ${RP.fmtDay(Math.floor(t / 24), "a d b")}, ${RP.pad2(t % 24)}:00`;
    },
    tick(host, S) {
      this.clock(host, S);
      const t = this.now(), day = Math.floor(t / 24), hr = t % 24, pid = RP.st.product;
      const g = this.byPD.get(pid + "|" + RP.iso(day)) || [];
      RP.$("#mo-title", host).textContent = `Is ${RP.plabel(pid)} on track today?`;
      RP.$("#mo-sub", host).textContent = `${RP.fmtDay(day, "A d b")} · observed cumulative sales vs expected range`;
      RP.chReplay(RP.$("#mo-plot", host), g, hr);
      const seen = g.filter((r) => r.hour <= hr), last = seen[seen.length - 1];
      if (last) {
        const status = last.hour < 6 ? "before trading hours" : last.out === 1 && last.hour <= 21 ? "out of stock" : last.cum_obs < last.cum_lo - 1e-6 ? "below the expected range" : last.cum_obs > last.cum_hi + 1e-6 ? "above the expected range" : "within the expected range";
        RP.$("#mo-note", host).innerHTML = RP.note(`At ${RP.pad2(last.hour)}:00 cumulative sales are ${RP.fmtNum(last.cum_obs, 2)} vs ${RP.fmtNum(last.cum_exp, 2)} expected, so the product is ${status}. Red shading marks out-of-stock hours.`);
      } else RP.$("#mo-note", host).innerHTML = "";
      const cur = this.rp.filter((r) => r.t === t && r.out === 1 && r.hour >= 6 && r.hour <= 21);
      const a = this.alerts.filter((x) => x.t <= t);
      RP.$("#mo-now", host).innerHTML = [["Products out of stock now", cur.length], ["Critical alerts so far", a.filter((x) => x.severity === "Critical").length], ["Warnings so far", a.filter((x) => x.severity === "Warning").length]]
        .map(([l, v]) => `<div><span>${l}</span><strong>${v}</strong></div>`).join("");
      this.sofar(host, S);
    },
    sofar(host, S) {
      const t = this.now(); let a = this.alerts.filter((x) => x.t <= t);
      if (mo.onlyProd) a = a.filter((x) => x.product_id === RP.st.product);
      a = a.slice().sort((p, q) => q.t - p.t);
      RP.$("#mo-sofar-sub", host).textContent = `${mo.onlyProd ? RP.plabel(RP.st.product) : "all products"} · ${a.length} alerts · newest first`;
      RP.table(RP.$("#mo-sofar", host), a, [
        { key: "t", label: "Time", width: 90, render: (x) => `${RP.fmtDay(Math.floor(x.t / 24), "a")} ${RP.pad2(x.hour)}:00` },
        { key: "product_id", label: "Product", width: 86, cls: "pid", render: (x) => RP.plabel(x.product_id) },
        { key: "severity", label: "Severity", width: 92, render: (x) => RP.badge(x.severity, RP.sevKind(x.severity)) },
        { key: "type", label: "Type" }, { key: "message", label: "Detail", sortable: false },
      ], { pageSize: 6, empty: "No alerts yet at this simulated time.", onClick: (x) => RP.goto("product", { product: x.product_id, date: x.dt }) });
    },
    allAlerts(S) {
      const r1 = this.alerts.map((a) => ({ when: `${a.dt} ${RP.pad2(a.hour)}:00`, d: RP.day(a.dt), dt: a.dt, product_id: a.product_id, source: "Hourly replay", type: a.type, severity: a.severity,
        observed: a.observed, expected: a.expected, deviation: a.observed - a.expected, explanation: a.message,
        method: a.type === "Out of stock" ? "Stock status turned to unavailable during trading hours" : "Cumulative sales outside forecast-based 80% range for 3 consecutive hours" }));
      const r2 = RP.classifyAnomalies(S, RP.st.zthr).map((a) => ({ when: a.dt, d: a.d, dt: a.dt, product_id: a.product_id, source: "Daily anomaly",
        type: (a.direction === "surge" ? "Surge" : "Drop") + ": " + a.cause, severity: "Anomaly", observed: a.observed, expected: a.expected, deviation: a.deviation,
        explanation: a.explanation + " Statistical unusualness only; not a confirmed operational problem.", method: a.method }));
      return r1.concat(r2);
    },
    explorer(host, S) {
      const all = this.allAlerts(S);
      const ft = RP.$("#mo-ftype", host);
      if (!ft.options.length) RP.options(ft, [["", "All types"], ...[...new Set(all.map((a) => a.type))].sort().map((t) => [t, t])], "");
      const ff = RP.$("#mo-ffrom", host), fto = RP.$("#mo-fto", host);
      if (!ff.value) { const ds = all.map((a) => a.d); ff.value = RP.iso(Math.min(...ds)); fto.value = RP.iso(Math.max(...ds)); }
      const ty = ft.value, sev = RP.$("#mo-fsev", host).value, pr = RP.$("#mo-fprod", host).value, a0 = RP.day(ff.value), a1 = RP.day(fto.value);
      const rows = all.filter((a) => (!ty || a.type === ty) && (!sev || a.severity === sev) && (!pr || a.product_id === Number(pr)) && a.d >= a0 && a.d <= a1)
        .sort((p, q) => (p.when < q.when ? 1 : -1));
      RP.$("#mo-ex-sub", host).textContent = `${rows.length} shown · newest first`;
      RP.table(RP.$("#mo-ex", host), rows, [
        { key: "when", label: "When", width: 130 }, { key: "product_id", label: "Product", width: 86, cls: "pid", render: (x) => RP.plabel(x.product_id) },
        { key: "source", label: "Source" }, { key: "type", label: "Type" },
        { key: "severity", label: "Severity", width: 92, render: (x) => RP.badge(x.severity, RP.sevKind(x.severity)) },
        { key: "observed", label: "Observed", num: true, render: (x) => RP.fmtNum(x.observed, 2) }, { key: "expected", label: "Expected", num: true, render: (x) => RP.fmtNum(x.expected, 2) },
        { key: "deviation", label: "Deviation", num: true, render: (x) => RP.fmtNum(x.deviation, 2) },
      ], { search: true, placeholder: "Search alerts…", pageSize: 12, empty: "No alerts match these filters. Clear a filter to see more.", onClick: (x) => this.detail(host, x) });
      RP.$("#mo-ex-note", host).innerHTML = RP.note(`Daily anomalies use the current threshold |z| ≥ ${RP.st.zthr.toFixed(1)} (adjustable under Forecast &amp; Scenarios). Anomalies are statistical signals, not confirmed problems.`);
    },
    detail(host, r) {
      RP.$("#mo-detail", host).innerHTML = `<h4>${RP.plabel(r.product_id)} · ${r.when}</h4>${RP.badge(r.severity, RP.sevKind(r.severity))}<p><strong>${RP.esc(r.type)}</strong></p><p>${RP.esc(r.explanation)}</p>
        <dl><dt>Observed</dt><dd>${RP.fmtNum(r.observed, 3)}</dd><dt>Expected / reference</dt><dd>${RP.fmtNum(r.expected, 3)}</dd><dt>Deviation</dt><dd>${RP.fmtNum(r.deviation, 3)}</dd><dt>Detection method</dt><dd>${RP.esc(r.method)}</dd></dl>
        <button class="btn btn-primary" id="mo-open">Open this product</button>`;
      RP.$("#mo-open", host).addEventListener("click", () => RP.goto("product", { product: r.product_id, date: r.dt }));
    },
  };
})();
