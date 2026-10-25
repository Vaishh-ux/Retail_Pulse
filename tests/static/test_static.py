"""Browser tests for the static RetailPulse dashboard (site/).
Serve it first, then:  cd site && python3 -m http.server 8080 &   RP_URL=http://127.0.0.1:8080 pytest tests/static -q
"""
import os, re
import pytest
from playwright.sync_api import sync_playwright, expect

URL = os.environ.get("RP_URL", "http://127.0.0.1:8080").rstrip("/") + "/"
IGNORED = ("ERR_TUNNEL_CONNECTION_FAILED", "fonts.g", "ERR_FAILED")


@pytest.fixture(scope="module")
def page():
    with sync_playwright() as p:
        b = p.chromium.launch()
        ctx = b.new_context(viewport={"width": 1440, "height": 900}, accept_downloads=True)
        pg = ctx.new_page()
        pg.route("**/fonts.g*/**", lambda r: r.abort())
        errors = []
        pg.on("pageerror", lambda e: errors.append(str(e)))
        pg.goto(URL)
        pg.wait_for_selector("#ov-kpis .kpi", timeout=30000)
        pg.errors = errors
        yield pg
        b.close()


def nav(pg, key):
    pg.evaluate(f"location.hash = '{key}'")
    pg.wait_for_timeout(1500)


def sel(pg, css, value):
    pg.select_option(css, str(value))
    pg.wait_for_timeout(700)


def kpi(pg, i):
    return pg.locator("#ov-kpis .kpi-value").nth(i).inner_text()


def test_overview_layout_and_real_data_label(page):
    expect(page.locator("#ov-kpis .kpi")).to_have_count(6)
    for t in ["Sales and estimated demand", "Priority stock alerts", "Recommended actions", "Quick insights",
              "Top products by estimated demand", "Category performance", "Demand heatmap"]:
        expect(page.get_by_role("heading", name=t)).to_be_visible()
    expect(page.locator("#datapill")).to_contain_text(re.compile("Real data|Synthetic demo"))
    assert page.locator("#ov-heat .main-svg").count() >= 1


def test_overview_matches_r_results(page):
    # the browser re-runs the rules; at default settings its counts must equal R's
    js = page.evaluate("""() => { const S = RP.S, r = RP.recs(S, S.zDefault), R = RP.rows(S.raw.recommendations_r);
        return { n: r.length, nr: R.length, same: r.every((x, i) => x.action === R[i].action && x.product_id === R[i].product_id && Math.abs(x.priority - R[i].priority) < 1e-6),
                 an: RP.classifyAnomalies(S, S.zDefault).length, anr: S.raw.anomalies_n_r }; }""")
    assert js["n"] == js["nr"] and js["same"]
    assert js["an"] == js["anr"]


def test_period_and_category_filters_update_kpis(page):
    v28 = kpi(page, 0)
    sel(page, "#ov-period", "7")
    v7 = kpi(page, 0)
    assert v7 != v28
    assert page.locator("#ov-from").input_value() != ""
    cat = page.locator("#ov-cat option").nth(1).get_attribute("value")
    sel(page, "#ov-cat", cat)
    assert kpi(page, 0) != v7
    sel(page, "#ov-cat", "")
    sel(page, "#ov-period", "28")
    assert kpi(page, 0) == v28


def test_action_tiles_filter_queue(page):
    tiles = page.locator("#ov-tiles .action")
    assert tiles.count() >= 2
    label = tiles.nth(1).locator(".action-l").inner_text()
    tiles.nth(1).click()
    page.wait_for_timeout(500)
    expect(page.locator("#ov-tiles .action.active")).to_contain_text(label)
    actions = page.locator("#ov-queue tbody tr td:nth-child(2)").all_inner_texts()
    assert actions and all(a.strip() == label for a in actions)
    page.locator("#ov-tiles .action").nth(0).click()


def test_queue_search_and_sort(page):
    q = page.locator("#ov-queue .tbl-q")
    q.fill("surge")
    page.wait_for_timeout(300)
    rows = page.locator("#ov-queue tbody tr").all_inner_texts()
    assert rows and all("surge" in r.lower() for r in rows)
    q.fill("")
    page.locator("#ov-queue th", has_text="Priority").click()
    page.wait_for_timeout(300)
    pr = [float(x) for x in page.locator("#ov-queue tbody tr td:nth-child(6)").all_inner_texts()]
    assert pr == sorted(pr, reverse=True)


def test_heatmap_modes(page):
    for mode in ["demand", "stockout", "z"]:
        sel(page, "#ov-heatmode", mode)
        assert page.locator("#ov-heat .main-svg").count() >= 1


def test_stock_alert_click_opens_product(page):
    btn = page.locator("#ov-alerts .alert").first
    pid = btn.locator(".alert-name").inner_text().split(" · ")[0]
    btn.click()
    page.wait_for_timeout(1500)
    expect(page.locator(".rp-links a[data-page='product']")).to_have_class(re.compile("active"))
    expect(page.locator(".prod-head h2")).to_have_text(pid)
    expect(page.locator(".mini-kpis .kpi")).to_have_count(5)


def test_queue_click_opens_product(page):
    nav(page, "overview")
    first = page.locator("#ov-queue tbody tr").first
    pid = first.locator("td").first.inner_text().strip()
    first.click()
    page.wait_for_timeout(1500)
    expect(page.locator(".prod-head h2")).to_have_text(pid)


def test_product_compare_horizon_and_search(page):
    n0 = page.evaluate("document.getElementById('pr-trend').data.length")
    other = page.locator("#pr-compare option").nth(3).get_attribute("value")
    sel(page, "#pr-compare", other)
    assert page.evaluate("document.getElementById('pr-trend').data.length") == n0 + 1
    sel(page, "#pr-compare", "")
    page.evaluate("const s = document.getElementById('pr-horizon'); s.value = 12; s.dispatchEvent(new Event('input'))")
    page.wait_for_timeout(400)
    expect(page.locator("#pr-hnote .warn")).to_contain_text("beyond the 7-day horizon")
    page.evaluate("const s = document.getElementById('pr-horizon'); s.value = 7; s.dispatchEvent(new Event('input'))")
    target = page.locator("#pr-product option").nth(2).inner_text()        # e.g. "P6 · Category 4"
    page.locator("#pr-search").fill(target)
    page.locator("#pr-search").dispatch_event("change")
    page.wait_for_timeout(800)
    assert page.locator(".prod-head h2").inner_text() == target.split(" · ")[0]


def test_heatmap_click_opens_product_and_date(page):
    nav(page, "overview")
    page.evaluate("""() => { const el = document.getElementById('ov-heat'), t = el.data[0];
        el.emit('plotly_click', { points: [{ x: t.x[5], y: t.y[3] }] }); }""")
    page.wait_for_timeout(1500)
    expect(page.locator(".rp-links a[data-page='product']")).to_have_class(re.compile("active"))
    assert re.match(r"\d{4}-\d{2}-\d{2}", page.locator("#pr-from").input_value())


def test_replay_play_pause_reset_jump(page):
    nav(page, "monitor")
    clock = page.locator("#mo-clock strong")
    t0 = clock.inner_text()
    assert "06:00" in t0
    expect(page.locator("#mo-clock")).to_contain_text("HISTORICAL REPLAY")
    page.locator("#mo-play").click()
    page.wait_for_timeout(3200)
    page.locator("#mo-pause").click()
    t1 = clock.inner_text()
    assert t1 != t0
    page.wait_for_timeout(1500)
    assert clock.inner_text() == t1
    page.locator("#mo-reset").click()
    assert clock.inner_text() == t0
    day = page.locator("#mo-day option").nth(3).get_attribute("value")
    sel(page, "#mo-day", day)
    assert "06:00" in clock.inner_text() and clock.inner_text() != t0
    expect(page.locator(".rp-banner.replay")).to_contain_text("not a live feed")


def test_alert_explorer_filters_and_detail(page):
    page.locator(".tabs button[data-tab='explorer']").click()
    page.wait_for_timeout(800)
    rows = page.locator("#mo-ex tbody tr")
    assert rows.count() > 0
    rows.first.click()
    expect(page.locator("#mo-detail")).to_contain_text("Detection method")
    sel(page, "#mo-fsev", "Critical")
    sev = page.locator("#mo-ex .badge").all_inner_texts()
    assert sev and all(s == "Critical" for s in sev)
    sel(page, "#mo-fsev", "")
    page.locator(".tabs button[data-tab='replay']").click()


def test_scenario_recalculates_and_threshold_shared(page):
    nav(page, "scenario")
    expect(page.locator(".rp-banner.scenario")).to_be_visible()
    base = page.locator("#sc-compare .compare > div").first.locator(".scen").inner_text()
    page.evaluate("const s = document.getElementById('sc-growth'); s.value = 40; s.dispatchEvent(new Event('input'))")
    page.wait_for_timeout(800)
    expect(page.locator("#sc-fcnote")).to_contain_text("Hypothetical scenario")
    scen = page.locator("#sc-compare .compare > div").first.locator(".scen").inner_text()
    assert float(scen.replace(",", "")) == pytest.approx(float(base.replace(",", "")) * 1.4, rel=0.01)
    assert page.evaluate("document.getElementById('sc-plot').data.length") == 5
    page.evaluate("const s = document.getElementById('sc-growth'); s.value = 0; s.dispatchEvent(new Event('input'))")
    page.evaluate("const s = document.getElementById('sc-zthr'); s.value = 4; s.dispatchEvent(new Event('input'))")
    page.wait_for_timeout(800)
    expect(page.locator("#sc-thrnote")).to_contain_text("|z| ≥ 4.0")
    nav(page, "overview")
    expect(page.locator("#ov-kpis .kpi").nth(4)).to_contain_text("|z| ≥ 4.0")
    nav(page, "scenario")
    page.locator("#sc-reset").click()
    page.wait_for_timeout(500)


def test_weights_reorder_queue(page):
    page.evaluate("const s = document.getElementById('sc-wrisk'); s.value = 3; s.dispatchEvent(new Event('input'))")
    page.wait_for_timeout(600)
    assert page.locator("#sc-rank tbody tr").count() == 12
    page.locator("#sc-reset").click()


def test_methods_tabs_render(page):
    nav(page, "methods")
    for tab in ["prep", "eda", "models", "data"]:
        page.locator(f".tabs button[data-tab='{tab}']").click()
        page.wait_for_timeout(1200)
        assert page.locator("#me-body .card").count() > 0
    page.locator(".tabs button[data-tab='models']").click()
    page.wait_for_timeout(1200)
    assert page.locator("#me-cm .c").count() == 4


def test_report_page_and_downloads(page):
    nav(page, "report")
    link = page.locator("#rep-open")
    if link.count():
        r = page.request.get(URL + link.get_attribute("href"))
        assert r.status == 200 and "RetailPulse" in r.text()
    for key, name in [("recs", "recommendations"), ("risk", "product_risk"), ("alerts", "replay_alerts"), ("anoms", "anomalies"), ("metrics", "evaluation_metrics")]:
        with page.expect_download() as d:
            page.locator(f"[data-dl='{key}']").click()
        assert name in d.value.suggested_filename
        with open(d.value.path(), encoding="utf-8") as f:
            assert len(f.read().strip().splitlines()) > 1


def test_store_switch(page):
    opts = page.locator("#store option")
    if opts.count() < 2:
        pytest.skip("only one store shipped")
    other = opts.nth(1).get_attribute("value")
    page.select_option("#store", other)
    page.wait_for_function(f"RP.S && String(RP.S.m.store_id) === '{other}'", timeout=30000)
    nav(page, "overview")
    expect(page.locator(".hero .eyebrow").first).to_contain_text(f"Store {other}")
    page.select_option("#store", opts.nth(0).get_attribute("value"))
    page.wait_for_timeout(2000)


def test_mobile_has_no_horizontal_scroll(page):
    page.set_viewport_size({"width": 390, "height": 844})
    page.wait_for_timeout(1500)
    over = page.evaluate("document.documentElement.scrollWidth - window.innerWidth")
    page.locator("#burger").click()
    expect(page.locator("#navlinks")).to_be_visible()
    page.locator("#burger").click()
    page.set_viewport_size({"width": 1440, "height": 900})
    assert over <= 2


def test_no_javascript_errors(page):
    assert [e for e in page.errors if not any(i in e for i in IGNORED)] == []
