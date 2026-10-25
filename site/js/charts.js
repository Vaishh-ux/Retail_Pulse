/* RetailPulse static dashboard - charts (Plotly.js). Same colour roles as the R app:
   recorded = slate grey, estimated demand = forest, forecast = forest dashed + band,
   stockout = red, promotion = light gold shading, anomaly = plum, scenario = gold. */
"use strict";
(function () {
  const RP = window.RP;
  const C = RP.COL = {
    forest: "#173B35", forest2: "#2F6B5E", gold: "#D9A441", goldDk: "#A87A1E", sage: "#DCEBE3", red: "#DC5555", amber: "#C98A12",
    ink2: "#4C5A55", muted: "#86928D", grid: "#E6ECE8", recorded: "#5E6B66", demand: "#2F6B5E", band: "rgba(47,107,94,0.16)",
    stockLt: "rgba(220,85,85,0.16)", promoLt: "rgba(217,164,65,0.18)", anomaly: "#7B4F8E", baseline: "#A9B5B0",
  };
  const DIVERGING = [[0, "#0F2E29"], [0.2, "#2F6B5E"], [0.36, "#B9D6C8"], [0.44, "#F4F6F4"], [0.56, "#F4F6F4"], [0.64, "#F1DDAE"], [0.8, "#D9A441"], [1, "#8A5F12"]];
  const SEQ = [[0, "#F3F7F5"], [0.35, "#B9D6C8"], [1, "#173B35"]];
  const UNIT = "Sales (normalised units)";
  const CFG = { displaylogo: false, responsive: true, modeBarButtonsToRemove: ["lasso2d", "select2d", "autoScale2d", "toggleSpikelines"] };

  const base = (extra = {}) => ({
    font: { family: "Inter, system-ui, sans-serif", size: 12, color: C.ink2 },
    paper_bgcolor: "rgba(0,0,0,0)", plot_bgcolor: "rgba(0,0,0,0)", margin: { l: 56, r: 16, t: 16, b: 44 },
    hovermode: "x unified", hoverlabel: { bgcolor: "#fff", bordercolor: "#DDE5E0", font: { color: "#16231F", size: 12 } },
    legend: { orientation: "h", x: 0, y: 1.14, font: { size: 11 } },
    xaxis: { gridcolor: C.grid, zeroline: false, linecolor: "#C9D3CE" },
    yaxis: { gridcolor: C.grid, zeroline: false, rangemode: "tozero" }, ...extra,
  });
  const merge = (a, b) => { const o = { ...a }; for (const k in b) o[k] = b[k] && typeof b[k] === "object" && !Array.isArray(b[k]) && a[k] ? { ...a[k], ...b[k] } : b[k]; return o; };
  RP.plot = (el, traces, layout, onClick) => {
    if (typeof el === "string") el = document.getElementById(el);
    if (!el) return;
    Plotly.react(el, traces, layout, CFG);
    if (onClick) { el.removeAllListeners && el.removeAllListeners("plotly_click"); el.on("plotly_click", onClick); }
  };
  RP.emptyPlot = (el, msg = "No data for this selection") => RP.plot(el, [], { ...base(), xaxis: { visible: false }, yaxis: { visible: false },
    annotations: [{ text: msg, showarrow: false, font: { size: 14, color: C.muted } }] });
  const shade = (days, color) => {
    const s = [...new Set(days)].sort((a, b) => a - b), out = [];
    for (let i = 0; i < s.length; ) {
      let j = i; while (j + 1 < s.length && s[j + 1] === s[j] + 1) j++;
      out.push({ type: "rect", xref: "x", yref: "paper", x0: RP.iso(s[i] - 1) + "T12:00", x1: RP.iso(s[j]) + "T12:00", y0: 0, y1: 1, fillcolor: color, line: { width: 0 }, layer: "below" });
      i = j + 1;
    }
    return out;
  };
  const ma7 = (a) => a.map((_, i) => (i < 6 ? null : a.slice(i - 6, i + 1).reduce((s, x) => s + x, 0) / 7));

  /* product trend: recorded vs estimated demand, stockouts, promos, anomalies, forecast, comparison */
  RP.chTrend = (el, dp, an, fc, horizon, cmp, cmpLabel) => {
    if (!dp.length) return RP.emptyPlot(el, "No days in the selected range");
    const x = dp.map((r) => r.dt), so = dp.filter((r) => r.stock_h >= 4);
    const t = [
      { x, y: dp.map((r) => r.sale_amount), name: "Recorded sales", type: "scatter", mode: "lines", line: { color: C.recorded, width: 1.4 }, hovertemplate: "Recorded %{y:.2f}<extra></extra>" },
      { x, y: dp.map((r) => r.latent), name: "Estimated demand", type: "scatter", mode: "lines", line: { color: C.demand, width: 2.2 }, hovertemplate: "Estimated demand %{y:.2f}<extra></extra>" },
      { x, y: ma7(dp.map((r) => r.latent)), name: "7-day average (est. demand)", type: "scatter", mode: "lines", line: { color: C.demand, width: 1, dash: "dot" }, hovertemplate: "7-day avg %{y:.2f}<extra></extra>" },
    ];
    if (cmp && cmp.length) t.push({ x: cmp.map((r) => r.dt), y: cmp.map((r) => r.latent), name: "Estimated demand: " + cmpLabel, type: "scatter", mode: "lines",
      line: { color: C.goldDk, width: 1.6, dash: "dot" }, hovertemplate: cmpLabel + " est. demand %{y:.2f}<extra></extra>" });
    if (so.length) t.push({ x: so.map((r) => r.dt), y: so.map((r) => r.sale_amount), name: "Stockout day (4+ h out)", type: "scatter", mode: "markers",
      marker: { symbol: "circle-open", size: 9, color: C.red, line: { width: 2 } }, text: so.map((r) => r.stock_h + " of 16 trading hours out of stock"), hovertemplate: "%{text}<extra></extra>" });
    if (an && an.length) t.push({ x: an.map((a) => a.dt), y: an.map((a) => a.observed), name: "Anomaly", type: "scatter", mode: "markers",
      marker: { symbol: "diamond-open", size: 11, color: C.anomaly, line: { width: 2 } }, text: an.map((a) => `${a.cause} (z = ${a.z})`), hovertemplate: "%{text}<extra></extra>" });
    const shapes = shade(dp.filter((r) => r.promo === 1).map((r) => r.d), C.promoLt);
    let ann = [];
    if (fc && fc.length) {
      const f = fc.slice(0, horizon);
      t.push({ x: f.map((r) => r.dt).concat(f.map((r) => r.dt).reverse()), y: f.map((r) => r.hi80).concat(f.map((r) => r.lo80).reverse()), fill: "toself", fillcolor: C.band,
        line: { width: 0 }, name: "80% prediction interval", type: "scatter", mode: "lines", hoverinfo: "skip" });
      t.push({ x: f.map((r) => r.dt), y: f.map((r) => r.mean), name: "Forecast (estimated demand)", type: "scatter", mode: "lines", line: { color: C.demand, width: 2, dash: "dash" }, hovertemplate: "Forecast %{y:.2f}<extra></extra>" });
      const xl = RP.iso(dp[dp.length - 1].d) + "T12:00";
      shapes.push({ type: "line", xref: "x", yref: "paper", x0: xl, x1: xl, y0: 0, y1: 1, line: { color: C.muted, width: 1, dash: "dot" } });
      ann = [{ x: xl, y: 1, xref: "x", yref: "paper", text: "data ends | forecast", showarrow: false, yanchor: "bottom", font: { size: 10, color: C.muted } }];
    }
    t.push({ x, y: dp.map((r) => r.stock_h), type: "bar", name: "Stockout hours", marker: { color: C.red }, xaxis: "x", yaxis: "y2", showlegend: false, hovertemplate: "%{y} h out of stock<extra></extra>" });
    RP.plot(el, t, merge(base(), { shapes, annotations: ann, legend: { orientation: "h", x: 0, y: 1.16, font: { size: 11 } },
      yaxis: { title: UNIT, domain: [0.26, 1], gridcolor: C.grid, rangemode: "tozero", zeroline: false },
      yaxis2: { title: "Out (h)", domain: [0, 0.2], range: [0, 16], dtick: 8, gridcolor: C.grid }, xaxis: { type: "date", gridcolor: C.grid, anchor: "y2" } }));
  };

  RP.chStoreTrend = (el, sd) => {
    if (!sd.length) return RP.emptyPlot(el);
    const x = sd.map((r) => r.dt), mx = Math.max(1, ...sd.map((r) => r.stockout_hours));
    RP.plot(el, [
      { x, y: sd.map((r) => r.observed), name: "Recorded sales", type: "scatter", mode: "lines", line: { color: C.recorded, width: 1.5 } },
      { x, y: sd.map((r) => r.latent), name: "Estimated demand", type: "scatter", mode: "lines", line: { color: C.demand, width: 2.4 } },
      { x, y: sd.map((r) => r.stockout_hours), name: "Stockout hours (right axis)", type: "bar", yaxis: "y2", marker: { color: "rgba(220,85,85,0.22)" }, hovertemplate: "%{y} stockout hours<extra></extra>" },
    ], merge(base(), { bargap: 0.35, margin: { l: 56, r: 56, t: 16, b: 44 }, xaxis: { type: "date", gridcolor: C.grid, title: "Date" },
      yaxis: { title: "Store total (normalised units)" }, yaxis2: { overlaying: "y", side: "right", showgrid: false, title: "Stockout hours", range: [0, 3 * mx] },
      shapes: shade(sd.filter((r) => r.split === "eval").map((r) => r.d), "rgba(137,135,129,0.10)") }));
  };

  /* product x date heatmap: mode z | demand | stockout */
  RP.chHeatmap = (el, rows, labelOf, first, last, mode, onClick) => {
    const x = rows.filter((r) => r.d >= first && r.d <= last);
    if (!x.length) return RP.emptyPlot(el, "No days in the selected period");
    const prods = [...new Set(x.map((r) => r.product_id))].sort((a, b) => a - b);
    const days = [...new Set(x.map((r) => r.d))].sort((a, b) => a - b);
    const pi = new Map(prods.map((p, i) => [p, i])), di = new Map(days.map((d, i) => [d, i]));
    const mk = (v) => prods.map(() => days.map(() => v));
    const z = mk(null), st = mk(0), dm = mk(null);
    for (const r of x) { const i = pi.get(r.product_id), j = di.get(r.d); z[i][j] = r.z == null ? null : Math.max(-4, Math.min(4, r.z)); st[i][j] = r.stock_h; dm[i][j] = r.latent; }
    const rel = dm.map((row) => { const v = row.filter((q) => q != null); const m = v.length ? v.reduce((s, q) => s + q, 0) / v.length : 0; return row.map((q) => (q == null ? null : q / Math.max(m, 1e-9))); });
    const ylab = prods.map((p) => labelOf(p)), xlab = days.map((d) => RP.iso(d));
    const text = prods.map((p, i) => days.map((d, j) => `<b>${ylab[i]}</b> · ${RP.fmtDay(d, "a d b")}<br>Estimated demand ${dm[i][j] == null ? "n/a" : dm[i][j].toFixed(2)} (${rel[i][j] == null ? "n/a" : Math.round(100 * rel[i][j]) + "%"} of its usual level)<br>Deviation z = ${z[i][j] == null ? "n/a" : z[i][j].toFixed(1)}<br>${st[i][j] > 0 ? st[i][j] + " h out of stock" : "in stock all trading hours"}`));
    let zz, zmin, zmax, cs, cb;
    if (mode === "stockout") { zz = st; zmin = 0; zmax = 16; cs = [[0, "#F4F6F4"], [0.25, "#F3D3CC"], [1, C.red]]; cb = { title: { text: "Hours out", side: "right" }, thickness: 10, len: 0.6, tickvals: [0, 4, 8, 12, 16] }; }
    else if (mode === "demand") { zz = rel.map((r) => r.map((q) => (q == null ? null : Math.min(q, 2.5)))); zmin = 0; zmax = 2.5; cs = SEQ; cb = { title: { text: "× usual", side: "right" }, thickness: 10, len: 0.6, tickvals: [0, 0.5, 1, 1.5, 2, 2.5], ticktext: ["0", "0.5×", "1× usual", "1.5×", "2×", "≥2.5×"] }; }
    else { zz = z; zmin = -4; zmax = 4; cs = DIVERGING; cb = { title: { text: "Robust z", side: "right" }, thickness: 10, len: 0.6, tickvals: [-4, -2, 0, 2, 4], ticktext: ["≤ −4 below", "−2", "0 normal", "+2", "≥ +4 above"] }; }
    const t = [{ type: "heatmap", x: xlab, y: ylab, z: zz, zmin, zmax, colorscale: cs, text, hoverinfo: "text", xgap: 1.5, ygap: 1.5, colorbar: cb }];
    if (mode !== "stockout") {
      const sx = [], sy = [];
      prods.forEach((p, i) => days.forEach((d, j) => { if (st[i][j] >= 4) { sx.push(xlab[j]); sy.push(ylab[i]); } }));
      if (sx.length) t.push({ type: "scatter", mode: "markers", x: sx, y: sy, name: "4+ h out of stock", hoverinfo: "skip",
        marker: { symbol: "x-thin", size: 7, line: { width: 1.6, color: mode === "z" ? "#ffffff" : C.red } } });
    }
    RP.plot(el, t, merge(base({ hovermode: "closest" }), { xaxis: { type: "category", tickangle: 0, nticks: 7, showgrid: false },
      yaxis: { autorange: "reversed", showgrid: false, tickfont: { size: 10 }, type: "category", categoryorder: "array", categoryarray: ylab, rangemode: "normal" },
      legend: { orientation: "h", x: 0, y: -0.08 }, margin: { l: 56, r: 8, t: 8, b: 56 } }), onClick);
  };

  RP.chStackedH = (el, rows, label, onClick, catMargin = 56) => {
    if (!rows.length) return RP.emptyPlot(el);
    const r = rows.slice().sort((a, b) => a.latent - b.latent), y = r.map(label);
    RP.plot(el, [
      { type: "bar", orientation: "h", y, x: r.map((q) => q.observed), name: "Recorded sales", marker: { color: C.forest2 }, text: r.map((q) => q.hover1 || ""), textposition: "none",
        hovertemplate: "%{y}: recorded %{x:.1f}<br>%{text}<extra></extra>" },
      { type: "bar", orientation: "h", y, x: r.map((q) => q.latent - q.observed), name: "Estimated unmet demand", marker: { color: C.stockLt, line: { color: C.red, width: 1 } },
        text: r.map((q) => Math.round(100 * q.unmet_share) + "% of estimated demand unmet"), textposition: "none", hovertemplate: "%{y}: unmet %{x:.1f} (%{text})<extra></extra>" },
    ], merge(base({ hovermode: "closest" }), { barmode: "stack", xaxis: { title: "Normalised units in period", gridcolor: C.grid },
      yaxis: { type: "category", categoryorder: "array", categoryarray: y, title: "", rangemode: "normal" }, margin: { l: catMargin, r: 12, t: 8, b: 40 },
      legend: { orientation: "h", x: 0, y: -0.2 } }), onClick);
  };

  RP.chWeekdayHour = (el, wdh) => {
    if (!wdh.length) return RP.emptyPlot(el);
    const days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], z = days.map(() => Array(24).fill(null));
    for (const r of wdh) z[r.weekday - 1][r.hour] = r.mean_sales;
    RP.plot(el, [{ type: "heatmap", x: [...Array(24).keys()].map(RP.pad2), y: days, z, colorscale: SEQ, xgap: 1, ygap: 1,
      hovertemplate: "%{y} %{x}:00<br>mean %{z:.3f} per in-stock hour<extra></extra>", colorbar: { title: { text: "Mean sales / h" }, thickness: 10 } }],
      merge(base({ hovermode: "closest" }), { showlegend: false, xaxis: { title: "Hour of day", showgrid: false }, yaxis: { autorange: "reversed", showgrid: false, rangemode: "normal" } }));
  };
  RP.chSellout = (el, cur) => {
    if (!cur.length || cur.every((r) => r.surv === 1)) return RP.emptyPlot(el, "No trading-hour stockouts recorded for this product");
    const col = { weekday: C.forest2, weekend: C.goldDk }, t = [];
    for (const w of ["weekday", "weekend"]) { const g = cur.filter((r) => r.weektype === w).sort((a, b) => a.hour - b.hour); if (g.length)
      t.push({ x: g.map((r) => r.hour), y: g.map((r) => r.surv), name: w === "weekday" ? "Weekdays" : "Weekends", type: "scatter", mode: "lines", line: { shape: "hv", width: 2, color: col[w] }, hovertemplate: "%{x}:00 · %{y:.0%} still in stock<extra></extra>" }); }
    RP.plot(el, t, merge(base(), { yaxis: { title: "Share of days still in stock", range: [0, 1.02], tickformat: ".0%" }, xaxis: { title: "Hour of day", range: [6, 22], dtick: 2 } }));
  };
  RP.chInOut = (el, rows) => {
    if (!rows.length) return RP.emptyPlot(el);
    const g = (o) => rows.filter((r) => r.out === o).sort((a, b) => a.hour - b.hour);
    RP.plot(el, [
      { type: "bar", x: g(0).map((r) => r.hour), y: g(0).map((r) => r.mean_sales), name: "In stock", marker: { color: C.forest2 }, hovertemplate: "%{x}:00 · %{y:.3f}<extra>In stock</extra>" },
      { type: "bar", x: g(1).map((r) => r.hour), y: g(1).map((r) => r.mean_sales), name: "Out of stock", marker: { color: C.red }, hovertemplate: "%{x}:00 · %{y:.3f}<extra>Out of stock</extra>" },
    ], merge(base(), { barmode: "group", yaxis: { title: "Mean recorded sales per hour" }, xaxis: { title: "Hour of day (trading hours)" } }));
  };
  RP.chReplay = (el, g, upto) => {
    if (!g.length) return RP.emptyPlot(el, "No replay data for this product and day");
    const seen = g.filter((r) => r.hour <= upto);
    const shapes = g.filter((r) => r.out === 1 && r.hour >= 6 && r.hour <= 21 && r.hour <= upto).map((r) => ({ type: "rect", x0: r.hour - 0.5, x1: r.hour + 0.5, yref: "paper", y0: 0, y1: 1, fillcolor: C.stockLt, line: { width: 0 }, layer: "below" }));
    shapes.push({ type: "line", x0: upto + 0.5, x1: upto + 0.5, yref: "paper", y0: 0, y1: 1, line: { color: C.ink2, dash: "dot", width: 1 } });
    const h = g.map((r) => r.hour);
    RP.plot(el, [
      { x: h.concat(h.slice().reverse()), y: g.map((r) => r.cum_hi).concat(g.map((r) => r.cum_lo).reverse()), fill: "toself", fillcolor: C.band, line: { width: 0 }, name: "Expected range (80%)", type: "scatter", mode: "lines", hoverinfo: "skip" },
      { x: h, y: g.map((r) => r.cum_exp), name: "Expected (forecast × hourly profile)", type: "scatter", mode: "lines", line: { color: C.forest2, dash: "dash", width: 1.6 } },
      { x: seen.map((r) => r.hour), y: seen.map((r) => r.cum_obs), name: "Observed so far (cumulative)", type: "scatter", mode: "lines+markers", line: { color: C.recorded, width: 2.6 }, marker: { size: 5 } },
    ], merge(base(), { shapes, yaxis: { title: "Cumulative sales today" }, xaxis: { title: "Hour of day", range: [0, 23.5], dtick: 3 } }));
  };
  RP.chScenario = (el, hist, f, mult) => {
    if (!hist.length || !f.length) return RP.emptyPlot(el, "Not enough history to forecast this product");
    const xl = RP.iso(hist[hist.length - 1].d) + "T12:00";
    const t = [
      { x: hist.map((r) => r.dt), y: hist.map((r) => r.sale_amount), name: "Recorded sales", type: "scatter", mode: "lines", line: { color: C.recorded, width: 1.3 } },
      { x: hist.map((r) => r.dt), y: hist.map((r) => r.latent), name: "Estimated demand", type: "scatter", mode: "lines", line: { color: C.demand, width: 2 } },
      { x: f.map((r) => r.dt).concat(f.map((r) => r.dt).reverse()), y: f.map((r) => r.hi80).concat(f.map((r) => r.lo80).reverse()), fill: "toself", fillcolor: C.band, line: { width: 0 }, name: "80% interval (model)", type: "scatter", mode: "lines", hoverinfo: "skip" },
      { x: f.map((r) => r.dt), y: f.map((r) => r.mean), name: "Model forecast", type: "scatter", mode: "lines", line: { color: C.demand, width: 2, dash: "dash" } },
    ];
    if (Math.abs(mult - 1) > 1e-9) t.push({ x: f.map((r) => r.dt), y: f.map((r) => r.mean * mult), name: "Hypothetical scenario", type: "scatter", mode: "lines", line: { color: C.gold, width: 2.6 } });
    RP.plot(el, t, merge(base(), { yaxis: { title: UNIT }, xaxis: { type: "date", title: "Date", gridcolor: C.grid },
      shapes: [{ type: "line", xref: "x", yref: "paper", x0: xl, x1: xl, y0: 0, y1: 1, line: { color: C.muted, dash: "dot", width: 1 } }] }));
  };
  RP.chThreshold = (el, zs, cur) => {
    const grid = []; for (let t = 2; t <= 5.0001; t += 0.25) grid.push(RP.round(t, 2));
    const n = grid.map((t) => zs.filter((z) => Math.abs(z) >= t).length);
    RP.plot(el, [{ x: grid, y: n, type: "scatter", mode: "lines+markers", line: { color: C.forest2 }, marker: { color: C.forest2 }, hovertemplate: "|z| ≥ %{x}: %{y} flags<extra></extra>" }],
      merge(base(), { showlegend: false, xaxis: { title: "Threshold |z|" }, yaxis: { title: "Flags" },
        shapes: [{ type: "line", x0: cur, x1: cur, yref: "paper", y0: 0, y1: 1, line: { color: C.goldDk, width: 1.5, dash: "dot" } }] }));
  };
  RP.chModelBars = (el, cv, ev) => {
    const rows = [...cv.map((r) => ({ ...r, w: "Rolling-origin CV (training)" })), ...ev.map((r) => ({ ...r, w: "Hold-out (evaluation week)" }))];
    if (!rows.length) return RP.emptyPlot(el);
    const t = ["ets", "snaive"].map((m) => { const g = rows.filter((r) => r[".model"] === m); return { type: "bar", x: g.map((r) => r.w), y: g.map((r) => r.WAPE), name: m === "ets" ? "ETS" : "Seasonal naive",
      marker: { color: m === "ets" ? C.forest2 : C.baseline }, text: g.map((r) => (100 * r.WAPE).toFixed(1) + "%"), textposition: "outside", hovertemplate: "%{fullData.name}: WAPE %{y:.1%}<extra></extra>" }; });
    RP.plot(el, t, merge(base(), { barmode: "group", yaxis: { title: "WAPE on in-stock days (lower is better)", tickformat: ".0%", range: [0, Math.max(...rows.map((r) => r.WAPE)) * 1.2] } }));
  };
  RP.chActualFc = (el, ev) => {
    if (!ev.length) return RP.emptyPlot(el);
    const t = [];
    for (const m of ["ets", "snaive"]) { const g = ev.filter((r) => r[".model"] === m).sort((a, b) => (a.dt > b.dt ? 1 : -1)); if (g.length)
      t.push({ x: g.map((r) => r.dt), y: g.map((r) => r.mean), name: m === "ets" ? "ETS forecast" : "Seasonal-naive forecast", type: "scatter", mode: "lines", line: { dash: "dash", width: 2, color: m === "ets" ? C.forest2 : C.baseline } }); }
    const a = ev.filter((r) => r[".model"] === "ets").sort((x, y) => (x.dt > y.dt ? 1 : -1));
    t.push({ x: a.map((r) => r.dt), y: a.map((r) => r.sale_amount), name: "Recorded sales", type: "scatter", mode: "markers",
      marker: { color: a.map((r) => (r.any_stockout === 1 ? "#fff" : C.recorded)), size: 9, line: { color: a.map((r) => (r.any_stockout === 1 ? C.red : C.recorded)), width: 2 } },
      text: a.map((r) => (r.any_stockout === 1 ? "had a stockout: excluded from scoring" : "in stock: scored")), hovertemplate: "%{y:.2f} (%{text})<extra></extra>" });
    RP.plot(el, t, merge(base(), { yaxis: { title: UNIT }, xaxis: { title: "Date", type: "date" } }));
  };
  RP.chLatentScatter = (el, v) => {
    if (!v.length) return RP.emptyPlot(el);
    const mx = Math.max(...v.map((r) => Math.max(r.actual, r.estimate)));
    RP.plot(el, [
      { x: v.map((r) => r.actual), y: v.map((r) => r.estimate), type: "scattergl", mode: "markers", name: "Profile estimate", marker: { color: "rgba(47,107,94,0.35)", size: 5 }, hovertemplate: "actual %{x:.2f} · estimate %{y:.2f}<extra></extra>" },
      { x: v.map((r) => r.actual), y: v.map((r) => r.observed_only), type: "scattergl", mode: "markers", name: "Observed sales only", marker: { color: "rgba(94,107,102,0.25)", size: 4 } },
      { x: [0, mx], y: [0, mx], type: "scatter", mode: "lines", name: "Perfect estimate", line: { color: C.muted, dash: "dot", width: 1 }, hoverinfo: "skip" },
    ], merge(base({ hovermode: "closest" }), { xaxis: { title: "Actual day total (hidden hours known)" }, yaxis: { title: "Estimated day total" } }));
  };
  RP.chLatentCutoff = (el, b) => RP.plot(el, [
    { x: b.map((r) => r.cutoff_hour), y: b.map((r) => r.wape_profile), name: "Profile method", type: "scatter", mode: "lines", line: { color: C.forest2, width: 2 } },
    { x: b.map((r) => r.cutoff_hour), y: b.map((r) => r.wape_observed), name: "Observed sales only", type: "scatter", mode: "lines", line: { color: C.muted, width: 2, dash: "dash" } },
  ], merge(base(), { yaxis: { title: "WAPE", tickformat: ".0%" }, xaxis: { title: "Simulated stockout starts at (hour)" } }));
  RP.chCalibration = (el, cal) => RP.plot(el, [
    { x: cal.map((r) => r.mean_pred), y: cal.map((r) => r.observed_rate), type: "scatter", mode: "lines+markers", name: "Logistic model", line: { color: C.forest2 },
      marker: { color: C.forest2, size: cal.map((r) => Math.max(6, Math.sqrt(r.n) * 1.5)) }, text: cal.map((r) => "n = " + r.n), hovertemplate: "predicted %{x:.0%} · observed %{y:.0%} (%{text})<extra></extra>" },
    { x: [0, 1], y: [0, 1], type: "scatter", mode: "lines", name: "Perfect calibration", line: { color: C.muted, dash: "dot", width: 1 }, hoverinfo: "skip" },
  ], merge(base({ hovermode: "closest" }), { xaxis: { title: "Predicted probability", range: [0, 1], tickformat: ".0%" }, yaxis: { title: "Observed event rate", range: [0, 1], tickformat: ".0%" } }));
  RP.chCoefs = (el, co) => {
    const nice = { so_rate7: "Share of last 7 days with stockout", so_hours7: "Mean stockout hours, last 7 days", yest_event: "Stockout event yesterday",
      demand_ratio: "Recent demand change (7d / 28d)", promo: "Promotion on the day", holiday_flag: "Holiday", weekend: "Weekend" };
    const r = co.filter((x) => x.term !== "(Intercept)").sort((a, b) => a.odds_ratio - b.odds_ratio), y = r.map((x) => nice[x.term] || x.term);
    RP.plot(el, [{ type: "scatter", mode: "markers", y, x: r.map((x) => x.odds_ratio), marker: { color: C.forest2, size: 9 },
      error_x: { type: "data", symmetric: false, array: r.map((x) => x.or_hi95 - x.odds_ratio), arrayminus: r.map((x) => x.odds_ratio - x.or_lo95), color: C.ink2, thickness: 1.2 },
      hovertemplate: "%{y}: odds ratio %{x:.2f}<extra></extra>" }],
      merge(base({ hovermode: "closest" }), { showlegend: false, xaxis: { type: "log", title: "Odds ratio (log scale, 95% CI)" }, yaxis: { title: "", type: "category", categoryorder: "array", categoryarray: y, rangemode: "normal" },
        margin: { l: 230, r: 16, t: 16, b: 44 }, shapes: [{ type: "line", x0: 1, x1: 1, yref: "paper", y0: 0, y1: 1, line: { color: C.muted, dash: "dot" } }] }));
  };
  RP.chVariability = (el, v) => RP.plot(el, [{ type: "scatter", mode: "markers", x: v.map((r) => r.mean_latent), y: v.map((r) => r.cv), text: v.map((r) => "P" + r.product_id),
    marker: { size: v.map((r) => Math.max(6, 40 * r.unmet_share + 6)), color: v.map((r) => r.unmet_share), colorscale: [[0, C.sage], [0.5, "#E9B7A8"], [1, C.red]], showscale: true,
      colorbar: { title: { text: "Unmet share" }, tickformat: ".0%", thickness: 10 }, line: { color: "#fff", width: 0.5 } },
    hovertemplate: "%{text}<br>mean %{x:.2f} · CV %{y:.2f}<extra></extra>" }],
    merge(base({ hovermode: "closest" }), { showlegend: false, xaxis: { title: "Mean estimated daily demand (normalised units)" }, yaxis: { title: "Coefficient of variation" } }));
  RP.chHist = (el, a, b) => RP.plot(el, [
    { type: "histogram", x: a, name: "Recorded sales", marker: { color: C.recorded }, opacity: 0.55, nbinsx: 40 },
    { type: "histogram", x: b, name: "Estimated demand", marker: { color: C.forest2 }, opacity: 0.55, nbinsx: 40 },
  ], merge(base({ hovermode: "closest" }), { barmode: "overlay", xaxis: { title: "Daily total (normalised units)" }, yaxis: { title: "Product-days" } }));
})();
