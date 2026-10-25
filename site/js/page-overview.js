/* Page 1 - Overview. Period and category filters drive KPIs, trend, top products,
   category chart, heatmap and insights. Alerts and actions are "as of the latest day". */
"use strict";
(function () {
  const RP = window.RP;
  const ACTION_ICONS = { "Consider replenishing earlier": "truck", "Review possible demand surge": "up", "Investigate unexplained sales drop": "search",
    "Plan for lower demand": "down", "Use caution: forecast unreliable": "help", "Maintain current approach": "check" };
  const ov = { period: "28", from: null, to: null, cat: "", action: "", heatMode: "z", heatRows: "top40" };

  RP.pages.overview = {
    render(host, S) {
      const m = S.m;
      ov.to = S.lastDay; ov.from = Math.max(S.firstDay, S.lastDay - 27); ov.period = "28"; ov.cat = ""; ov.action = "";
      host.innerHTML = `
      <div class="hero"><div>
          <div class="eyebrow">Store ${m.store_id} · ${m.products} products · ${m.mode === "synthetic" ? "synthetic demo data" : "FreshRetailNet-50K"}</div>
          <h1>Store overview</h1>
          <p>Data runs from ${RP.fmtDay(S.firstDay, "d b Y")} to ${RP.fmtDay(S.lastDay, "d b Y")}. What needs attention first, and why.</p></div>
        <div class="filters">
          <div class="field"><label for="ov-period">Period</label><select id="ov-period" class="inp">
            <option value="7">Last 7 days</option><option value="14">Last 14 days</option><option value="28" selected>Last 28 days</option>
            <option value="56">Last 56 days</option><option value="all">Whole period</option><option value="custom">Custom</option></select></div>
          <div class="field"><label>Dates</label><div class="daterange">
            <input type="date" id="ov-from" class="inp" aria-label="From"><span>to</span><input type="date" id="ov-to" class="inp" aria-label="To"></div></div>
          <div class="field"><label for="ov-cat">Category</label><select id="ov-cat" class="inp"></select></div>
        </div></div>
      <div class="kpis" id="ov-kpis"></div>
      <div class="grid g-8-4">
        ${RP.card("Sales and estimated demand", "Daily totals · red bars = out-of-stock hours · grey band = evaluation week", "line", `<div id="ov-store" class="plot" style="height:330px"></div><div id="ov-store-note"></div>`)}
        ${RP.card("Priority stock alerts", "as of the latest day · click to investigate", "bell", `<div id="ov-alerts"></div><div class="btn-row"><a class="btn btn-outline" href="#monitor">${RP.icon("arrow")} Open alert explorer</a></div>`)}
      </div>
      <div class="grid g-8-4">
        ${RP.card("Recommended actions", "Rule-based · pick an action type to filter · click a row to open the product", "list",
          `<div class="actions" id="ov-tiles"></div><div id="ov-queue"></div>` + RP.note("Ranked by urgency × (estimated unmet demand + stockout risk + recent unusual activity). No order quantities are given: the dataset has no inventory, lead-time or cost fields. Rules are listed under Data &amp; Methods; weights can be changed under Forecast &amp; Scenarios."))}
        ${RP.card("Quick insights", "for the selected period", "bulb", `<div class="insights" id="ov-insights"></div>`)}
      </div>
      <div class="grid g-6-6">
        ${RP.card("Top products by estimated demand", "Recorded sales + estimated unmet demand · click a bar", "rank", `<div id="ov-top" class="plot" style="height:360px"></div>`)}
        ${RP.card("Category performance", "Click a category to filter the page", "layers", `<div id="ov-cats" class="plot" style="height:360px"></div>`)}
      </div>
      ${RP.card("Demand heatmap", "Product × day for the selected period · click a cell to open that product and date", "grid",
        `<div class="heat-ctrl"><select id="ov-heatmode" class="inp" aria-label="Heatmap view"><option value="z">Deviation from normal (robust z)</option>
          <option value="demand">Estimated demand vs usual level</option><option value="stockout">Out-of-stock hours</option></select>
          <select id="ov-heatrows" class="inp" aria-label="Products shown"><option value="top40">40 most unusual products</option><option value="top20">20 most unusual products</option><option value="all">All products</option></select></div>
         <div id="ov-heat" class="plot"></div><div id="ov-heat-note"></div>`)}`;
      RP.options(RP.$("#ov-cat", host), [["", "All categories"], ...S.categories.map((c) => [c, "Category " + c])], "");
      const from = RP.$("#ov-from", host), to = RP.$("#ov-to", host);
      for (const el of [from, to]) { el.min = RP.iso(S.firstDay); el.max = RP.iso(S.lastDay); }
      const setDates = () => { from.value = RP.iso(ov.from); to.value = RP.iso(ov.to); };
      setDates();
      RP.$("#ov-period", host).addEventListener("change", (e) => {
        ov.period = e.target.value;
        if (ov.period === "custom") return;
        ov.to = S.lastDay; ov.from = ov.period === "all" ? S.firstDay : Math.max(S.firstDay, S.lastDay - Number(ov.period) + 1);
        setDates(); this.update(host, S);
      });
      const onDates = () => {
        if (!from.value || !to.value) return;
        let a = RP.day(from.value), b = RP.day(to.value); if (a > b) [a, b] = [b, a];
        ov.from = Math.max(S.firstDay, a); ov.to = Math.min(S.lastDay, b);
        const n = ov.to - ov.from + 1;
        ov.period = ov.to === S.lastDay && ov.from === S.firstDay ? "all" : ov.to === S.lastDay && [7, 14, 28, 56].includes(n) ? String(n) : "custom";
        RP.$("#ov-period", host).value = ov.period; this.update(host, S);
      };
      from.addEventListener("change", onDates); to.addEventListener("change", onDates);
      RP.$("#ov-cat", host).addEventListener("change", (e) => { ov.cat = e.target.value; this.update(host, S); });
      RP.$("#ov-heatmode", host).addEventListener("change", (e) => { ov.heatMode = e.target.value; this.heat(host, S); });
      RP.$("#ov-heatrows", host).addEventListener("change", (e) => { ov.heatRows = e.target.value; this.heat(host, S); });
      RP.$("#ov-tiles", host).addEventListener("click", (e) => { const b = e.target.closest(".action"); if (b) { ov.action = b.dataset.a; this.actions(host, S); } });
      RP.$("#ov-alerts", host).addEventListener("click", (e) => { const b = e.target.closest(".alert"); if (b) RP.goto("product", { product: b.dataset.pid, date: null }); });
      this.update(host, S);
    },
    onShow(host, S) { this.kpis(host, S); this.actions(host, S); this.alerts(host, S); this.heat(host, S); },

    ids(S) { return ov.cat ? new Set(S.products.filter((p) => String(p.first_category_id) === ov.cat).map((p) => p.product_id)) : null; },
    per(S, a, b) { const ids = this.ids(S); return S.daily.filter((r) => r.d >= a && r.d <= b && (!ids || ids.has(r.product_id))); },
    recsCat(S) { const ids = this.ids(S); return RP.recs(S, RP.st.zthr).filter((r) => !ids || ids.has(r.product_id)); },
    label() { return `${RP.fmtDay(ov.from, "d b")} – ${RP.fmtDay(ov.to, "d b Y")}`; },

    update(host, S) { this.kpis(host, S); this.trend(host, S); this.alerts(host, S); this.actions(host, S); this.insights(host, S); this.top(host, S); this.cats(host, S); this.heat(host, S); },

    kpis(host, S) {
      const x = this.per(S, ov.from, ov.to), n = ov.to - ov.from + 1, pv = this.per(S, ov.from - n, ov.from - 1), m = S.m;
      const el = RP.$("#ov-kpis", host);
      if (!x.length) { el.innerHTML = `<div class="empty">No data for this period and category.</div>`; return; }
      const chg = (a, b) => (b == null || !(b > 0) ? null : a / b - 1);
      const sum = (a, k) => RP.sum(a, (r) => r[k]);
      const rec = sum(x, "sale_amount"), recP = pv.length ? sum(pv, "sale_amount") : null;
      const dem = sum(x, "latent"), demP = pv.length ? sum(pv, "latent") : null;
      const unmet = sum(x, "lost") / Math.max(dem, 1e-9), unmetP = pv.length ? sum(pv, "lost") / Math.max(sum(pv, "latent"), 1e-9) : null;
      const so = sum(x, "stock_h") / (16 * x.length), soP = pv.length ? sum(pv, "stock_h") / (16 * pv.length) : null;
      const recs = this.recsCat(S);
      const attn = new Set(recs.filter((r) => r.urgency === "High" || r.urgency === "Medium").map((r) => r.product_id)).size;
      const high = new Set(recs.filter((r) => r.urgency === "High").map((r) => r.product_id)).size;
      const ids = this.ids(S), nan = RP.classifyAnomalies(S, RP.st.zthr).filter((a) => !ids || ids.has(a.product_id)).length;
      const ev = RP.rows(S.raw.forecast_eval_overall), w = (mm) => (ev.find((r) => r[".model"] === mm) || {}).WAPE;
      const d = (a, b, upGood) => { const c = chg(a, b); return [c, c == null ? null : upGood ? c >= 0 : c <= 0]; };
      const nP = new Set(x.map((r) => r.product_id)).size;
      el.innerHTML = [
        RP.kpi("Recorded sales", RP.fmtNum(rec, 0), `${this.label()} · ${nP} products · normalised units`, "cart", "neutral", ...d(rec, recP, true)),
        RP.kpi("Estimated demand", RP.fmtNum(dem, 0), "Recorded sales plus estimated sales lost to stockouts (a model estimate)", "chart", "neutral", ...d(dem, demP, true)),
        RP.kpi("Estimated unmet demand", RP.fmtPct(unmet, 1), `${RP.fmtNum(sum(x, "lost"), 0)} units of estimated demand went unmet`, "box", RP.toneFor(unmet, 0.05, 0.15), ...d(unmet, unmetP, false)),
        RP.kpi("Stockout-hour rate", RP.fmtPct(so, 1), "Share of 06:00–22:00 trading hours out of stock", "store", RP.toneFor(so, 0.08, 0.15), ...d(so, soP, false)),
        RP.kpi("Needs attention", String(attn), `${high} high urgency · as of ${RP.fmtDay(S.lastDay, "d b")} · ${nan} anomalies at |z| ≥ ${RP.st.zthr.toFixed(1)}`, "alert", high > 0 ? "warning" : "good"),
        RP.kpi(`Forecast error (${m.chosen_model.toUpperCase()})`, RP.fmtPct(w(m.chosen_model), 1), `WAPE on the held-out week; seasonal naive ${RP.fmtPct(w("snaive"), 1)}. Lower is better.`, "target"),
      ].join("");
    },

    trend(host, S) {
      const x = this.per(S, ov.from, ov.to);
      const by = new Map();
      for (const r of x) { let a = by.get(r.d); if (!a) by.set(r.d, (a = { d: r.d, dt: r.dt, split: r.split, observed: 0, latent: 0, stockout_hours: 0 })); a.observed += r.sale_amount; a.latent += r.latent; a.stockout_hours += r.stock_h; }
      const a = [...by.values()].sort((p, q) => p.d - q.d);
      RP.chStoreTrend(RP.$("#ov-store", host), a);
      if (!a.length) { RP.$("#ov-store-note", host).innerHTML = ""; return; }
      const gap = RP.sum(a, (r) => r.latent - r.observed), worst = a.reduce((p, q) => (q.latent - q.observed > p.latent - p.observed ? q : p));
      RP.$("#ov-store-note", host).innerHTML = RP.note(`Between ${this.label()}, estimated demand exceeds recorded sales by ${RP.fmtNum(gap, 1)} units (${RP.fmtPct(gap / Math.max(RP.sum(a, (r) => r.latent), 1e-9), 1)} of estimated demand). The largest gap was on ${RP.fmtDay(worst.d, "a d b")} (${RP.fmtNum(worst.latent - worst.observed, 1)} units, ${worst.stockout_hours} stockout hours). Estimated demand is a model output, not a measurement.`);
    },

    alerts(host, S) {
      const r = this.recsCat(S).filter((x) => x.action === "Consider replenishing earlier");
      const el = RP.$("#ov-alerts", host);
      if (!r.length) { el.innerHTML = `<div class="empty">${RP.icon("check")} No products currently meet the stockout rules.</div>`; return; }
      const nTotal = new Set(r.map((x) => x.product_id)).size, top = r.slice(0, 6), thr = S.m.risk_threshold;
      el.innerHTML = `<div class="alert-list">${top.map((x) => {
        const sev = x.urgency === "High" ? "critical" : "warning", col = x.risk == null ? RP.COL.muted : x.risk >= thr ? RP.COL.red : RP.COL.amber;
        return `<button type="button" class="alert" data-pid="${x.product_id}"><span class="alert-sev ${sev}"></span>
          <span class="alert-name">${RP.plabel(x.product_id)} · ${RP.esc((S.prod.get(x.product_id) || {}).category)}</span>
          <span class="alert-meta">${RP.badge(sev === "critical" ? "Critical" : "Warning", sev)}<span class="riskbar"><span style="width:${Math.round(100 * Math.min(1, x.risk || 0))}%;background:${col}"></span></span><span class="riskval">next-day risk ${RP.fmtPct(x.risk)}</span></span>
          <span class="alert-why">Out of stock 4+ hours on ${x.stockout_days7} of the last 7 days · ${RP.fmtPct(x.lost_share7)} of demand unmet</span></button>`;
      }).join("")}</div>` + RP.note(`Top ${top.length} of ${nTotal} products that meet the stockout rule (R1). Risk is a historical-pattern score for tomorrow, not stock on hand: the data has no inventory field.`);
    },

    actions(host, S) {
      const r = this.recsCat(S), uniq = (f) => new Set(r.filter(f).map((x) => x.product_id)).size;
      const tiles = [["", uniq((x) => x.action !== "Maintain current approach"), "All products needing action", "layers"],
        ...Object.keys(ACTION_ICONS).map((a) => [a, uniq((x) => x.action === a), a, ACTION_ICONS[a]]).filter((t) => t[1] > 0)];
      RP.$("#ov-tiles", host).innerHTML = tiles.map(([k, n, l, ic]) => `<button type="button" class="action${ov.action === k ? " active" : ""}" data-a="${RP.esc(k)}">
        <span style="display:flex;justify-content:space-between;align-items:center"><span class="action-n">${n}</span><span style="color:var(--muted)">${RP.icon(ic)}</span></span><span class="action-l">${RP.esc(l)}</span></button>`).join("");
      const seen = new Set();
      const rows = ov.action ? r.filter((x) => x.action === ov.action) : r.filter((x) => x.action !== "Maintain current approach" && !seen.has(x.product_id) && seen.add(x.product_id));
      RP.table(RP.$("#ov-queue", host), rows, [
        { key: "product_id", label: "Product", width: 86, cls: "pid", render: (x) => RP.plabel(x.product_id) },
        { key: "action", label: "Action" },
        { key: "urgency", label: "Urgency", width: 92, render: (x) => RP.badge(x.urgency, RP.urgKind(x.urgency)), sortValue: (x) => ({ High: 3, Medium: 2, Low: 1, Info: 0 }[x.urgency]) },
        { key: "reason", label: "Why", cls: "why", sortable: false },
        { key: "reliability", label: "Forecast", width: 92, render: (x) => RP.badge(x.reliability, RP.relKind(x.reliability)) },
        { key: "priority", label: "Priority", num: true, width: 80, render: (x) => x.priority.toFixed(2) },
      ], { search: true, placeholder: "Search products, actions, reasons…", pageSize: 6, empty: "No products currently need this action.",
        onClick: (x) => RP.goto("product", { product: x.product_id, date: null }) });
    },

    insights(host, S) {
      const x = this.per(S, ov.from, ov.to), n = ov.to - ov.from + 1, pv = this.per(S, ov.from - n, ov.from - 1);
      const el = RP.$("#ov-insights", host);
      if (!x.length) { el.innerHTML = ""; return; }
      const out = [], add = (icon, kind, html) => out.push(`<div class="insight"><span class="insight-icon ${kind}">${RP.icon(icon)}</span><p>${html}</p></div>`);
      const byp = new Map();
      for (const r of x) { const a = byp.get(r.product_id) || { lost: 0, latent: 0 }; a.lost += r.lost; a.latent += r.latent; byp.set(r.product_id, a); }
      const share = RP.sum(x, (r) => r.lost) / Math.max(RP.sum(x, (r) => r.latent), 1e-9);
      const over20 = [...byp.values()].filter((a) => a.lost / Math.max(a.latent, 1e-9) > 0.2).length;
      add("box", share >= 0.15 ? "bad" : share >= 0.05 ? "warn" : "", `<strong>${RP.fmtPct(share)} of estimated demand went unmet.</strong> ${over20} of ${byp.size} products lost more than 20% of their estimated demand to stockouts.`);
      if (pv.length) {
        const ch = RP.sum(x, (r) => r.latent) / Math.max(RP.sum(pv, (r) => r.latent), 1e-9) - 1;
        const cc = new Map(); for (const r of x) cc.set(r.first_category_id, (cc.get(r.first_category_id) || 0) + r.latent);
        for (const r of pv) cc.set(r.first_category_id, (cc.get(r.first_category_id) || 0) - r.latent);
        const lead = [...cc.entries()].sort((a, b) => Math.abs(b[1]) - Math.abs(a[1]))[0];
        add(ch >= 0 ? "up" : "down", "gold", `<strong>Estimated demand is ${ch >= 0 ? "up" : "down"} ${RP.fmtPct(Math.abs(ch))}</strong> versus the previous ${n} days${lead ? `; the biggest change is in Category ${lead[0]} (${lead[1] >= 0 ? "+" : "−"}${RP.fmtNum(Math.abs(lead[1]), 1)} units)` : ""}.`);
      }
      const w = RP.rows(S.raw.store_weekday_hour);
      if (w.length) {
        const byH = new Map(), byD = new Map();
        for (const r of w) { byH.set(r.hour, (byH.get(r.hour) || 0) + r.mean_sales); byD.set(r.weekday, (byD.get(r.weekday) || 0) + r.mean_sales); }
        const h = [...byH.entries()].sort((a, b) => b[1] - a[1])[0][0], dd = [...byD.entries()].sort((a, b) => b[1] - a[1])[0][0];
        const ids = new Set(x.map((r) => r.product_id));
        const so = S.products.filter((p) => ids.has(p.product_id) && p.median_sellout_hour != null).map((p) => p.median_sellout_hour);
        add("clock", "", `<strong>Busiest hour: ${RP.pad2(h)}:00; busiest day: ${["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"][dd - 1]}.</strong> ` +
          (so.length ? `${so.length} products are usually out of stock by mid-evening; the median sell-out hour among them is ${RP.pad2(Math.round(RP.median(so)))}:00.` : "No product sells out on most days."));
      }
      const ids = new Set(x.map((r) => r.product_id));
      const a = RP.classifyAnomalies(S, RP.st.zthr).filter((q) => q.d >= ov.from && q.d <= ov.to && ids.has(q.product_id)), ue = a.filter((q) => q.cause === "Unexplained");
      const lastU = ue.reduce((p, q) => (!p || q.d > p.d ? q : p), null);
      add("search", ue.length ? "warn" : "", `<strong>${a.length} unusual product-days, ${ue.length} unexplained.</strong> ` + (lastU ? `Most recent: ${RP.plabel(lastU.product_id)} on ${RP.fmtDay(lastU.d, "a d b")} (${lastU.direction}). These have no stockout, promotion, holiday or heavy-rain flag.` : "Every flagged day coincides with a stockout, promotion, holiday or heavy rain."));
      const pp = new Map();
      for (const r of x) { if (r.stock_h >= 4) continue; const k = r.product_id; const e = pp.get(k) || { p: [], n: [] }; (r.promo === 1 ? e.p : e.n).push(r.latent); pp.set(k, e); }
      const ratios = [...pp.values()].filter((e) => e.p.length && e.n.length).map((e) => RP.mean(e.p) / Math.max(RP.mean(e.n), 1e-9));
      if (ratios.length >= 5) { const rr = RP.median(ratios);
        add("tag", "", `<strong>Promotion days: median ${rr >= 1 ? "+" : "−"}${RP.fmtPct(Math.abs(rr - 1))} estimated demand.</strong> Compared within the same ${ratios.length} products on mostly in-stock days. This is an association, not a measured promotion effect.`); }
      el.innerHTML = out.join("");
    },

    top(host, S) {
      const x = this.per(S, ov.from, ov.to), by = new Map();
      for (const r of x) { const a = by.get(r.product_id) || { product_id: r.product_id, observed: 0, latent: 0 }; a.observed += r.sale_amount; a.latent += r.latent; by.set(r.product_id, a); }
      const rows = [...by.values()].map((a) => ({ ...a, unmet_share: (a.latent - a.observed) / Math.max(a.latent, 1e-9) })).sort((a, b) => b.latent - a.latent).slice(0, 12);
      RP.chStackedH(RP.$("#ov-top", host), rows, (q) => RP.plabel(q.product_id), (ev) => {
        const pid = Number(String(ev.points[0].y).replace(/^P/, "")); if (pid) RP.goto("product", { product: pid, date: null });
      });
    },
    cats(host, S) {
      const x = S.daily.filter((r) => r.d >= ov.from && r.d <= ov.to), by = new Map();
      for (const r of x) { const a = by.get(r.first_category_id) || { c: r.first_category_id, observed: 0, latent: 0, stock_h: 0, n: 0 }; a.observed += r.sale_amount; a.latent += r.latent; a.stock_h += r.stock_h; a.n++; by.set(r.first_category_id, a); }
      const nProd = new Map(); for (const p of S.products) nProd.set(p.first_category_id, (nProd.get(p.first_category_id) || 0) + 1);
      const rows = [...by.values()].map((a) => ({ ...a, unmet_share: (a.latent - a.observed) / Math.max(a.latent, 1e-9),
        hover1: `${nProd.get(a.c)} products · stockout-hour rate ${Math.round(100 * a.stock_h / (16 * a.n))}%` })).sort((a, b) => b.latent - a.latent).slice(0, 12);
      RP.chStackedH(RP.$("#ov-cats", host), rows, (q) => "Category " + q.c, (ev) => {
        const cid = String(ev.points[0].y).replace(/^Category /, "");
        ov.cat = ov.cat === cid ? "" : cid; RP.$("#ov-cat", host).value = ov.cat; this.update(host, S);
      }, 96);
    },
    heat(host, S) {
      const ids = this.ids(S), d = S.daily.filter((r) => !ids || ids.has(r.product_id)), w = d.filter((r) => r.d >= ov.from && r.d <= ov.to);
      const score = new Map();
      for (const r of w) score.set(r.product_id, (score.get(r.product_id) || 0) + (r.z != null && Math.abs(r.z) >= RP.st.zthr ? Math.abs(r.z) : 0));
      const n = { top40: 40, top20: 20, all: Infinity }[ov.heatRows];
      const keep = new Set([...score.entries()].sort((a, b) => b[1] - a[1] || a[0] - b[0]).slice(0, n).map((e) => e[0]));
      const el = RP.$("#ov-heat", host); el.style.height = Math.max(320, 120 + 13 * keep.size) + "px";
      RP.chHeatmap(el, d.filter((r) => keep.has(r.product_id)), RP.labelOf, ov.from, ov.to, ov.heatMode, (ev) => {
        const p = ev.points[0]; const pid = Number(String(p.y).replace(/^P/, "")); if (pid && p.x) RP.goto("product", { product: pid, date: String(p.x).slice(0, 10) });
      });
      const a = RP.classifyAnomalies(S, RP.st.zthr).filter((q) => q.d >= ov.from && q.d <= ov.to && (!ids || ids.has(q.product_id)));
      const legend = { z: "Green = below the product's normal level, gold = above; a white × marks a day with 4+ stockout hours, where the low value is censored.",
        demand: "Darker = more estimated demand relative to the product's own average in this period; red × = 4+ stockout hours.", stockout: "Darker red = more trading hours out of stock (0–16)." }[ov.heatMode];
      RP.$("#ov-heat-note", host).innerHTML = RP.note(`Showing ${keep.size} of ${ids ? ids.size : S.products.length} products, ordered by product ID; the selection ranks products by the size of their flags in the period. In this period, ${a.length} product-days were flagged at |z| ≥ ${RP.st.zthr.toFixed(1)}: ${a.filter((q) => q.cause !== "Unexplained").length} explained by a stockout, promotion, holiday or rain, and ${a.filter((q) => q.cause === "Unexplained").length} unexplained. ${legend}`);
    },
  };
})();
