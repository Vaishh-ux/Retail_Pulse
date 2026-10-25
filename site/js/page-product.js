/* Page 2 - Product intelligence */
"use strict";
(function () {
  const RP = window.RP;
  const pr = { from: null, to: null, compare: "", showFc: true };

  RP.pages.product = {
    render(host, S) {
      const opts = RP.productOptions(S);
      host.innerHTML = `<div class="with-side"><aside class="side">
          <div class="field"><label for="pr-search">Find a product</label><input id="pr-search" class="inp" type="search" placeholder="Type a product ID, e.g. 108" list="pr-list" autocomplete="off">
            <datalist id="pr-list">${opts.map(([v, l]) => `<option value="${RP.esc(l)}"></option>`).join("")}</datalist></div>
          <div class="field"><label for="pr-product">Product</label><select id="pr-product" class="inp"></select></div>
          <div class="field"><label for="pr-compare">Compare with (optional)</label><select id="pr-compare" class="inp"></select></div>
          ${RP.slider("pr-horizon", "Forecast horizon (days)", 1, 14, 1, RP.st.horizon)}
          <div id="pr-hnote"></div>
          <label class="check"><input type="checkbox" id="pr-showfc" checked> Show forecast</label>
          <div class="field"><label>Date range</label><div class="daterange"><input type="date" id="pr-from" class="inp" aria-label="From"><span>to</span><input type="date" id="pr-to" class="inp" aria-label="To"></div></div>
          <div class="facts" id="pr-facts"></div>
        </aside><div>
          <div id="pr-head"></div>
          ${RP.card("Is demand really changing, or are stockouts hiding it?", "Recorded sales vs estimated demand · gold shading = promotion · red bars = out-of-stock hours · gold dotted = comparison product", null, `<div id="pr-trend" class="plot" style="height:440px"></div><div id="pr-trend-note"></div>`)}
          <div style="height:1rem"></div><div id="pr-recs"></div>
          <div class="grid g-6-6">
            ${RP.card("When do customers buy it?", "Mean recorded sales per in-stock hour, by weekday and hour", null, `<div id="pr-wdh" class="plot" style="height:300px"></div><div id="pr-wdh-note"></div>`)}
            ${RP.card("When does it usually run out?", "Kaplan–Meier: share of days still in stock at each hour", null, `<div id="pr-sell" class="plot" style="height:300px"></div><div id="pr-sell-note"></div>`)}
          </div>
          <div class="grid g-6-6">
            ${RP.card("Do sales differ when it is out of stock?", "Mean recorded sales per trading hour, in stock vs out of stock", null, `<div id="pr-inout" class="plot" style="height:280px"></div><div id="pr-inout-note"></div>`)}
            ${RP.card("How does it compare?", "This product vs its category median (and the comparison product)", null, `<div id="pr-cmp"></div><div id="pr-risk"></div>`)}
          </div></div></div>`;
      RP.options(RP.$("#pr-product", host), opts, RP.st.product);
      RP.options(RP.$("#pr-compare", host), [["", "None"], ...opts], pr.compare);
      const f = RP.$("#pr-from", host), t = RP.$("#pr-to", host);
      for (const el of [f, t]) { el.min = RP.iso(S.firstDay); el.max = RP.iso(S.lastDay); }
      RP.$("#pr-product", host).addEventListener("change", (e) => { RP.st.product = Number(e.target.value); RP.invalidate("product"); this.draw(host, S); });
      RP.$("#pr-search", host).addEventListener("change", (e) => {
        const q = e.target.value.trim().replace(/^P/i, "").split(/\s|·/)[0];
        const p = S.products.find((x) => String(x.product_id) === q || x.label.toLowerCase() === e.target.value.trim().toLowerCase().split(" ")[0]);
        if (p) { RP.st.product = p.product_id; RP.$("#pr-product", host).value = p.product_id; RP.invalidate("product"); this.draw(host, S); e.target.value = ""; }
      });
      RP.$("#pr-compare", host).addEventListener("change", (e) => { pr.compare = e.target.value; this.drawTrend(host, S); this.drawCompare(host, S); });
      RP.bindSlider(host, "pr-horizon", (v) => { RP.st.horizon = v; RP.invalidate("product"); this.drawTrend(host, S); this.hnote(host, S); });
      RP.$("#pr-showfc", host).addEventListener("change", (e) => { pr.showFc = e.target.checked; this.drawTrend(host, S); });
      const onD = () => { if (!f.value || !t.value) return; pr.from = RP.day(f.value); pr.to = RP.day(t.value); if (pr.from > pr.to) [pr.from, pr.to] = [pr.to, pr.from]; this.drawTrend(host, S); this.header(host, S); };
      f.addEventListener("change", onD); t.addEventListener("change", onD);
      this.draw(host, S);
    },
    onShow(host, S) { RP.$("#pr-product", host).value = RP.st.product; RP.setSlider(host, "pr-horizon", RP.st.horizon); this.draw(host, S); },

    draw(host, S) {
      if (RP.st.date) { const d = RP.day(RP.st.date); pr.from = Math.max(S.firstDay, d - 28); pr.to = Math.min(S.lastDay, d + 14); RP.st.date = null; }
      else if (pr.from == null) { pr.from = S.firstDay; pr.to = S.lastDay; }
      RP.$("#pr-from", host).value = RP.iso(pr.from); RP.$("#pr-to", host).value = RP.iso(pr.to);
      RP.$("#pr-product", host).value = RP.st.product;
      this.header(host, S); this.drawTrend(host, S); this.recs(host, S); this.hnote(host, S); this.facts(host, S);
      const pid = RP.st.product;
      const wdh = RP.rows(S.raw.weekday_hour).filter((r) => r.product_id === pid);
      RP.chWeekdayHour(RP.$("#pr-wdh", host), wdh);
      if (wdh.length) {
        const byH = new Map(), byD = new Map();
        for (const r of wdh) { (byH.get(r.hour) || byH.set(r.hour, []).get(r.hour)).push(r.mean_sales); (byD.get(r.weekday) || byD.set(r.weekday, []).get(r.weekday)).push(r.mean_sales); }
        const top = (m) => [...m.entries()].map(([k, v]) => [k, RP.mean(v)]).sort((a, b) => b[1] - a[1])[0][0];
        RP.$("#pr-wdh-note", host).innerHTML = RP.note(`Busiest hour on average: ${RP.pad2(top(byH))}:00. Busiest weekday: ${["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"][top(byD) - 1]}. Stockout hours are excluded, so these show demand while the product was available.`);
      } else RP.$("#pr-wdh-note", host).innerHTML = "";
      RP.chSellout(RP.$("#pr-sell", host), RP.rows(S.raw.sellout_curves).filter((r) => r.product_id === pid));
      const p = S.prod.get(pid);
      RP.$("#pr-sell-note", host).innerHTML = p ? RP.note(`It ran out during trading hours on ${p.sellout_days} of ${p.days} days (${RP.fmtPct(p.sellout_share)}). ${p.median_sellout_hour == null ? "On most days it never sold out." : `On half of all days it was out by ${RP.pad2(Math.round(p.median_sellout_hour))}:00.`} Probability of still being in stock at 18:00: ${RP.fmtPct(p.p_instock_18)}.`) : "";
      const io = RP.rows(S.raw.instock_out).filter((r) => r.product_id === pid);
      RP.chInOut(RP.$("#pr-inout", host), io);
      const hrs = this.hourSplit(S, pid);
      RP.$("#pr-inout-note", host).innerHTML = RP.note(`Recorded sales average ${RP.fmtNum(hrs[0], 3)} per in-stock hour and ${RP.fmtNum(hrs[1], 3)} per out-of-stock hour (mean of the hourly profile). Near-zero sales while out of stock are censored demand, not low demand.`);
      this.drawCompare(host, S); this.risk(host, S);
    },
    hourSplit(S, pid) {
      const io = RP.rows(S.raw.instock_out).filter((r) => r.product_id === pid);
      return [RP.mean(io.filter((r) => r.out === 0), (r) => r.mean_sales), RP.mean(io.filter((r) => r.out === 1), (r) => r.mean_sales)];
    },
    dp(S, pid = RP.st.product) { return (S.byProduct.get(pid) || []).filter((r) => r.d >= pr.from && r.d <= pr.to); },
    header(host, S) {
      const pid = RP.st.product, p = S.prod.get(pid); if (!p) return;
      const recs = RP.recs(S, RP.st.zthr).filter((r) => r.product_id === pid), rel = recs.length ? recs[0].reliability : "–";
      const rk = (S.riskNext.get(pid) || {}).risk, thr = S.m.risk_threshold, x = this.dp(S);
      const soDays = x.filter((r) => r.stock_h >= 4).length, unmet = RP.sum(x, (r) => r.lost) / Math.max(RP.sum(x, (r) => r.latent), 1e-9);
      RP.$("#pr-head", host).innerHTML = `<div class="prod-head"><div><h2>${RP.esc(p.label)}</h2><span class="sub">${RP.esc(p.category)} · encoded product ID ${pid} · the dataset does not include product names</span></div>
        <div class="chips">${RP.badge("Forecast reliability: " + rel, RP.relKind(rel))}${RP.badge("Next-day stockout risk: " + RP.fmtPct(rk), rk != null && rk >= thr ? "critical" : "neutral")}</div></div>
        <div class="mini-kpis">${[
          RP.kpi("Recorded sales", RP.fmtNum(RP.sum(x, (r) => r.sale_amount), 1), x.length ? `${RP.fmtDay(x[0].d, "d b")} – ${RP.fmtDay(x[x.length - 1].d, "d b")}` : "", "cart"),
          RP.kpi("Estimated demand", RP.fmtNum(RP.sum(x, (r) => r.latent), 1), "recorded + estimated lost sales", "chart"),
          RP.kpi("Unmet demand", RP.fmtPct(unmet, 1), "share of estimated demand", "box", RP.toneFor(unmet, 0.05, 0.15)),
          RP.kpi("Stockout days", `${soDays} / ${x.length}`, "days with 4+ trading hours out", "store", RP.toneFor(soDays / Math.max(x.length, 1), 0.15, 0.35)),
          RP.kpi("Next-day risk", RP.fmtPct(rk), `model threshold ${RP.fmtPct(thr)}`, "alert", rk == null ? "neutral" : rk >= thr ? "critical" : "good")].join("")}</div>`;
    },
    drawTrend(host, S) {
      const pid = RP.st.product, x = this.dp(S);
      const an = RP.classifyAnomalies(S, RP.st.zthr).filter((a) => a.product_id === pid && a.d >= pr.from && a.d <= pr.to);
      const atEnd = x.length && x[x.length - 1].d === S.lastDay;
      const fc = pr.showFc && atEnd ? (S.fcNext.get(pid) || []) : null;
      let cmp = null, cl = null;
      if (pr.compare && Number(pr.compare) !== pid) { cmp = this.dp(S, Number(pr.compare)); cl = RP.plabel(pr.compare); }
      RP.chTrend(RP.$("#pr-trend", host), x, an, fc, RP.st.horizon, cmp, cl);
      if (!x.length) { RP.$("#pr-trend-note", host).innerHTML = ""; return; }
      const lost = RP.sum(x, (r) => r.lost), tot = RP.sum(x, (r) => r.latent);
      RP.$("#pr-trend-note", host).innerHTML = RP.note(`In this range, ${RP.plabel(pid)} had 4+ stockout hours on ${x.filter((r) => r.stock_h >= 4).length} of ${x.length} days. Estimated unmet demand is ${RP.fmtNum(lost, 2)} units (${RP.fmtPct(lost / Math.max(tot, 1e-9), 1)} of estimated demand). ` +
        (fc ? `The dashed line is a ${S.m.chosen_model.toUpperCase()} forecast of estimated demand for the next ${RP.st.horizon} days, with its 80% interval.` : pr.showFc ? "Extend the date range to the last day to see the forecast." : ""));
    },
    hnote(host, S) {
      const h = RP.st.horizon, e = S.m.evaluated_horizon;
      RP.$("#pr-hnote", host).innerHTML = h > e ? `<div class="warn">Days ${e + 1}–${h} are beyond the ${e}-day horizon that was evaluated; treat them with extra caution.</div>` : "";
    },
    recs(host, S) {
      const r = RP.recs(S, RP.st.zthr).filter((x) => x.product_id === RP.st.product);
      RP.$("#pr-recs", host).innerHTML = r.length ? RP.card("Recommendations for this product", "Rule-based; no order quantities (the dataset has no inventory, lead time or cost data)", "list",
        `<div class="rec-grid">${r.map((x) => `<div class="rec ${RP.urgKind(x.urgency)}"><div class="rec-top"><strong>${RP.esc(x.action)}</strong>${RP.badge(x.urgency, RP.urgKind(x.urgency))}${RP.badge(x.recommendation_type, x.recommendation_type === "Data-supported" ? "info" : "neutral")}</div>
          <p>${RP.esc(x.reason)}</p><p class="ev"><strong>Evidence:</strong> ${RP.esc(x.evidence)}</p>${x.if_ignored ? `<p class="ev"><strong>If ignored:</strong> ${RP.esc(x.if_ignored)}</p>` : ""}
          <p class="rule">${RP.esc(x.rule)} · reliability: ${x.reliability}</p></div>`).join("")}</div>`) + '<div style="height:1rem"></div>' : "";
    },
    drawCompare(host, S) {
      const p = S.prod.get(RP.st.product); if (!p) return;
      const cat = S.products.filter((q) => q.first_category_id === p.first_category_id);
      const metric = (q) => [q.mean_latent, q.cv, q.unmet_share, q.stockout_hour_rate, q.sellout_share];
      const names = ["Mean estimated demand / day", "Variability (CV)", "Unmet demand share", "Stockout-hour rate", "Days with a sell-out"];
      const med = [0, 1, 2, 3, 4].map((i) => RP.median(cat.map((q) => metric(q)[i])));
      const cp = pr.compare ? S.prod.get(Number(pr.compare)) : null;
      const fm = (v, i) => (i < 2 ? RP.fmtNum(v, 2) : RP.fmtPct(v, 1));
      const rows = names.map((n, i) => ({ m: n, a: fm(metric(p)[i], i), b: fm(med[i], i), c: cp ? fm(metric(cp)[i], i) : "" }));
      const cols = [{ key: "m", label: "Metric", sortable: false }, { key: "a", label: p.label, sortable: false }, { key: "b", label: "Category median", sortable: false }];
      if (cp) cols.push({ key: "c", label: cp.label, sortable: false });
      RP.table(RP.$("#pr-cmp", host), rows, cols, { pageSize: 10 });
    },
    risk(host, S) {
      const rn = S.riskNext.get(RP.st.product), co = RP.rows(S.raw.risk_coefficients);
      if (!rn || !co.length) { RP.$("#pr-risk", host).innerHTML = ""; return; }
      const nice = { so_rate7: "recent stockout frequency", so_hours7: "recent stockout hours", yest_event: "a stockout yesterday", demand_ratio: "recent demand change", promo: "promotion", holiday_flag: "holiday", weekend: "weekend" };
      const c = co.filter((x) => x.term in rn).map((x) => [x.term, x.estimate * Number(rn[x.term])]).sort((a, b) => b[1] - a[1]).slice(0, 3);
      RP.$("#pr-risk", host).innerHTML = `<div class="riskbox"><strong>Why is next-day stockout risk ${RP.fmtPct(rn.risk)}?</strong><p>The largest upward contributions on the log-odds scale come from ${c.map((x) => nice[x[0]]).join(", ")}. Estimated for ${RP.fmtDay(RP.day(rn.next_dt), "a d b Y")}, assuming no promotion or holiday that day. This reflects historical sell-out patterns, not current stock on hand (the dataset has no inventory field).</p></div>`;
    },
    facts(host, S) {
      const pid = RP.st.product, p = S.prod.get(pid); if (!p) return;
      const ev = RP.rows(S.raw.forecast_eval_product).filter((r) => r.product_id === pid), w = (m) => (ev.find((r) => r[".model"] === m) || {}).WAPE;
      const spec = RP.rows(S.raw.ets_spec).find((r) => r.product_id === pid);
      RP.$("#pr-facts", host).innerHTML = [["Fully in-stock days", p.full_instock_days], ["Promotion days", p.promo_days], ["CV WAPE (chosen model)", RP.fmtPct(S.cvWape.get(pid), 1)],
        ["Hold-out WAPE ETS / naive", `${RP.fmtPct(w("ets"))} / ${RP.fmtPct(w("snaive"))}`], ["ETS form", spec ? spec.ets_form : "–"]].map(([a, b]) => `<div><span>${a}</span><strong>${b}</strong></div>`).join("");
    },
  };
})();
