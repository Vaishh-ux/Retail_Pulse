/* RetailPulse static dashboard - small UI building blocks (no framework). */
"use strict";
(function () {
  const RP = window.RP;
  const P = (d) => `<path d="${d}"/>`;
  const ICONS = {
    gauge: P("M12 14l4-4") + P("M3.3 19a10 10 0 1 1 17.4 0"),
    search: '<circle cx="11" cy="11" r="7"/>' + P("M20 20l-3.5-3.5"),
    clock: P("M3 12a9 9 0 1 0 3-6.7L3 8") + P("M3 3v5h5") + P("M12 7v5l3 2"),
    sliders: P("M4 6h10M18 6h2M4 12h4M12 12h8M4 18h12M20 18h0") + '<circle cx="16" cy="6" r="2"/><circle cx="10" cy="12" r="2"/><circle cx="18" cy="18" r="2"/>',
    flask: P("M9 3h6M10 3v6L4.5 19a1.5 1.5 0 0 0 1.3 2h12.4a1.5 1.5 0 0 0 1.3-2L14 9V3") + P("M7 15h10"),
    file: P("M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z") + P("M14 3v5h5M9 13h6M9 17h6"),
    cart: '<circle cx="9" cy="20" r="1.5"/><circle cx="18" cy="20" r="1.5"/>' + P("M2 3h3l2.6 12.2a2 2 0 0 0 2 1.6h7.7a2 2 0 0 0 2-1.5L21 8H6"),
    chart: P("M4 20V10M10 20V4M16 20v-7M22 20H2"),
    box: P("M21 8l-9-5-9 5 9 5 9-5z") + P("M3 8v8l9 5 9-5V8M12 13v8"),
    store: P("M3 9l1.5-5h15L21 9M4 9v11h16V9M3 9h18") + P("M4 4l16 16"),
    alert: P("M12 3l10 18H2L12 3z") + P("M12 10v5M12 18h0"),
    target: '<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="5"/><circle cx="12" cy="12" r="1"/>',
    line: P("M3 3v18h18") + P("M7 15l4-4 3 3 5-6"),
    bell: P("M6 8a6 6 0 1 1 12 0c0 7 3 9 3 9H3s3-2 3-9") + P("M10 21h4"),
    list: P("M9 6h12M9 12h12M9 18h12M4 6h0M4 12h0M4 18h0"),
    bulb: P("M9 18h6M10 22h4") + P("M12 2a7 7 0 0 0-4 12.7V17h8v-2.3A7 7 0 0 0 12 2z"),
    rank: P("M8 21V10M12 21V3M16 21v-7M4 21h16"),
    layers: P("M12 2l10 5-10 5L2 7l10-5z") + P("M2 12l10 5 10-5M2 17l10 5 10-5"),
    grid: '<rect x="3" y="3" width="7" height="7"/><rect x="14" y="3" width="7" height="7"/><rect x="3" y="14" width="7" height="7"/><rect x="14" y="14" width="7" height="7"/>',
    up: P("M3 17l6-6 4 4 8-8") + P("M15 7h6v6"), down: P("M3 7l6 6 4-4 8 8") + P("M15 17h6v-6"),
    truck: P("M3 6h11v10H3zM14 9h4l3 3v4h-7") + '<circle cx="7" cy="18" r="2"/><circle cx="17" cy="18" r="2"/>',
    help: '<circle cx="12" cy="12" r="9"/>' + P("M9.5 9a2.5 2.5 0 1 1 3.5 2.3c-.6.3-1 1-1 1.7v.5M12 17h0"),
    check: '<circle cx="12" cy="12" r="9"/>' + P("M8 12l3 3 5-6"),
    arrow: P("M5 12h14M13 6l6 6-6 6"),
    play: P("M7 4l13 8-13 8z"), pause: P("M7 4h3v16H7zM14 4h3v16h-3z"), reset: P("M3 12a9 9 0 1 0 3-6.7L3 8") + P("M3 3v5h5"),
    tag: P("M3 12V3h9l9 9-9 9-9-9z") + '<circle cx="7.5" cy="7.5" r="1.5"/>',
    db: '<ellipse cx="12" cy="5" rx="8" ry="3"/>' + P("M4 5v14c0 1.7 3.6 3 8 3s8-1.3 8-3V5M4 12c0 1.7 3.6 3 8 3s8-1.3 8-3"),
    download: P("M12 3v12M7 10l5 5 5-5M4 21h16"), external: P("M14 3h7v7M10 14L21 3M19 14v5a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2h5"),
    eye: P("M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12z") + '<circle cx="12" cy="12" r="3"/>',
    book: P("M4 4h6a2 2 0 0 1 2 2v14a2 2 0 0 0-2-2H4zM20 4h-6a2 2 0 0 0-2 2v14a2 2 0 0 1 2-2h6z"),
    info: '<circle cx="12" cy="12" r="9"/>' + P("M12 11v6M12 7h0"),
    compare: P("M7 4v16M17 4v16M3 8l4-4 4 4M13 16l4 4 4-4"),
    broom: P("M14 3l7 7M9 8l7 7-4 5-9-9 6-3z"), copy: '<rect x="8" y="8" width="13" height="13" rx="2"/>' + P("M4 16V4h12"),
    half: '<circle cx="12" cy="12" r="9"/>' + P("M12 3v18"),
  };
  RP.icon = (name) => `<svg class="ic" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${ICONS[name] || ""}</svg>`;
  RP.hydrateIcons = (root = document) => root.querySelectorAll("i.ic").forEach((i) => {
    const n = [...i.classList].find((c) => c.startsWith("ic-"));
    const map = { "ic-gauge": "gauge", "ic-search": "search", "ic-clock": "clock", "ic-sliders": "sliders", "ic-flask": "flask", "ic-file": "file" };
    i.outerHTML = RP.icon(map[n] || n.slice(3));
  });

  RP.badge = (text, kind = "neutral") => `<span class="badge b-${kind}">${RP.esc(text)}</span>`;
  RP.urgKind = (u) => ({ High: "critical", Medium: "warning", Low: "neutral", Info: "info" }[u] || "neutral");
  RP.relKind = (r) => ({ High: "good", Medium: "neutral", Low: "warning" }[r] || "neutral");
  RP.sevKind = (s) => ({ Critical: "critical", Warning: "warning", Info: "info", Anomaly: "anomaly" }[s] || "neutral");
  RP.toneFor = (x, warn, crit) => (x == null || Number.isNaN(x) ? "neutral" : x >= crit ? "critical" : x >= warn ? "warning" : "good");
  RP.kpi = (title, value, sub, icon, tone = "neutral", delta = null, deltaGood = null) => {
    let chip = "";
    if (delta != null && Number.isFinite(delta)) chip = `<span class="delta ${deltaGood ? "good" : "bad"}">${delta >= 0 ? "▲" : "▼"} ${RP.fmtPct(Math.abs(delta), 0)} vs previous period</span>`;
    return `<div class="kpi ${tone}"><div class="kpi-top"><span class="kpi-icon">${RP.icon(icon)}</span><span class="kpi-title">${RP.esc(title)}</span></div>
      <div class="kpi-value">${value}</div>${sub ? `<p class="kpi-sub">${sub}</p>` : ""}${chip}</div>`;
  };
  RP.card = (title, sub, icon, body, id) => `<div class="card"${id ? ` id="${id}"` : ""}><div class="card-h">${icon ? `<span class="ct-icon">${RP.icon(icon)}</span>` : ""}<h3>${title}</h3>${sub ? `<span class="sub">${sub}</span>` : ""}</div><div class="card-b">${body}</div></div>`;
  RP.note = (html) => `<p class="note">${html}</p>`;
  RP.$ = (sel, root = document) => root.querySelector(sel);
  RP.$$ = (sel, root = document) => [...root.querySelectorAll(sel)];
  RP.options = (sel, opts, value) => {
    sel.innerHTML = opts.map(([v, l]) => `<option value="${RP.esc(v)}"${String(v) === String(value) ? " selected" : ""}>${RP.esc(l)}</option>`).join("");
  };
  RP.productOptions = (S) => S.products.map((p) => [p.product_id, `${p.label} · ${p.category}`]);

  // Range slider with label: returns HTML; value shown in .range-val[data-for=id]
  RP.slider = (id, label, min, max, step, value, suffix = "") => `<div class="field"><label for="${id}">${label}</label>
    <div class="range-row"><span>${min}${suffix}</span><span class="range-val" data-for="${id}">${value}${suffix}</span><span>${max}${suffix}</span></div>
    <input type="range" class="range" id="${id}" min="${min}" max="${max}" step="${step}" value="${value}" data-suffix="${suffix}"></div>`;
  RP.bindSlider = (root, id, cb, debounceMs = 0) => {
    const el = RP.$("#" + id, root); const lab = RP.$(`.range-val[data-for="${id}"]`, root);
    let t = null;
    el.addEventListener("input", () => {
      lab.textContent = el.value + (el.dataset.suffix || "");
      if (debounceMs) { clearTimeout(t); t = setTimeout(() => cb(Number(el.value)), debounceMs); } else cb(Number(el.value));
    });
    return el;
  };
  RP.setSlider = (root, id, v) => { const el = RP.$("#" + id, root); el.value = v; const lab = RP.$(`.range-val[data-for="${id}"]`, root); if (lab) lab.textContent = v + (el.dataset.suffix || ""); };

  /* Sortable, searchable, paginated table.
     cols: [{key, label, num, width, sortable(default true), render(row) -> html, sortValue(row)}] */
  RP.table = (host, rows, cols, opts = {}) => {
    const st = { q: "", sort: opts.sort || null, dir: opts.dir || 1, page: 0, size: opts.pageSize || 10 };
    host.innerHTML = `${opts.search ? `<div class="tbl-tools"><input class="inp tbl-q" type="search" placeholder="${RP.esc(opts.placeholder || "Search…")}" aria-label="Search table"></div>` : ""}
      <div class="tbl-wrap"><table class="tbl"><thead></thead><tbody></tbody></table></div><div class="pager"></div>`;
    const thead = RP.$("thead", host), tbody = RP.$("tbody", host), pager = RP.$(".pager", host);
    if (!rows.length) { tbody.innerHTML = `<tr><td class="empty" colspan="${cols.length}">${opts.empty || "No rows."}</td></tr>`; pager.innerHTML = ""; return; }
    const text = (r) => cols.map((c) => String(r[c.key] ?? "")).join(" ").toLowerCase();
    const draw = () => {
      let v = st.q ? rows.filter((r) => text(r).includes(st.q)) : rows.slice();
      if (st.sort) {
        const c = cols.find((x) => x.key === st.sort); const f = c.sortValue || ((r) => r[c.key]);
        v.sort((a, b) => { const x = f(a), y = f(b); return (x > y ? 1 : x < y ? -1 : 0) * st.dir; });
      }
      const pages = Math.max(1, Math.ceil(v.length / st.size)); st.page = Math.min(st.page, pages - 1);
      thead.innerHTML = "<tr>" + cols.map((c) => `<th class="${c.num ? "num " : ""}${c.sortable === false ? "" : "sortable"}" data-k="${c.key}"${c.width ? ` style="width:${c.width}px"` : ""}>${RP.esc(c.label)}${st.sort === c.key ? `<span class="arr">${st.dir > 0 ? "▲" : "▼"}</span>` : ""}</th>`).join("") + "</tr>";
      const slice = v.slice(st.page * st.size, (st.page + 1) * st.size);
      tbody.innerHTML = slice.length ? slice.map((r, i) => `<tr class="${opts.onClick ? "click" : ""}" data-i="${rows.indexOf(r)}">` + cols.map((c) =>
        `<td class="${c.num ? "num " : ""}${c.cls || ""}">${c.render ? c.render(r) : RP.esc(r[c.key] ?? "")}</td>`).join("") + "</tr>").join("")
        : `<tr><td class="empty" colspan="${cols.length}">No rows match your search.</td></tr>`;
      const from = v.length ? st.page * st.size + 1 : 0, to = Math.min(v.length, (st.page + 1) * st.size);
      let btns = "";
      if (pages > 1) {
        const show = new Set([0, pages - 1, st.page - 1, st.page, st.page + 1].filter((x) => x >= 0 && x < pages));
        let prev = -1;
        for (const p of [...show].sort((a, b) => a - b)) { if (p - prev > 1) btns += "<span>…</span>"; btns += `<button data-p="${p}" class="${p === st.page ? "cur" : ""}">${p + 1}</button>`; prev = p; }
        btns = `<button data-p="${st.page - 1}" ${st.page === 0 ? "disabled" : ""}>Previous</button>${btns}<button data-p="${st.page + 1}" ${st.page >= pages - 1 ? "disabled" : ""}>Next</button>`;
      }
      pager.innerHTML = `<span>${from}–${to} of ${v.length} rows</span><span>${btns}</span>`;
    };
    thead.addEventListener("click", (e) => {
      const th = e.target.closest("th.sortable"); if (!th) return;
      const k = th.dataset.k; if (st.sort === k) st.dir = -st.dir; else { st.sort = k; st.dir = cols.find((c) => c.key === k).num ? -1 : 1; }
      draw();
    });
    pager.addEventListener("click", (e) => { const b = e.target.closest("button[data-p]"); if (b && !b.disabled) { st.page = Number(b.dataset.p); draw(); } });
    if (opts.search) RP.$(".tbl-q", host).addEventListener("input", (e) => { st.q = e.target.value.trim().toLowerCase(); st.page = 0; draw(); });
    if (opts.onClick) tbody.addEventListener("click", (e) => {
      const tr = e.target.closest("tr[data-i]"); if (!tr) return;
      RP.$$("tr.sel", tbody).forEach((x) => x.classList.remove("sel")); tr.classList.add("sel");
      opts.onClick(rows[Number(tr.dataset.i)]);
    });
    draw();
  };
})();
