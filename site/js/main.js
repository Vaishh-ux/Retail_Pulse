/* RetailPulse static dashboard - app shell: stores, routing, shared state. */
"use strict";
(function () {
  const RP = window.RP;
  RP.pages = RP.pages || {};
  // shared state across pages (same roles as the Shiny app's reactiveValues)
  RP.st = { product: null, date: null, zthr: 3, horizon: 7 };
  const dirty = new Set();
  let current = null, index = null;

  RP.invalidate = (except) => { for (const k of Object.keys(RP.pages)) if (k !== except) dirty.add(k); };
  RP.goto = (page, params = {}) => {
    if (params.product != null) RP.st.product = Number(params.product);
    if ("date" in params) RP.st.date = params.date;
    if (params.product != null || "date" in params) dirty.add(page);
    location.hash = page;
    if (current === page) show(page);
  };
  RP.labelOf = (pid) => (RP.S.prod.get(pid) || {}).label || "P" + pid;

  function show(page) {
    if (!RP.pages[page]) page = "overview";
    current = page;
    RP.$$(".rp-page").forEach((s) => (s.hidden = s.dataset.page !== page));
    RP.$$(".rp-links a").forEach((a) => a.classList.toggle("active", a.dataset.page === page));
    RP.$("#navlinks").classList.remove("open");
    const host = RP.$("#page-" + page);
    if (!host.dataset.built || dirty.has(page)) {
      dirty.delete(page);
      try { RP.pages[page].render(host, RP.S); host.dataset.built = "1"; }
      catch (e) { console.error(e); host.innerHTML = `<div class="warn">This page could not be drawn: ${RP.esc(e.message)}</div>`; }
    } else if (RP.pages[page].onShow) RP.pages[page].onShow(host, RP.S);
    window.dispatchEvent(new Event("resize"));   // let Plotly fit charts that were hidden
  }

  async function loadStore(sid) {
    const entry = index.stores.find((s) => String(s.store_id) === String(sid)) || index.stores[0];
    RP.$("#loading").hidden = false;
    RP.$$(".rp-page").forEach((s) => { s.hidden = true; s.dataset.built = ""; s.innerHTML = ""; });
    RP.S = await RP.load(entry.file);
    RP.S.entry = entry;
    const S = RP.S, m = S.m, synthetic = m.mode === "synthetic";
    RP.st.zthr = S.zDefault; RP.st.horizon = 7; RP.st.date = null;
    const firstRec = RP.recs(S, RP.st.zthr)[0];
    RP.st.product = firstRec ? firstRec.product_id : S.products[0].product_id;
    const pill = RP.$("#datapill");
    pill.className = "rp-data-pill" + (synthetic ? " synthetic" : "");
    pill.innerHTML = `<span class="dot"></span><span>${synthetic ? "Synthetic demo data" : "Real data · FreshRetailNet-50K"}</span>`;
    RP.$("#banner").innerHTML = synthetic ? `<div class="rp-banner demo">${RP.icon("alert")}<div><strong>Demo mode: synthetic data.</strong> Every number comes from a generated dataset with the FreshRetailNet-50K schema. They are not findings about real stores.</div></div>` : "";
    RP.$("#footer").textContent = `RetailPulse · Store ${m.store_id} · ${m.date_min} to ${m.date_max} · Analysis in R (pipeline/run_pipeline.R), dashboard in the browser · Data: FreshRetailNet-50K (Dingdong-Inc, CC BY 4.0) · CSI3005 Advanced Data Visualization Techniques${synthetic ? " · SYNTHETIC demo data" : ""}`;
    document.title = `RetailPulse · Store ${m.store_id}`;
    RP.$("#loading").hidden = true;
    RP.invalidate();
    show((location.hash || "#overview").slice(1).split("?")[0] || "overview");
  }

  async function boot() {
    RP.hydrateIcons();
    RP.$("#burger").addEventListener("click", () => { const n = RP.$("#navlinks"); n.classList.toggle("open"); RP.$("#burger").setAttribute("aria-expanded", n.classList.contains("open")); });
    try {
      const res = await fetch("data/index.json", { cache: "no-cache" });
      index = await res.json();
    } catch (e) {
      RP.$("#loading").innerHTML = `<div class="warn">Could not load data/index.json. Run <code>Rscript scripts/export_static.R</code> to generate the data files.</div>`;
      return;
    }
    const want = new URLSearchParams(location.search).get("store") || index.default;
    const sel = RP.$("#store");
    RP.options(sel, index.stores.map((s) => [s.store_id, "Store " + s.store_id]), want);
    sel.addEventListener("change", () => {
      const u = new URL(location.href); u.searchParams.set("store", sel.value); history.replaceState(null, "", u);
      loadStore(sel.value);
    });
    window.addEventListener("hashchange", () => RP.S && show(location.hash.slice(1) || "overview"));
    try { await loadStore(want); }
    catch (e) { console.error(e); RP.$("#loading").innerHTML = `<div class="warn">Could not load the store data: ${RP.esc(e.message)}</div>`; }
  }
  document.addEventListener("DOMContentLoaded", boot);
})();
