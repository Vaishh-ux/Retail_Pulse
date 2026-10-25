"""Browser tests for the running RetailPulse app (Playwright + pytest).
Start the app first, then:  RP_URL=http://127.0.0.1:3838 pytest tests/ui -q
"""
import os, re
import pytest
from playwright.sync_api import sync_playwright, expect

URL = os.environ.get("RP_URL", "http://127.0.0.1:3838")
# Google Fonts may be unreachable in sandboxes; resource load failures are not app errors
IGNORED = ("ERR_TUNNEL_CONNECTION_FAILED", "fonts.g")


@pytest.fixture(scope="module")
def page():
    with sync_playwright() as p:
        b = p.chromium.launch()
        ctx = b.new_context(viewport={"width": 1440, "height": 900}, accept_downloads=True)
        pg = ctx.new_page()
        errors = []
        pg.on("pageerror", lambda e: errors.append(str(e)))
        pg.goto(URL, wait_until="networkidle")
        pg.wait_for_selector(".plotly", timeout=60000)
        pg.errors = errors
        yield pg
        b.close()


def nav(pg, key):
    pg.evaluate(f"document.querySelector(\"a.nav-link[data-value='{key}']\").click()")
    pg.wait_for_timeout(2500)


def shiny_errors(pg):
    return pg.locator(".shiny-output-error:visible").count()


def sel(pg, css, value):
    """Set a select input whether or not Shiny rendered it with selectize."""
    pg.evaluate(f"""() => {{ const el = document.querySelector('{css}');
        if (el.selectize) el.selectize.setValue('{value}');
        else {{ el.value = '{value}'; el.dispatchEvent(new Event('change', {{bubbles: true}})); }} }}""")


def options(pg, css):
    return pg.evaluate(f"""() => {{ const el = document.querySelector('{css}');
        return el.selectize ? Object.keys(el.selectize.options) : Array.from(el.options).map(o => o.value); }}""")


def kpi_value(pg, i):
    return pg.locator("#ov-kpis .rp-kpi-value").nth(i).inner_text()


def test_overview_layout_and_data_label(page):
    expect(page.locator("#ov-kpis .rp-kpi")).to_have_count(6)
    for t in ["Sales and estimated demand", "Priority stock alerts", "Recommended actions", "Quick insights",
              "Top products by estimated demand", "Category performance", "Demand heatmap"]:
        expect(page.get_by_text(t, exact=True).first).to_be_visible()
    page.wait_for_selector("#ov-heat .plot-container", timeout=30000)
    expect(page.locator(".rp-data-pill").first).to_contain_text(re.compile("Real data|Synthetic demo"))
    assert shiny_errors(page) == 0


def test_period_and_category_filters_update_kpis(page):
    v28 = kpi_value(page, 0)
    sel(page, "#ov-period", "7")
    page.wait_for_timeout(2500)
    v7 = kpi_value(page, 0)
    assert v7 != v28
    assert re.search(r"\d", page.locator("#ov-dates input").first.input_value())
    cat = [o for o in options(page, "#ov-cat") if o][0]
    sel(page, "#ov-cat", cat)
    page.wait_for_timeout(2500)
    assert kpi_value(page, 0) != v7
    sel(page, "#ov-cat", "")
    sel(page, "#ov-period", "28")
    page.wait_for_timeout(2500)
    assert kpi_value(page, 0) == v28


def test_action_tiles_filter_queue(page):
    tiles = page.locator("#ov-action_tiles .rp-action")
    assert tiles.count() >= 2
    label = tiles.nth(1).locator(".rp-action-l").inner_text()
    tiles.nth(1).click()
    page.wait_for_timeout(2000)
    expect(page.locator("#ov-action_tiles .rp-action.active")).to_contain_text(label)
    actions = page.locator("#ov-queue .rt-tbody .rt-tr .rt-td:nth-child(2)").all_inner_texts()
    assert actions and all(a.strip() == label for a in actions)
    tiles.nth(0).click()
    page.wait_for_timeout(1500)


def test_heatmap_modes_render(page):
    for mode in ["demand", "stockout", "z"]:
        sel(page, "#ov-heat_mode", mode)
        page.wait_for_timeout(2500)
        assert page.locator("#ov-heat .plot-container").count() == 1
        assert shiny_errors(page) == 0


def test_stock_alert_click_opens_product(page):
    btn = page.locator("#ov-alerts .rp-alert").first
    pid = btn.locator(".rp-alert-name").inner_text().split(" · ")[0]
    btn.click()
    page.wait_for_timeout(3000)
    expect(page.locator("a.nav-link[data-value='product']")).to_have_class(re.compile("active"))
    expect(page.locator(".rp-prod-head h2")).to_have_text(pid)
    nav(page, "overview")


def test_queue_click_opens_product_page(page):
    first = page.locator("#ov-queue .rt-tbody .rt-tr").first
    pid = first.locator(".rt-td").first.inner_text().strip()
    first.click()
    page.wait_for_timeout(3000)
    expect(page.locator("a.nav-link[data-value='product']")).to_have_class(re.compile("active"))
    expect(page.locator(".rp-prod-head h2")).to_have_text(pid)
    expect(page.locator(".rp-mini-kpis .rp-kpi")).to_have_count(5)
    assert shiny_errors(page) == 0


def test_product_compare_and_horizon(page):
    nav(page, "product")
    n0 = page.evaluate("document.getElementById('pr-trend').data.length")
    opts = page.evaluate("Object.keys(document.querySelector('#pr-compare').selectize.options)")
    pick = [o for o in opts if o][1]
    page.evaluate(f"document.querySelector('#pr-compare').selectize.setValue('{pick}')")
    page.wait_for_timeout(3000)
    n1 = page.evaluate("document.getElementById('pr-trend').data.length")
    assert n1 == n0 + 1                      # comparison line added
    page.evaluate("document.querySelector('#pr-compare').selectize.setValue('')")
    page.evaluate("Shiny.setInputValue('pr-horizon', 12)")
    page.wait_for_timeout(1500)
    expect(page.locator(".rp-warn")).to_contain_text("beyond the 7-day horizon")
    page.evaluate("Shiny.setInputValue('pr-horizon', 7)")


def test_heatmap_click_opens_product_and_date(page):
    nav(page, "overview")
    page.wait_for_selector("#ov-heat .plot-container", timeout=30000)
    page.wait_for_timeout(1500)
    page.evaluate("""() => {
        const el = document.getElementById('ov-heat');
        const t = el.data[0];
        el.emit('plotly_click', {points: [{curveNumber: 0, pointNumber: [3, 5], x: t.x[5], y: t.y[3], z: t.z[3][5]}]});
    }""")
    page.wait_for_timeout(3000)
    expect(page.locator("a.nav-link[data-value='product']")).to_have_class(re.compile("active"))
    start = page.locator("#pr-range input").first.input_value()
    assert re.match(r"\d{4}-\d{2}-\d{2}", start)


def test_replay_play_pause_reset_and_jump(page):
    nav(page, "monitor")
    clock = page.locator(".rp-clock strong")
    t0 = clock.inner_text()
    assert "06:00" in t0
    expect(page.locator(".rp-clock")).to_contain_text("HISTORICAL REPLAY")
    page.get_by_role("button", name="Play").click()
    page.wait_for_timeout(3500)
    page.get_by_role("button", name="Pause").click()
    t1 = clock.inner_text()
    assert t1 != t0
    page.wait_for_timeout(2000)
    assert clock.inner_text() == t1          # paused: time does not move
    page.get_by_role("button", name="Reset").click()
    page.wait_for_timeout(1500)
    assert "06:00" in clock.inner_text()
    day = [o for o in options(page, "#mo-jump_day") if o][3]
    sel(page, "#mo-jump_day", day)
    page.wait_for_timeout(2000)
    assert "06:00" in clock.inner_text() and clock.inner_text() != t0
    expect(page.locator(".rp-replay-banner")).to_contain_text("not a live feed")


def test_alert_explorer_filters_and_detail(page):
    page.get_by_role("tab", name="Alert explorer").click()
    page.wait_for_timeout(2500)
    rows = page.locator("#mo-explorer .rt-tbody .rt-tr")
    assert rows.count() > 0
    rows.first.click()
    page.wait_for_timeout(1500)
    expect(page.locator(".rp-detail")).to_contain_text("Detection method")
    page.evaluate("Shiny.setInputValue('mo-f_sev', ['Critical'])")
    page.wait_for_timeout(2000)
    sev = page.locator("#mo-explorer .rp-badge").all_inner_texts()
    assert sev and all(s == "Critical" for s in sev)
    page.evaluate("Shiny.setInputValue('mo-f_sev', [])")


def test_scenario_recalculates_and_threshold_is_shared(page):
    nav(page, "scenario")
    expect(page.locator(".rp-scenario-banner")).to_be_visible()
    base = page.locator("#sc-compare .rp-compare > div").first.locator(".scen").inner_text()
    page.evaluate("Shiny.setInputValue('sc-growth', 40)")
    page.wait_for_timeout(3500)
    expect(page.locator("#sc-fc_note")).to_contain_text("Hypothetical scenario")
    scen = page.locator("#sc-compare .rp-compare > div").first.locator(".scen").inner_text()
    assert float(scen.replace(",", "")) == pytest.approx(float(base.replace(",", "")) * 1.4, rel=0.01)
    n = page.evaluate("document.getElementById('sc-fc_plot').data.length")
    assert n >= 5                              # scenario line drawn
    page.evaluate("Shiny.setInputValue('sc-growth', 0)")
    page.evaluate("Shiny.setInputValue('sc-zthr', 4)")
    page.wait_for_timeout(2500)
    expect(page.locator("#sc-thr_note")).to_contain_text("|z| ≥ 4.0")
    nav(page, "overview")
    expect(page.locator("#ov-kpis .rp-kpi").nth(4)).to_contain_text("|z| ≥ 4.0")   # shared across pages


def test_methods_pages_render(page):
    nav(page, "methods")
    for tab in ["Data preparation", "Exploratory analysis", "Models and evaluation", "Dataset and limitations"]:
        page.get_by_role("tab", name=tab).click()
        page.wait_for_timeout(2000)
        assert shiny_errors(page) == 0, tab


def test_report_page_downloads(page):
    nav(page, "report")
    link = page.locator("a:has-text('Open full report')")
    if link.count():
        href = link.get_attribute("href")
        r = page.request.get(URL.rstrip("/") + "/" + href)
        assert r.status == 200 and "RetailPulse" in r.text()
        with page.expect_download() as d:
            page.locator("#rep-dl_report").click()
        assert d.value.suggested_filename.endswith(".html")
    for btn, name in [("#rep-dl_recs", "recommendations"), ("#rep-dl_risk", "product_risk"), ("#rep-dl_metrics", "evaluation_metrics")]:
        with page.expect_download() as d:
            page.locator(btn).click()
        path = d.value.path()
        assert name in d.value.suggested_filename
        with open(path, encoding="utf-8") as f:
            lines = f.read().strip().splitlines()
        assert len(lines) > 1


def test_store_switch_reloads_with_other_store(page):
    if page.locator("#store").count() == 0:
        pytest.skip("only one store shipped")
    other = options(page, "#store")[1]
    sel(page, "#store", other)
    page.wait_for_url(re.compile(rf"store={other}"), timeout=20000)
    page.wait_for_selector("#ov-kpis .rp-kpi", timeout=60000)
    expect(page.locator(".rp-hero .rp-eyebrow").first).to_contain_text(f"Store {other}")
    page.goto(URL, wait_until="networkidle")
    page.wait_for_selector("#ov-kpis .rp-kpi", timeout=60000)


def test_mobile_layout_has_no_horizontal_scroll(page):
    page.set_viewport_size({"width": 390, "height": 844})
    page.wait_for_timeout(2000)
    over = page.evaluate("document.documentElement.scrollWidth - window.innerWidth")
    page.set_viewport_size({"width": 1440, "height": 900})
    assert over <= 2


def test_no_javascript_errors(page):
    assert [e for e in page.errors if not any(i in e for i in IGNORED)] == []
