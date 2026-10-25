/* Page 6 - Report and downloads. The R Markdown report is knitted in R (scripts/knit_reports.R)
   and shipped as a static file per store; CSV downloads reflect the current settings. */
"use strict";
(function () {
  const RP = window.RP;
  RP.pages.report = {
    render(host, S) {
      const m = S.m, rep = S.entry.report;
      const sec = (ic, t, s) => `<div class="report-sec">${RP.icon(ic)}<div><strong>${t}</strong><span>${s}</span></div></div>`;
      host.innerHTML = `<div class="hero"><div><div class="eyebrow">Report</div><h1>Store ${m.store_id} analysis report</h1>
          <p>${RP.esc(m.mode_note)} · ${m.products} products · ${m.date_min} to ${m.date_max} · results generated ${String(m.generated_at).slice(0, 10)}</p></div></div>
        <div class="grid g-7-5">
          ${RP.card("What the report contains", "R Markdown · ggplot2 figures · inline-computed text · R code folded", "book", `<div class="report-grid">
            ${sec("db", "Dataset and coverage", "Source, licence, store, date ranges, data-quality checks and cleaning")}
            ${sec("bulb", "Key business insights", "Unmet demand, stockout timing, weekday and hour patterns")}
            ${sec("alert", "Product-level risk", "Next-day stockout risk, products losing the most demand")}
            ${sec("line", "Forecast results", "ETS vs seasonal naive, rolling-origin CV and held-out week")}
            ${sec("target", "Evaluation metrics", "MAE, RMSE, WAPE, bias, coverage; AUC, F1, calibration")}
            ${sec("list", "Recommendations", "Rule-based actions with evidence and the rule that fired")}
            ${sec("info", "Limitations", "Normalised units, no inventory or cost data, observational effects")}</div>`)}
          ${RP.card("Download", "files reflect this store", "download", `${rep ? `<div class="btn-row">
              <a class="btn btn-primary" id="rep-open" href="${rep}" target="_blank" rel="noopener">${RP.icon("external")} Open full report</a>
              <a class="btn btn-gold" id="rep-dl" href="${rep}" download="retailpulse_store${m.store_id}_report.html">${RP.icon("download")} Download report (HTML)</a></div>`
              : `<div class="warn">The HTML report has not been knitted for this store. Run <code>Rscript scripts/knit_reports.R</code>, then <code>scripts/export_static.R</code>. The tables below can still be downloaded.</div>`}
            <p class="sub">To save as PDF, open the full report and use your browser's Print → Save as PDF.</p>
            <h6 class="side-h">Tables (CSV)</h6><div class="btn-row">
              <button class="btn btn-outline" data-dl="recs">${RP.icon("download")} Recommendations</button><button class="btn btn-outline" data-dl="risk">${RP.icon("download")} Product risk table</button>
              <button class="btn btn-outline" data-dl="alerts">${RP.icon("download")} Replay alerts</button><button class="btn btn-outline" data-dl="anoms">${RP.icon("download")} Anomalies</button>
              <button class="btn btn-outline" data-dl="metrics">${RP.icon("download")} Evaluation metrics</button></div><div id="rep-sum"></div>`)}
        </div>
        ${rep ? RP.card("Report preview", null, "eye", `<iframe class="report-frame" src="${rep}" title="RetailPulse report" loading="lazy"></iframe>`) : ""}`;
      RP.$$("[data-dl]", host).forEach((b) => b.addEventListener("click", () => this.dl(S, b.dataset.dl)));
      this.summary(host, S);
    },
    onShow(host, S) { this.summary(host, S); },
    summary(host, S) {
      const r = RP.recs(S, RP.st.zthr), lost = RP.sum(S.daily, (x) => x.lost), lat = RP.sum(S.daily, (x) => x.latent);
      RP.$("#rep-sum", host).innerHTML = RP.note(`Current data: ${S.m.products} products, ${RP.fmtNum(S.daily.length, 0)} product-days, estimated unmet demand ${RP.fmtPct(lost / lat, 1)}, ${new Set(r.filter((x) => x.urgency === "High" || x.urgency === "Medium").map((x) => x.product_id)).size} products with a High or Medium action, ${RP.classifyAnomalies(S, RP.st.zthr).length} anomalies at |z| ≥ ${RP.st.zthr.toFixed(1)}.`);
    },
    dl(S, what) {
      const sid = S.m.store_id, name = (x) => `retailpulse_store${sid}_${x}.csv`, z = RP.st.zthr;
      if (what === "recs") {
        const r = RP.recs(S, z).map((x) => ({ ...x, product: RP.plabel(x.product_id), type: x.recommendation_type }));
        RP.download(name("recommendations"), RP.csv(r, ["product", "action", "urgency", "reliability", "priority", "reason", "evidence", "if_ignored", "rule", "type"]));
      } else if (what === "risk") {
        const top = new Map(); for (const x of RP.recs(S, z)) if (!top.has(x.product_id)) top.set(x.product_id, x);
        const rows = S.products.map((p) => { const t = top.get(p.product_id) || {}; return { product: p.label, category: p.category, next_day_stockout_risk: p.risk, mean_estimated_demand: p.mean_latent,
          unmet_share: p.unmet_share, stockout_hour_rate: p.stockout_hour_rate, sellout_share: p.sellout_share, median_sellout_hour: p.median_sellout_hour,
          top_action: t.action, urgency: t.urgency, reliability: t.reliability, stockout_days_last7: t.stockout_days7, unmet_share_last7: t.lost_share7, forecast_ratio: t.fc_ratio }; })
          .sort((a, b) => (b.next_day_stockout_risk ?? -1) - (a.next_day_stockout_risk ?? -1));
        RP.download(name("product_risk"), RP.csv(rows, Object.keys(rows[0])));
      } else if (what === "alerts") {
        const rows = RP.rows(S.raw.alerts).map((a) => ({ timestamp: `${a.dt} ${RP.pad2(a.hour)}:00`, product: RP.plabel(a.product_id), severity: a.severity, type: a.type,
          observed: a.observed, expected: a.expected, message: a.message, note: "Historical replay of the evaluation week, not live data" }));
        RP.download(name("replay_alerts"), RP.csv(rows, Object.keys(rows[0])));
      } else if (what === "anoms") {
        const rows = RP.classifyAnomalies(S, z).map((a) => ({ date: a.dt, product: RP.plabel(a.product_id), direction: a.direction, cause: a.cause, z: a.z, observed: a.observed, expected: a.expected, threshold: z }));
        RP.download(name("anomalies"), RP.csv(rows, ["date", "product", "direction", "cause", "z", "observed", "expected", "threshold"]));
      } else if (what === "metrics") {
        const rows = [];
        for (const x of RP.rows(S.raw.latent_val.metrics)) rows.push({ task: "latent demand validation", window: "hidden-hours test", model: x.method, n: S.raw.latent_val.n, MAE: x.MAE, WAPE: x.WAPE, bias: x.bias });
        for (const [w, k] of [["rolling-origin CV", "forecast_cv_overall"], ["held-out eval week", "forecast_eval_overall"]])
          for (const x of RP.rows(S.raw[k])) rows.push({ task: "forecast", window: w, model: x[".model"], n: x.n_instock, MAE: x.MAE, RMSE: x.RMSE, WAPE: x.WAPE, bias: x.bias, coverage80: x.coverage80 });
        for (const x of RP.rows(S.raw.risk_metrics)) rows.push({ task: "stockout risk", window: x.set, model: /baseline/.test(x.set) ? "frequency baseline" : "logistic", n: x.n, AUC: x.AUC, F1: x.F1, precision: x.precision, recall: x.recall });
        RP.download(name("evaluation_metrics"), RP.csv(rows, ["task", "window", "model", "n", "MAE", "RMSE", "WAPE", "bias", "coverage80", "AUC", "F1", "precision", "recall"]));
      }
    },
  };
})();
