/* Page 4 - Forecasts and scenario analysis. Everything except the baseline forecast is HYPOTHETICAL. */
"use strict";
(function () {
  const RP = window.RP;
  const sc = { growth: 0, depth: 0, w_lost: 1, w_risk: 1, w_anomaly: 1 };

  RP.pages.scenario = {
    render(host, S) {
      host.innerHTML = `<div class="with-side"><aside class="side">
          <div class="field"><label for="sc-product">Product</label><select id="sc-product" class="inp"></select></div>
          ${RP.slider("sc-horizon", "Forecast horizon (days)", 1, 14, 1, RP.st.horizon)}
          <h6 class="side-h">Hypothetical assumptions</h6>
          ${RP.slider("sc-growth", "Demand change vs model forecast", -30, 50, 5, sc.growth, "%")}
          ${RP.slider("sc-depth", "Planned promotion depth (% off)", 0, 50, 5, sc.depth, "%")}
          <h6 class="side-h">Detection and prioritisation settings</h6>
          ${RP.slider("sc-zthr", "Anomaly threshold |z|", 2, 5, 0.5, RP.st.zthr)}
          ${RP.slider("sc-wlost", "Weight: unmet demand", 0, 3, 0.5, sc.w_lost)}
          ${RP.slider("sc-wrisk", "Weight: stockout risk", 0, 3, 0.5, sc.w_risk)}
          ${RP.slider("sc-wanom", "Weight: unusual activity", 0, 3, 0.5, sc.w_anomaly)}
          <button class="btn btn-outline" id="sc-reset" style="width:100%;justify-content:center">Reset to defaults</button>
        </aside><div>
          <div class="rp-banner scenario">${RP.icon("flask")}<div><strong>Hypothetical scenario.</strong> Assumption sliders change only this page. They do not predict what will happen; the promotion effect is an observational association, not a causal estimate. The anomaly threshold and the horizon are shared with the other pages.</div></div>
          ${RP.card("Scenario comparison", "Baseline (model, observed data) → hypothetical scenario", "compare", `<div id="sc-compare"></div>`)}<div style="height:1rem"></div>
          ${RP.card('<span id="sc-title"></span>', '<span id="sc-sub"></span>', null, `<div id="sc-plot" class="plot" style="height:360px"></div><div id="sc-fcnote"></div>`)}<div style="height:1rem"></div>
          <div class="grid g-6-6">
            ${RP.card("How does the threshold change what gets flagged?", "Number of anomaly flags (whole period) at each |z| threshold", null, `<div id="sc-thr" class="plot" style="height:260px"></div><div id="sc-thrnote"></div>`)}
            ${RP.card("How do the weights change the priority order?", "Top 12 products under your weights vs the default weights", null, `<div id="sc-rank"></div>` + RP.note("▲/▼ = places moved compared with the default weights (all 1). Urgency comes from the rules and is not changed by the weights; the weights only reorder products within the queue."))}
          </div></div></div>`;
      RP.options(RP.$("#sc-product", host), RP.productOptions(S), RP.st.product);
      RP.$("#sc-product", host).addEventListener("change", (e) => { RP.st.product = Number(e.target.value); RP.invalidate("scenario"); this.forecast(host, S); });
      RP.bindSlider(host, "sc-horizon", (v) => { RP.st.horizon = v; RP.invalidate("scenario"); this.forecast(host, S); });
      RP.bindSlider(host, "sc-growth", (v) => { sc.growth = v; this.forecast(host, S); }, 150);
      RP.bindSlider(host, "sc-depth", (v) => { sc.depth = v; this.forecast(host, S); }, 150);
      RP.bindSlider(host, "sc-zthr", (v) => { RP.st.zthr = v; RP.invalidate("scenario"); this.forecast(host, S); this.threshold(host, S); this.ranks(host, S); }, 150);
      for (const [id, k] of [["sc-wlost", "w_lost"], ["sc-wrisk", "w_risk"], ["sc-wanom", "w_anomaly"]]) RP.bindSlider(host, id, (v) => { sc[k] = v; this.ranks(host, S); }, 150);
      RP.$("#sc-reset", host).addEventListener("click", () => {
        Object.assign(sc, { growth: 0, depth: 0, w_lost: 1, w_risk: 1, w_anomaly: 1 }); RP.st.zthr = S.zDefault; RP.invalidate("scenario");
        for (const [id, v] of [["sc-growth", 0], ["sc-depth", 0], ["sc-zthr", S.zDefault], ["sc-wlost", 1], ["sc-wrisk", 1], ["sc-wanom", 1]]) RP.setSlider(host, id, v);
        this.all(host, S);
      });
      this.all(host, S);
    },
    onShow(host, S) { RP.$("#sc-product", host).value = RP.st.product; RP.setSlider(host, "sc-horizon", RP.st.horizon); RP.setSlider(host, "sc-zthr", RP.st.zthr); this.all(host, S); },
    all(host, S) { this.forecast(host, S); this.threshold(host, S); this.ranks(host, S); },

    mult(S) {
      const pid = RP.st.product, cat = (S.prod.get(pid) || {}).first_category_id;
      const e = RP.rows(S.raw.promo_effects).find((r) => r.first_category_id === cat);
      const g = 1 + sc.growth / 100, depth = sc.depth / 100;
      const usable = !(depth > 0 && (!e || e.beta == null));
      const pm = depth > 0 && usable ? RP.promoMultiplier(e.beta, e.se, depth) : { mid: 1, lo: 1, hi: 1 };
      return { g, pm, total: g * pm.mid, usable, e };
    },
    forecast(host, S) {
      const pid = RP.st.product, h = RP.st.horizon;
      const hist = (S.byProduct.get(pid) || []).filter((r) => r.d > S.lastDay - 28), f = (S.fcNext.get(pid) || []).slice(0, h);
      const m = this.mult(S);
      RP.$("#sc-title", host).textContent = `What demand can be expected for ${RP.plabel(pid)}?`;
      RP.$("#sc-sub", host).textContent = `Estimated demand, last 28 days · ${S.m.chosen_model.toUpperCase()} forecast for ${h} days · scenario in gold`;
      RP.chScenario(RP.$("#sc-plot", host), hist, f, m.total);
      if (!f.length) { RP.$("#sc-fcnote", host).innerHTML = ""; RP.$("#sc-compare", host).innerHTML = `<div class="empty">No forecast available for this product.</div>`; return; }
      const base = RP.sum(f, (r) => r.mean), parts = [`Model forecast: ${RP.fmtNum(base, 2)} units over ${f.length} days (80% daily intervals shown). `];
      if (Math.abs(m.total - 1) > 1e-9) parts.push(`Hypothetical scenario: ${RP.fmtNum(base * m.total, 2)} units (× ${m.total.toFixed(2)}). `);
      if (sc.depth > 0) parts.push(!m.usable ? "Too few past promotion days in this category to estimate a promotion association; the promotion slider has no effect here. "
        : `A ${sc.depth}% promotion was historically associated with demand × ${m.pm.mid.toFixed(2)} (95% CI ${m.pm.lo.toFixed(2)}–${m.pm.hi.toFixed(2)}) in this category, based on ${m.e.n_promo_days} promotion days. `);
      if (h > S.m.evaluated_horizon) parts.push(`Days beyond ${S.m.evaluated_horizon} were not evaluated.`);
      RP.$("#sc-fcnote", host).innerHTML = RP.note(parts.join(""));
      // comparison: baseline vs scenario, with the rules re-run
      const last7 = RP.sum((S.byProduct.get(pid) || []).filter((r) => r.d > S.lastDay - 7), (r) => r.latent);
      const f7 = RP.sum((S.fcNext.get(pid) || []).slice(0, 7), (r) => r.mean);
      const z = RP.st.zthr, g = 1 + sc.growth / 100;
      const b = RP.recs(S, z), scen = Math.abs(g - 1) < 1e-9 ? b : RP.recs(S, z, {}, g), prodScen = Math.abs(m.total - 1) < 1e-9 ? b : RP.recs(S, z, {}, m.total);
      const acts = (r) => { const a = r.filter((x) => x.product_id === pid).map((x) => x.action); return a.length ? a.join("; ") : "–"; };
      const cnt = (r, a) => new Set(r.filter((x) => x.action === a).map((x) => x.product_id)).size;
      const tile = (lbl, bv, sv, expl) => `<div class="${String(sv).length > 14 ? "text" : ""}"><div class="lbl">${lbl}</div><div class="vals"><span class="base">${RP.esc(bv)}</span><span class="arrow">→</span><span class="scen${String(bv) !== String(sv) ? " changed" : ""}">${RP.esc(sv)}</span></div><p class="expl">${expl}</p></div>`;
      RP.$("#sc-compare", host).innerHTML = `<div class="compare">
        ${tile(`${RP.plabel(pid)} demand, next ${f.length} days`, RP.fmtNum(base, 2), RP.fmtNum(base * m.total, 2), `80% interval (model): ${RP.fmtNum(RP.mean(f, (r) => r.lo80), 2)}–${RP.fmtNum(RP.mean(f, (r) => r.hi80), 2)} per day on average.`)}
        ${tile("Next 7 days vs last 7 days", RP.fmtPct(f7 / Math.max(last7, 1e-9)), RP.fmtPct(f7 * m.total / Math.max(last7, 1e-9)), `Rules flag a surge at ≥ ${RP.fmtPct(S.rules.surge_ratio)} and a decline at ≤ ${RP.fmtPct(S.rules.decline_ratio)}.`)}
        ${tile(`Recommendation for ${RP.plabel(pid)}`, acts(b), acts(prodScen), "Rules R3/R4 re-evaluated with the scenario forecast.")}
        ${tile("Store: products flagged for a possible surge", cnt(b, "Review possible demand surge"), cnt(scen, "Review possible demand surge"), `All products with demand change ${sc.growth >= 0 ? "+" : ""}${sc.growth}% (promotion depth is category-specific, so it is not applied store-wide).`)}
        ${tile("Store: products to plan for lower demand", cnt(b, "Plan for lower demand"), cnt(scen, "Plan for lower demand"), "Same store-wide demand change.")}</div>` +
        RP.note("Baseline values come from the model fitted on observed data. Scenario values are the baseline multiplied by your assumptions; they are what-if arithmetic, not forecasts of what will happen.");
    },
    threshold(host, S) {
      const zs = S.daily.filter((r) => r.z != null).map((r) => r.z), t = RP.st.zthr, n = zs.filter((z) => Math.abs(z) >= t).length;
      RP.chThreshold(RP.$("#sc-thr", host), zs, t);
      RP.$("#sc-thrnote", host).innerHTML = RP.note(`At |z| ≥ ${t.toFixed(1)}, ${n} of ${zs.length} scored product-days are flagged (${RP.fmtPct(n / zs.length, 1)}). Lower thresholds catch more real changes but also more noise. This setting applies across the app.`);
    },
    ranks(host, S) {
      const z = RP.st.zthr, top = (r) => { const seen = new Set(), out = []; for (const x of r) if (!seen.has(x.product_id)) { seen.add(x.product_id); out.push(x); } return out; };
      const a = top(RP.recs(S, z)), b = top(RP.recs(S, z, { w_lost: sc.w_lost, w_risk: sc.w_risk, w_anomaly: sc.w_anomaly }));
      const ra = new Map(a.map((x, i) => [x.product_id, i + 1]));
      const rows = b.slice(0, 12).map((x, i) => ({ rank: i + 1, product_id: x.product_id, action: x.action, priority: x.priority, change: ra.get(x.product_id) - (i + 1) }));
      RP.table(RP.$("#sc-rank", host), rows, [
        { key: "rank", label: "Rank", num: true, width: 56 }, { key: "product_id", label: "Product", width: 86, cls: "pid", render: (x) => RP.plabel(x.product_id) },
        { key: "action", label: "Action" }, { key: "priority", label: "Priority", num: true, render: (x) => x.priority.toFixed(2) },
        { key: "change", label: "Change", num: true, render: (x) => (x.change > 0 ? `<span class="up">▲ ${x.change}</span>` : x.change < 0 ? `<span class="down">▼ ${-x.change}</span>` : "–") },
      ], { pageSize: 12 });
    },
  };
})();
