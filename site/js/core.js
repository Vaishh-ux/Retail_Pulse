/* RetailPulse static dashboard - data access and analytics.
 * Everything modelled (latent demand, forecasts, risk, anomaly z-scores, replay) was
 * computed in R by pipeline/run_pipeline.R. This file only reproduces the cheap,
 * rule-based steps that react to the user's settings, using the same logic as R:
 *   R/anomaly.R  rp_classify_anomalies()   -> classifyAnomalies()
 *   R/decide.R   rp_product_indicators(), rp_reliability(), rp_recommend()
 *   R/scenario.R rp_promo_multiplier()
 */
"use strict";
const RP = (window.RP = window.RP || {});
RP.pages = RP.pages || {};

/* ---------- formatting ---------- */
RP.fmtNum = (x, d = 1) => (x == null || Number.isNaN(x) ? "–" :
  Number(x).toLocaleString("en-US", { minimumFractionDigits: d, maximumFractionDigits: d }));
RP.fmtPct = (x, d = 0) => (x == null || Number.isNaN(x) || !Number.isFinite(x) ? "–" : (100 * x).toFixed(d) + "%");
RP.plabel = (id) => "P" + id;
RP.esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
RP.pad2 = (n) => String(n).padStart(2, "0");

/* ---------- dates (day numbers, UTC) ---------- */
RP.day = (s) => Math.round(Date.parse(s + "T00:00:00Z") / 864e5);
RP.iso = (n) => new Date(n * 864e5).toISOString().slice(0, 10);
const WD = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const WDL = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
const MON = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
RP.fmtDay = (n, style = "d b") => {
  const d = new Date(n * 864e5);
  const dd = RP.pad2(d.getUTCDate()), b = MON[d.getUTCMonth()], y = d.getUTCFullYear(), a = WD[d.getUTCDay()];
  const tok = { A: WDL[d.getUTCDay()], a, d: dd, b, Y: y };
  return style.replace(/[AadbY]/g, (k) => tok[k]);
};

/* ---------- column tables -> rows ---------- */
RP.rows = (t) => {
  if (!t) return [];
  const keys = Object.keys(t);
  if (!keys.length) return [];
  const n = Array.isArray(t[keys[0]]) ? t[keys[0]].length : 1;
  const out = new Array(n);
  for (let i = 0; i < n; i++) {
    const r = {};
    for (const k of keys) r[k] = Array.isArray(t[k]) ? t[k][i] : t[k];
    out[i] = r;
  }
  return out;
};
RP.groupBy = (rows, key) => {
  const m = new Map();
  for (const r of rows) { const k = r[key]; if (!m.has(k)) m.set(k, []); m.get(k).push(r); }
  return m;
};
RP.sum = (a, f = (x) => x) => a.reduce((s, x) => s + (Number(f(x)) || 0), 0);
RP.mean = (a, f = (x) => x) => (a.length ? RP.sum(a, f) / a.length : NaN);
RP.median = (arr) => {
  const a = arr.filter((x) => x != null && !Number.isNaN(x)).sort((x, y) => x - y);
  if (!a.length) return NaN;
  const m = Math.floor(a.length / 2);
  return a.length % 2 ? a[m] : (a[m - 1] + a[m]) / 2;
};
RP.round = (x, d) => { const p = Math.pow(10, d); return Math.round((x + Number.EPSILON) * p) / p; };

/* ---------- load a store ---------- */
RP.load = async (file) => {
  const res = await fetch("data/" + file, { cache: "force-cache" });
  if (!res.ok) throw new Error("Could not load " + file + " (" + res.status + ")");
  const D = await res.json();
  const S = { raw: D, m: D.manifest, q: D.quality };
  S.daily = RP.rows(D.daily);
  for (const r of S.daily) { r.d = RP.day(r.dt); if (r.z != null) r.z = Number(r.z); }
  S.products = RP.rows(D.products).sort((a, b) => a.product_id - b.product_id);
  S.prod = new Map(S.products.map((p) => [p.product_id, p]));
  S.byProduct = RP.groupBy(S.daily, "product_id");
  S.lastDay = Math.max(...S.daily.map((r) => r.d));
  S.firstDay = Math.min(...S.daily.map((r) => r.d));
  S.fcNext = RP.groupBy(RP.rows(D.forecast_next).map((r) => ({ ...r, d: RP.day(r.dt) })).sort((a, b) => a.d - b.d), "product_id");
  S.riskNext = new Map(RP.rows(D.risk_next).map((r) => [r.product_id, r]));
  const cvp = RP.rows(D.forecast_cv_product).filter((r) => r[".model"] === S.m.chosen_model);
  S.cvWape = new Map(cvp.map((r) => [r.product_id, r.WAPE]));
  S.categories = [...new Set(S.products.map((p) => p.first_category_id))].sort((a, b) => a - b);
  S.rainQ = D.rain_q;
  S.rules = D.rules;
  S.zDefault = S.m.thresholds.anomaly_z;
  S.cache = new Map();
  return S;
};

/* ---------- anomalies (port of rp_classify_anomalies) ---------- */
RP.classifyAnomalies = (S, zthr) => {
  const key = "an" + zthr;
  if (S.cache.has(key)) return S.cache.get(key);
  const out = [];
  for (const r of S.daily) {
    if (r.z == null || Math.abs(r.z) < zthr) continue;
    const dir = r.z > 0 ? "surge" : "drop";
    const stockExpl = r.stock_h >= 4 || r.stockout_day === 1;
    let cause;
    if (dir === "drop" && stockExpl) cause = "Stockout (supply-side)";
    else if (dir === "surge" && r.promo === 1) cause = "Promotion";
    else if (r.holiday_flag === 1) cause = "Holiday";
    else if (dir === "drop" && r.precpt >= S.rainQ) cause = "Possibly heavy rain";
    else cause = "Unexplained";
    const expl = {
      "Stockout (supply-side)": `Out of stock for ${r.stock_h} of 16 trading hours; recorded sales understate demand.`,
      Promotion: `Promotion active (discount ${Math.round(100 * r.promo_depth)}% off). Higher sales are expected.`,
      Holiday: "Holiday flag set on this day; demand often shifts on holidays.",
      "Possibly heavy rain": `Precipitation ${RP.fmtNum(r.precpt, 1)} is in the top 10% of days; a weather effect is possible but not confirmed.`,
      Unexplained: "No stockout, promotion, holiday or heavy rain recorded. Cause unknown; worth checking (quality, pricing, display).",
    }[cause];
    out.push({ product_id: r.product_id, dt: r.dt, d: r.d, direction: dir, observed: RP.round(r.sale_amount, 3),
      expected: RP.round(r.reference, 3), deviation: RP.round(r.sale_amount - r.reference, 3), z: RP.round(r.z, 2),
      cause, explanation: expl, method: `Robust z vs weekday-adjusted 28-day in-stock median; |z| >= ${zthr.toFixed(1)}` });
  }
  S.cache.set(key, out);
  return out;
};

/* ---------- indicators and rules (port of R/decide.R) ---------- */
RP.indicators = (S, anoms, growth = 1) => {
  const last = S.lastDay, rows = [];
  const anBy = RP.groupBy(anoms.filter((a) => a.d > last - 7), "product_id");
  for (const [pid, ds] of [...S.byProduct.entries()].sort((a, b) => a[0] - b[0])) {
    const rec = ds.filter((r) => r.d > last - 7);
    if (!rec.length) continue;
    const obs7 = RP.sum(rec, (r) => r.sale_amount), latent7 = RP.sum(rec, (r) => r.latent);
    const stockout_days7 = RP.sum(rec, (r) => r.event);
    const fc = (S.fcNext.get(pid) || []).slice(0, 7);
    const fc7 = fc.length ? RP.sum(fc, (r) => r.mean) * growth : null;
    const a = anBy.get(pid) || [];
    const p = S.prod.get(pid) || {};
    const rn = S.riskNext.get(pid);
    rows.push({ product_id: pid, obs7, latent7, stockout_days7, lost_share7: latent7 > 0 ? (latent7 - obs7) / latent7 : 0,
      fc7, unexplained_drops7: a.filter((x) => x.cause === "Unexplained" && x.direction === "drop").length,
      unexplained_surges7: a.filter((x) => x.cause === "Unexplained" && x.direction === "surge").length,
      risk: rn ? rn.risk : null, cv_wape: S.cvWape.has(pid) ? S.cvWape.get(pid) : null,
      full_instock_days: p.full_instock_days, zero_sale_share: p.zero_sale_share,
      fc_ratio: latent7 > 0 && fc7 != null ? fc7 / latent7 : null });
  }
  return rows;
};

RP.reliability = (r, p) => {
  if (r.cv_wape == null || r.full_instock_days < p.min_instock_days || r.zero_sale_share > 0.5) return "Low";
  if (r.cv_wape > p.wape_low_reliability) return "Low";
  if (r.cv_wape > 0.3) return "Medium";
  return "High";
};
const fmtR = (x, d) => (x == null ? "NA" : Number(x).toFixed(d));

RP.recommend = (S, ind, params = {}) => {
  const p = { ...S.rules, ...params };
  if (typeof p.risk_thr !== "number") p.risk_thr = S.m.risk_threshold;   // R's NULL arrives as {}
  const recs = [];
  for (const r0 of ind) {
    const r = { ...r0, reliability: RP.reliability(r0, p) };
    let fired = false;
    const add = (action, reason, evidence, urgency, rule) => recs.push({ ...r, action, reason, evidence, urgency, rule });
    if (r.stockout_days7 >= p.stockout_days_thr || (r.risk != null && r.risk >= p.risk_thr && r.lost_share7 >= p.lost_share_thr)) {
      const urg = r.lost_share7 >= 0.2 || r.stockout_days7 >= 4 ? "High" : "Medium";
      add("Consider replenishing earlier",
        `Out of stock for 4+ trading hours on ${r.stockout_days7} of the last 7 days; about ${Math.round(100 * r.lost_share7)}% of estimated demand went unmet.`,
        `Stockout days (7d) = ${r.stockout_days7}; unmet share = ${(100 * r.lost_share7).toFixed(1)}%; next-day stockout risk = ${r.risk == null ? "n/a" : Math.round(100 * r.risk) + "%"}`,
        urg, `R1: stockout days >= ${p.stockout_days_thr} OR (risk >= ${p.risk_thr.toFixed(2)} AND unmet share >= ${Math.round(100 * p.lost_share_thr)}%)`);
      fired = true;
    }
    if (r.unexplained_drops7 > 0) {
      add("Investigate unexplained sales drop",
        "Sales fell far below this product's normal level with no stockout, promotion, holiday or heavy rain recorded.",
        `${r.unexplained_drops7} unexplained drop(s) in the last 7 days (robust z <= -threshold)`, "Medium", "R2: unexplained drop anomaly in the last 7 days");
      fired = true;
    }
    const byFc = r.fc_ratio != null && r.fc_ratio >= p.surge_ratio;
    if (byFc || r.unexplained_surges7 > 0) {
      const why = [];
      if (byFc) why.push(`Forecast for the next 7 days is ${Math.round(100 * r.fc_ratio)}% of estimated demand in the last 7 days.`);
      if (r.unexplained_surges7 > 0) why.push(`Sales were far above normal on ${r.unexplained_surges7} recent day(s) with no promotion or holiday recorded.`);
      add("Review possible demand surge", why.join(" "), `Forecast ratio = ${fmtR(r.fc_ratio, 2)}; unexplained surges (7d) = ${r.unexplained_surges7}`,
        r.reliability === "Low" ? "Low" : "Medium", `R3: forecast ratio >= ${p.surge_ratio.toFixed(2)} OR unexplained surge`);
      fired = true;
    }
    if (r.fc_ratio != null && r.fc_ratio <= p.decline_ratio && r.reliability !== "Low") {
      add("Plan for lower demand", `Forecast for the next 7 days is ${Math.round(100 * r.fc_ratio)}% of estimated demand in the last 7 days.`,
        `Forecast ratio = ${fmtR(r.fc_ratio, 2)} (reliability ${r.reliability})`, "Low", `R4: forecast ratio <= ${p.decline_ratio.toFixed(2)} and reliability not Low`);
      fired = true;
    }
    if (r.reliability === "Low") {
      add("Use caution: forecast unreliable", "Too little in-stock history or high past forecast error; rely on judgement for this product.",
        `CV WAPE = ${r.cv_wape == null ? "n/a" : r.cv_wape.toFixed(2)}; in-stock days = ${r.full_instock_days}; zero-sale share = ${Math.round(100 * r.zero_sale_share)}%`,
        "Info", "R5: reliability = Low");
      fired = true;
    }
    if (!fired) add("Maintain current approach", "No rule triggered; demand and availability are within normal ranges.",
      `Unmet share = ${(100 * r.lost_share7).toFixed(1)}%; forecast ratio = ${r.fc_ratio == null ? "n/a" : r.fc_ratio.toFixed(2)}`, "Low", "R6: no other rule fired");
  }
  const urgW = { High: 3, Medium: 2, Low: 1, Info: 0.5 };
  for (const x of recs) {
    x.priority = RP.round(urgW[x.urgency] * (1 + p.w_lost * x.lost_share7 + p.w_risk * (x.risk ?? 0) +
      p.w_anomaly * Math.min(1, x.unexplained_drops7 + x.unexplained_surges7)), 3);
    x.if_ignored = x.action === "Consider replenishing earlier" ? `At the recent rate, about ${Math.round(100 * x.lost_share7)}% of this product's demand may keep going unmet.`
      : x.action === "Investigate unexplained sales drop" ? "If the cause is a quality, price or display problem, it may persist unnoticed."
      : x.action === "Review possible demand surge" ? "If the rise is real, stock may run out sooner than usual." : "";
    x.recommendation_type = /^R[56]/.test(x.rule) ? "General operational suggestion" : "Data-supported";
  }
  return recs.map((x, i) => [x, i]).sort((a, b) => b[0].priority - a[0].priority || a[1] - b[1]).map((x) => x[0]);
};

RP.recs = (S, zthr, params = {}, growth = 1) => {
  const key = "rec|" + zthr + "|" + growth + "|" + JSON.stringify(params);
  if (S.cache.has(key)) return S.cache.get(key);
  const v = RP.recommend(S, RP.indicators(S, RP.classifyAnomalies(S, zthr), growth), params);
  if (S.cache.size > 60) S.cache.clear();
  S.cache.set(key, v);
  return v;
};

RP.promoMultiplier = (beta, se, depth) => ({ mid: Math.exp(beta * depth), lo: Math.exp((beta - 1.96 * se) * depth), hi: Math.exp((beta + 1.96 * se) * depth) });

/* ---------- CSV ---------- */
RP.csv = (rows, cols) => {
  const q = (v) => { const s = v == null ? "" : String(v); return /[",\n]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s; };
  return [cols.join(","), ...rows.map((r) => cols.map((c) => q(r[c])).join(","))].join("\n");
};
RP.download = (name, text, type = "text/csv") => {
  const a = document.createElement("a");
  a.href = URL.createObjectURL(new Blob([text], { type: type + ";charset=utf-8" }));
  a.download = name; document.body.appendChild(a); a.click();
  setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 500);
};
