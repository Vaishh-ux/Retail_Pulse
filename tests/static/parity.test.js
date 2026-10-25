// Node check: the browser's rule engine (site/js/core.js) must reproduce R's recommendations.
//   node tests/static/parity.test.js
const fs = require("fs"), path = require("path"), vm = require("vm");
const root = path.resolve(__dirname, "../..");
const ctx = { window: {}, console, fetch: null, document: {}, URL, Blob: class {} };
vm.createContext(ctx);
vm.runInContext(fs.readFileSync(path.join(root, "site/js/core.js"), "utf8"), ctx);
const RP = ctx.window.RP;
let failures = 0;
const idx = JSON.parse(fs.readFileSync(path.join(root, "site/data/index.json"), "utf8"));
(async () => {
  for (const st of idx.stores) {
    const raw = fs.readFileSync(path.join(root, "site/data", st.file), "utf8");
    ctx.fetch = async () => ({ ok: true, json: async () => JSON.parse(raw) });
    const S = await RP.load(st.file);
    const js = RP.recs(S, S.zDefault);
    const r = RP.rows(S.raw.recommendations_r);
    const same = js.length === r.length && js.every((x, i) => x.product_id === r[i].product_id && x.action === r[i].action &&
      x.urgency === r[i].urgency && x.reliability === r[i].reliability && Math.abs(x.priority - r[i].priority) < 1e-6 && x.rule === r[i].rule);
    // anomalies at default threshold must match the count R reports in the manifest-era outputs
    const an = RP.classifyAnomalies(S, S.zDefault);
    const zr = S.daily.filter((x) => x.z != null && Math.abs(x.z) >= S.zDefault).length;
    console.log(`store ${st.store_id}: ${js.length} JS recs vs ${r.length} R recs -> ${same ? "identical" : "DIFFERENT"}; anomalies ${an.length} (expected ${S.raw.anomalies_n_r})`);
    if (an.length !== S.raw.anomalies_n_r) failures++;
    if (!same) {
      failures++;
      for (let i = 0; i < Math.max(js.length, r.length); i++) {
        const a = js[i] || {}, b = r[i] || {};
        if (a.product_id !== b.product_id || a.action !== b.action || a.rule !== b.rule || Math.abs((a.priority || 0) - (b.priority || 0)) > 1e-6) {
          console.log("  first difference at", i, { js: [a.product_id, a.action, a.urgency, a.priority, a.rule], r: [b.product_id, b.action, b.urgency, b.priority, b.rule] });
          break;
        }
      }
    }
    // growth scales the forecast ratio exactly
    const i1 = RP.indicators(S, an, 1), i2 = RP.indicators(S, an, 1.5);
    const ok = i1.every((x, k) => x.fc_ratio == null || Math.abs(i2[k].fc_ratio - 1.5 * x.fc_ratio) < 1e-9);
    if (!ok) { failures++; console.log("  growth scaling FAILED"); }
  }
  console.log(failures ? `FAILED (${failures})` : "parity OK");
  process.exit(failures ? 1 : 0);
})();
