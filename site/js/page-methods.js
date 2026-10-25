/* Page 5 - Data quality and methods (all numbers computed in R) */
"use strict";
(function () {
  const RP = window.RP;
  RP.pages.methods = {
    tab: "prep",
    render(host, S) {
      host.innerHTML = `<div class="tabs" role="tablist">${[["prep", "Data preparation"], ["eda", "Exploratory analysis"], ["models", "Models and evaluation"], ["data", "Dataset and limitations"]]
        .map(([k, l]) => `<button role="tab" data-tab="${k}" class="${k === this.tab ? "active" : ""}">${l}</button>`).join("")}</div><div id="me-body"></div>`;
      RP.$$(".tabs button", host).forEach((b) => b.addEventListener("click", () => {
        this.tab = b.dataset.tab; RP.$$(".tabs button", host).forEach((x) => x.classList.toggle("active", x === b)); this.draw(host, S);
      }));
      this.draw(host, S);
    },
    onShow(host, S) { if (this.tab === "models") this.draw(host, S); },
    draw(host, S) {
      const b = RP.$("#me-body", host), q = S.q, m = S.m, R = (k) => RP.rows(S.raw[k]);
      const simple = (el, rows, cols) => RP.table(el, rows, cols.map((c) => (typeof c === "string" ? { key: c, label: c, sortable: false } : { sortable: false, ...c })), { pageSize: 20 });
      if (this.tab === "prep") {
        const mb = (q.raw_profile && q.raw_profile.missing_by_column) || {};
        const imp = { precpt: q.imputed_precpt, avg_temperature: q.imputed_avg_temperature, avg_humidity: q.imputed_avg_humidity, avg_wind_level: q.imputed_avg_wind_level };
        const issues = ["duplicates_removed", "hourly_wrong_length", "hourly_daily_mismatch", "negative_sales_rows", "discount_out_of_range", "stock_count_mismatch"].reduce((s, k) => s + (q[k] || 0), 0);
        const totMiss = Object.values(mb).reduce((s, v) => s + Number(v || 0), 0), totImp = Object.values(imp).reduce((s, v) => s + Number(v || 0), 0);
        b.innerHTML = `<div class="kpis">${[
          RP.kpi("Raw rows", RP.fmtNum(q.raw_profile.rows, 0), `${q.raw_profile.columns} columns · ${q.raw_profile.products} products`, "db"),
          RP.kpi("Cleaned rows", RP.fmtNum(q.rows_clean, 0), `${q.date_min} to ${q.date_max}`, "broom"),
          RP.kpi("Duplicates removed", String(q.duplicates_removed || 0), "duplicate product-days", "copy", q.duplicates_removed > 0 ? "warning" : "good"),
          RP.kpi("Rows changed by checks", RP.fmtNum(issues, 0), "length, sum, sign, discount and stock-count checks", "list", issues > 0 ? "warning" : "good"),
          RP.kpi("Missing values", RP.fmtNum(totMiss, 0), `${RP.fmtNum(totImp, 0)} weather values imputed with the store median`, "half", totMiss > 0 ? "warning" : "good")].join("")}</div>
          <div class="grid g-5-7">${RP.card("Raw vs cleaned data", null, null, `<div id="me-dims"></div>` + RP.note("Rows are product-days for the selected store; both the training (90 days) and evaluation (7 days) splits are included."))}
            ${RP.card("Issues found and how they were treated", null, null, `<div id="me-issues"></div>`)}</div>
          <div class="grid g-6-6">${RP.card("Missing values before and after cleaning", null, null, `<div id="me-missing"></div>`)}
            ${RP.card("Before vs after: what estimating demand changes", "Daily totals per product-day on days with any trading-hour stockout", null, `<div id="me-ba" class="plot" style="height:280px"></div><div id="me-ba-note"></div>`)}</div>
          ${RP.card("Transformations and engineered features", "All lag and rolling features use only days before the day being described", null, `<div id="me-feat"></div>`)}`;
        const rp = q.raw_profile, rbs = rp.rows_by_split || {};
        simple(RP.$("#me-dims", b), [
          { i: "Rows (product-days)", r: RP.fmtNum(rp.rows, 0), c: RP.fmtNum(q.rows_clean, 0) }, { i: "Columns", r: rp.columns, c: "Daily table + 24-hour matrices" },
          { i: "Products", r: rp.products, c: q.products }, { i: "Date range", r: `${rp.date_min} to ${rp.date_max}`, c: `${q.date_min} to ${q.date_max}` },
          { i: "Training / evaluation rows", r: `${rbs.train} / ${rbs.eval}`, c: `${S.daily.filter((r) => r.split === "train").length} / ${S.daily.filter((r) => r.split === "eval").length}` }],
          [{ key: "i", label: "Item" }, { key: "r", label: "Raw" }, { key: "c", label: "Cleaned" }]);
        simple(RP.$("#me-issues", b), [
          ["Duplicate product-days", q.duplicates_removed, "Kept first occurrence"], ["Hourly lists not of length 24", q.hourly_wrong_length, "Row removed"],
          ["Hourly sum ≠ daily sale_amount (> 0.05)", q.hourly_daily_mismatch, "Daily total replaced by the hourly sum (hourly record treated as authoritative)"],
          ["Negative sales values", q.negative_sales_rows, "Set to 0"], ["Discount outside (0, 1]", q.discount_out_of_range, "Set to 1.0 (no discount)"],
          ["stock_hour6_22_cnt ≠ recount from hourly status", q.stock_count_mismatch, "Recomputed from hourly status (hours 06–21)"],
          ["Missing product-days in the calendar", q.missing_product_days, "Reported; series kept as observed"]].map(([a, n, t]) => ({ a, n, t })),
          [{ key: "a", label: "Check" }, { key: "n", label: "Found", num: true }, { key: "t", label: "Treatment" }]);
        simple(RP.$("#me-missing", b), Object.keys(mb).map((k) => ({ k, b: mb[k], a: k in imp ? 0 : mb[k], t: k in imp && mb[k] > 0 ? "Imputed with store median" : mb[k] > 0 ? "Row-level check" : "None needed" })),
          [{ key: "k", label: "Column" }, { key: "b", label: "Before", num: true }, { key: "a", label: "After", num: true }, { key: "t", label: "Treatment" }]);
        const so = S.daily.filter((r) => r.any_stockout === 1);
        RP.chHist(RP.$("#me-ba", b), so.map((r) => r.sale_amount), so.map((r) => r.latent));
        RP.$("#me-ba-note", b).innerHTML = RP.note(`On the ${so.length} product-days with any trading-hour stockout, the median daily total rises from ${RP.fmtNum(RP.median(so.map((r) => r.sale_amount)), 2)} (recorded) to ${RP.fmtNum(RP.median(so.map((r) => r.latent)), 2)} (estimated demand). ${so.filter((r) => r.latent_method === "profile").length} days used the profile method and ${so.filter((r) => r.latent_method === "fallback").length} the fallback level (in-stock share below ${Math.round(100 * m.thresholds.min_share_in)}%).`);
        simple(RP.$("#me-feat", b), R("feature_dictionary"), [{ key: "feature", label: "Feature" }, { key: "definition", label: "Definition" }, { key: "uses_future", label: "Uses future data?" }]);
      } else if (this.tab === "eda") {
        b.innerHTML = `<div class="grid g-6-6">${RP.card("When does the store sell?", "Mean recorded sales per in-stock product-hour, all products", null, `<div id="me-wdh" class="plot" style="height:300px"></div><div id="me-wdh-note"></div>`)}
          ${RP.card("How much do stockouts suppress recorded sales?", "Mean recorded sales per trading hour, in stock vs out of stock", null, `<div id="me-io" class="plot" style="height:300px"></div><div id="me-io-note"></div>`)}</div>
          ${RP.card("Which products are volatile, and which lose the most demand?", "Each dot is a product; size and colour = estimated unmet share", null, `<div id="me-var" class="plot" style="height:340px"></div><div id="me-var-note"></div>`)}`;
        const w = R("store_weekday_hour"); RP.chWeekdayHour(RP.$("#me-wdh", b), w);
        const byH = new Map(); for (const r of w) byH.set(r.hour, (byH.get(r.hour) || 0) + r.mean_sales);
        const top = [...byH.entries()].sort((x, y) => y[1] - x[1]);
        RP.$("#me-wdh-note", b).innerHTML = RP.note(`The two busiest hours across the store are ${RP.pad2(top[0][0])}:00 and ${RP.pad2(top[1][0])}:00. Night hours (00–05) show near-zero sales.`);
        const io = R("instock_vs_out").map((r) => ({ ...r, out: r.status === "Out of stock" ? 1 : 0 }));
        RP.chInOut(RP.$("#me-io", b), io);
        const wm = (s) => { const g = io.filter((r) => r.status === s); return RP.sum(g, (r) => r.mean_sales * r.hours) / Math.max(RP.sum(g, (r) => r.hours), 1e-9); };
        RP.$("#me-io-note", b).innerHTML = RP.note(`Recorded sales average ${RP.fmtNum(wm("In stock"), 3)} per in-stock trading hour and ${RP.fmtNum(wm("Out of stock"), 3)} per out-of-stock hour, so sales during stockouts are almost entirely missing. This is why recorded sales cannot be treated as demand.`);
        const v = R("variability"); RP.chVariability(RP.$("#me-var", b), v);
        RP.$("#me-var-note", b).innerHTML = RP.note(`Median coefficient of variation is ${RP.fmtNum(RP.median(v.map((r) => r.cv)), 2)}. ${v.filter((r) => r.unmet_share > 0.1).length} products lose more than 10% of estimated demand to stockouts.`);
      } else if (this.tab === "models") {
        b.innerHTML = `<h4 class="sec">1 · Stockout-aware demand estimation</h4><div class="grid g-4-4-4">${RP.card("Validation results", null, null, `<div id="me-lat"></div><div id="me-lat-note"></div>`)}
            ${RP.card("Error by simulated stockout start", null, null, `<div id="me-latcut" class="plot" style="height:260px"></div>`)}${RP.card("Estimated vs actual day totals", null, null, `<div id="me-latsc" class="plot" style="height:260px"></div>`)}</div>
          <h4 class="sec">2 · Demand forecasting</h4><div class="grid g-6-6">${RP.card("Forecast accuracy", null, null, `<div id="me-fc"></div><div id="me-fc-note"></div>`)}${RP.card("WAPE by model and window", null, null, `<div id="me-fcbars" class="plot" style="height:300px"></div>`)}</div>
          ${RP.card("Forecast vs actual in the evaluation week", `<select id="me-fcprod" class="inp" style="width:260px" aria-label="Product"></select>`, null, `<div id="me-avf" class="plot" style="height:280px"></div>` + RP.note("Hollow red markers are days with a stockout; they are excluded from scoring because recorded sales understate demand."))}
          <h4 class="sec">3 · Next-day stockout risk</h4><div class="grid g-7-5">${RP.card("Classification metrics", null, null, `<div id="me-risk"></div><div id="me-risk-note"></div>`)}${RP.card("Confusion matrix · evaluation week", null, null, `<div id="me-cm"></div>`)}</div>
          <div class="grid g-6-6">${RP.card("Are predicted probabilities trustworthy?", null, null, `<div id="me-cal" class="plot" style="height:280px"></div>`)}${RP.card("What drives the risk score?", null, null, `<div id="me-coef" class="plot" style="height:280px"></div>`)}</div>
          <h4 class="sec">4 · Anomaly detection and decision rules</h4>${RP.card("Rules", null, null, `<div class="rules" id="me-rules"></div>`)}`;
        const lv = RP.rows(S.raw.latent_val.metrics);
        simple(RP.$("#me-lat", b), lv.map((x) => ({ m: x.method === "profile_method" ? "Hourly-profile estimate" : "Observed sales only", mae: RP.fmtNum(x.MAE, 3), w: RP.fmtPct(x.WAPE, 1), bias: RP.fmtPct(x.bias, 1) })),
          [{ key: "m", label: "Method" }, { key: "mae", label: "MAE", num: true }, { key: "w", label: "WAPE", num: true }, { key: "bias", label: "Bias", num: true }]);
        RP.$("#me-lat-note", b).innerHTML = RP.note(`Validation on ${S.raw.latent_val.n} fully in-stock training days: trading hours from a random cut-off (12:00–20:00) were hidden as if out of stock, then the day total was estimated with a profile that excludes that day (leave-one-out).`);
        RP.chLatentCutoff(RP.$("#me-latcut", b), R("latent_validation_by_cutoff"));
        RP.chLatentScatter(RP.$("#me-latsc", b), R("latent_validation_rows"));
        const cv = R("forecast_cv_overall"), ev = R("forecast_eval_overall");
        simple(RP.$("#me-fc", b), [...cv.map((x) => ({ ...x, win: "CV (4 origins, training)" })), ...ev.map((x) => ({ ...x, win: "Hold-out (eval week)" }))].map((x) => ({
          win: x.win, mod: x[".model"] === "ets" ? "ETS" : "Seasonal naive", n: x.n_instock, mae: RP.fmtNum(x.MAE, 3), rmse: RP.fmtNum(x.RMSE, 3), w: RP.fmtPct(x.WAPE, 1), bias: RP.fmtPct(x.bias, 1), cov: RP.fmtPct(x.coverage80) })),
          [{ key: "win", label: "Window" }, { key: "mod", label: "Model" }, { key: "n", label: "In-stock days", num: true }, { key: "mae", label: "MAE", num: true }, { key: "rmse", label: "RMSE", num: true },
           { key: "w", label: "WAPE", num: true }, { key: "bias", label: "Bias", num: true }, { key: "cov", label: "80% coverage", num: true }]);
        const we = (mm) => (ev.find((x) => x[".model"] === mm) || {}).WAPE;
        RP.$("#me-fc-note", b).innerHTML = RP.note(`The model was chosen on training CV only (${m.chosen_model.toUpperCase()}). On the untouched evaluation week, ETS ${we("ets") < we("snaive") ? "beats" : "does not beat"} the seasonal-naive baseline (WAPE ${RP.fmtPct(we("ets"), 1)} vs ${RP.fmtPct(we("snaive"), 1)}). Scores use in-stock days only. These are high-demand days less often (busy days sell out), so a positive bias is expected; WAPE is unstable for products with many zero-sale days.`);
        RP.chModelBars(RP.$("#me-fcbars", b), cv, ev);
        const sel = RP.$("#me-fcprod", b); RP.options(sel, RP.productOptions(S), RP.st.product);
        const fe = R("forecast_eval"), avf = () => RP.chActualFc(RP.$("#me-avf", b), fe.filter((r) => r.product_id === Number(sel.value)));
        sel.addEventListener("change", avf); avf();
        const rk = R("risk_metrics"), nm = { logistic_validation: "Logistic · validation (threshold chosen here)", logistic_test: "Logistic · evaluation week", frequency_baseline_test: "Frequency baseline · evaluation week" };
        simple(RP.$("#me-risk", b), rk.map((x) => ({ s: nm[x.set] || x.set, n: x.n, er: RP.fmtPct(x.base_rate, 1), auc: RP.fmtNum(x.AUC, 3), br: RP.fmtNum(x.brier, 3), p: RP.fmtPct(x.precision), r: RP.fmtPct(x.recall), f1: RP.fmtNum(x.F1, 3) })),
          [{ key: "s", label: "Set" }, { key: "n", label: "n", num: true }, { key: "er", label: "Event rate", num: true }, { key: "auc", label: "AUC", num: true }, { key: "br", label: "Brier", num: true },
           { key: "p", label: "Precision", num: true }, { key: "r", label: "Recall", num: true }, { key: "f1", label: "F1", num: true }]);
        const rwin = m.risk_windows, cb = m.risk_class_balance;
        RP.$("#me-risk-note", b).innerHTML = RP.note(`Target: ${m.thresholds.risk_event_h ?? m.thresholds.risk_event_hours ?? 4}+ of 16 trading hours out of stock tomorrow. Fit ${rwin.fit[0]} to ${rwin.fit[1]}, validation ${rwin.validation[0]} to ${rwin.validation[1]}, test ${rwin.test[0]} to ${rwin.test[1]}. Event rate in the fit window: ${RP.fmtPct(cb.fit, 1)}, so accuracy alone would mislead; precision, recall and F1 are reported at threshold ${m.risk_threshold.toFixed(2)}.`);
        const t = rk.find((x) => x.set === "logistic_test");
        if (t) RP.$("#me-cm", b).innerHTML = `<div class="cm"><div></div><div class="h">Predicted: event</div><div class="h">Predicted: no event</div>
          <div class="h">Actual: event</div><div class="c ok"><strong>${t.TP}</strong><span>true positive</span></div><div class="c bad"><strong>${t.FN}</strong><span>missed</span></div>
          <div class="h">Actual: no event</div><div class="c bad"><strong>${t.FP}</strong><span>false alarm</span></div><div class="c ok"><strong>${t.TN}</strong><span>true negative</span></div></div>`;
        RP.chCalibration(RP.$("#me-cal", b), R("risk_calibration"));
        RP.chCoefs(RP.$("#me-coef", b), R("risk_coefficients"));
        const r = S.rules;
        RP.$("#me-rules", b).innerHTML = `<p><strong>Anomalies:</strong> robust z-score of recorded sales against the product's weekday-adjusted median of the previous ${m.thresholds.baseline_window} in-stock days (spread = 1.4826 × MAD, floored). Flag when |z| ≥ ${m.thresholds.anomaly_z.toFixed(1)} (current setting ${RP.st.zthr.toFixed(1)}). A flag is labelled Stockout, Promotion, Holiday, Possibly heavy rain or Unexplained, using the day's recorded flags. There is no ground truth, so detection accuracy is not claimed.</p>
          <p><strong>Decision rules (thresholds are design choices, not proven boundaries):</strong></p><ul>
          <li>R1 Consider replenishing earlier: ${r.stockout_days_thr}+ risk-event days in the last 7, or next-day risk ≥ model threshold and unmet share ≥ ${Math.round(100 * r.lost_share_thr)}%.</li>
          <li>R2 Investigate unexplained sales drop: an Unexplained drop anomaly in the last 7 days.</li>
          <li>R3 Review possible demand surge: forecast for the next 7 days ≥ ${Math.round(100 * r.surge_ratio)}% of the last 7 days' estimated demand, or an Unexplained surge.</li>
          <li>R4 Plan for lower demand: forecast ratio ≤ ${Math.round(100 * r.decline_ratio)}% and reliability not Low.</li>
          <li>R5 Use caution: reliability Low (CV WAPE > ${Math.round(100 * r.wape_low_reliability)}%, &lt; ${r.min_instock_days} fully in-stock days, or &gt; 50% zero-sale days).</li>
          <li>R6 Maintain current approach: no other rule fired.</li></ul>
          <p>Priority = urgency weight (High 3, Medium 2, Low 1, Info 0.5) × (1 + w₁·unmet share + w₂·risk + w₃·[recent unusual activity]).</p>
          <p class="sub">The rules run in your browser with the same logic as <code>R/decide.R</code>; an automated test checks that both give identical recommendations.</p>`;
      } else {
        b.innerHTML = `<div class="grid g-6-6">${RP.card("Dataset", null, "db", `<dl class="dl">
            <dt>Source</dt><dd><a href="https://huggingface.co/datasets/Dingdong-Inc/FreshRetailNet-50K" target="_blank" rel="noopener">FreshRetailNet-50K, Dingdong-Inc (Hugging Face)</a> · Wang et al. (2025), arXiv:2505.16319</dd>
            <dt>Licence</dt><dd>CC BY 4.0</dd><dt>Data used</dt><dd>${RP.esc(m.mode_note)}</dd><dt>Store analysed</dt><dd>Store ${m.store_id} · ${m.products} products</dd>
            <dt>Dates represented</dt><dd>Training ${m.train_range[0]} to ${m.train_range[1]} · evaluation ${m.eval_range[0]} to ${m.eval_range[1]}</dd>
            <dt>Granularity</dt><dd>Daily rows with 24 hourly sales values and 24 hourly stock-status flags</dd>
            <dt>Results generated</dt><dd>${RP.esc(m.generated_at)} (pipeline runtime ${Math.round(m.runtime_seconds)} s, ${RP.esc(m.r_version)})</dd>
            <dt>How it is built</dt><dd>All analysis runs in R (<code>pipeline/run_pipeline.R</code>); its results are exported to this static dashboard (<code>scripts/export_static.R</code>), which only re-runs the transparent rules in the browser.</dd></dl>`)}
          ${RP.card("Limitations", null, "info", `<ul class="rules">
            <li>Sales are globally normalised by an undisclosed factor, so every value is in normalised units: no money, kilograms or real quantities.</li>
            <li>There is no inventory, price, cost, lead-time or shelf-life field. No reorder quantities, dates or financial losses are produced.</li>
            <li>Hourly stock status = 1 is documented as out of stock. Overnight 1s may also mean closed or not stocked; only 06:00–21:59 is used for stockout analysis.</li>
            <li>Estimated demand assumes a stable hourly sales profile. Its error is measured by the hidden-hours validation, and it is always labelled as an estimate.</li>
            <li>90 training days: weekly patterns only, no yearly seasonality. Forecasts beyond 7 days were not evaluated.</li>
            <li>Stores belong to one large operator; results are a proxy for a small independent shop.</li>
            <li>Promotion effects are observational associations, not causal effects.</li>
            <li>The monitoring page replays historical data; it is not connected to a live feed.</li></ul>`)}</div>`;
      }
      window.dispatchEvent(new Event("resize"));
    },
  };
})();
