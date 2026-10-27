"""Browser tests for the running RetailPulse Shiny app (Playwright + pytest), three-page version.
Start the app first, then:  RP_URL=http://127.0.0.1:3838 pytest tests/ui -q
"""
import os, re
import pytest
from playwright.sync_api import sync_playwright, expect

URL = os.environ.get("RP_URL", "http://127.0.0.1:3838")
IGNORED = ("ERR_TUNNEL_CONNECTION_FAILED", "fonts.g")


@pytest.fixture(scope="module")
def page():
    with sync_playwright() as p:
        b = p.chromium.launch()
        ctx = b.new_context(viewport={"width": 1440, "height": 900}, accept_downloads=True)
        pg = ctx.new_page()
        pg.route("**/fonts.g*/**", lambda r: r.abort())
        errors = []
        pg.on("pageerror", lambda e: errors.append(str(e)))
        pg.goto(URL, wait_until="networkidle")
        pg.wait_for_selector("#db-kpis .rp-kpi", timeout=60000)
        pg.errors = errors
        yield pg
        b.close()


def nav(pg, key):
    pg.evaluate(f"document.querySelector(\"a.nav-link[data-value='{key}']\").click()")
    pg.wait_for_timeout(2500)


def sel(pg, css, value):
    pg.evaluate(f"""() => {{ const el = document.querySelector('{css}');
        if (el.selectize) el.selectize.setValue('{value}');
        else {{ el.value = '{value}'; el.dispatchEvent(new Event('change', {{bubbles: true}})); }} }}""")
    pg.wait_for_timeout(2000)


def options(pg, css):
    return pg.evaluate(f"""() => {{ const el = document.querySelector('{css}');
        return el.selectize ? Object.keys(el.selectize.options) : Array.from(el.options).map(o => o.value); }}""")


def errors_shown(pg):
    return pg.locator(".shiny-output-error:visible").count()


def kpi(pg, i):
    return pg.locator("#db-kpis .rp-kpi-value").nth(i).inner_text()


def test_main_pages(page):
    vals = page.evaluate("Array.from(document.querySelectorAll('.navbar a.nav-link[data-value]')).map(a => a.dataset.value)")
    assert vals == ["dashboard", "product", "results", "inventory"]
    expect(page.locator(".rp-data-pill").first).to_contain_text(re.compile("Real data|Synthetic demo"))


def test_dashboard_content(page):
    expect(page.locator("#db-kpis .rp-kpi")).to_have_count(4)
    for t in ["Sales and estimated demand", "What this means", "Products that need attention"]:
        expect(page.get_by_text(t, exact=True).first).to_be_visible()
    page.wait_for_selector("#db-trend .plot-container", timeout=30000)
    assert page.locator("#db-attention .rt-tbody .rt-tr").count() > 0
    assert errors_shown(page) == 0


def test_period_and_category_filters(page):
    v28 = kpi(page, 0)
    sel(page, "#db-period", "7")
    v7 = kpi(page, 0)
    assert v7 != v28
    cat = [o for o in options(page, "#db-cat") if o][0]
    sel(page, "#db-cat", cat)
    assert kpi(page, 0) != v7
    sel(page, "#db-cat", "")
    sel(page, "#db-period", "28")
    assert kpi(page, 0) == v28


def test_action_filter_limits_attention_list(page):
    sel(page, "#db-action", "Review possible demand surge")
    acts = page.locator("#db-attention .rt-tbody .rt-tr .rt-td:nth-child(3)").all_inner_texts()
    assert acts and all(a.strip() == "Review possible demand surge" for a in acts)
    sel(page, "#db-action", "")


def test_attention_row_opens_product(page):
    first = page.locator("#db-attention .rt-tbody .rt-tr").first
    pid = first.locator(".rt-td").first.inner_text().strip()
    first.click()
    page.wait_for_timeout(3000)
    expect(page.locator("a.nav-link[data-value='product']")).to_have_class(re.compile("active"))
    expect(page.locator(".rp-prod-head h2")).to_have_text(pid)
    expect(page.locator(".rp-mini-kpis .rp-kpi")).to_have_count(4)
    expect(page.locator("#pr-reading")).to_contain_text("units expected over the next 7 days")
    assert errors_shown(page) == 0


def test_product_change_updates_page(page):
    target = [o for o in options(page, "#pr-product") if o][2]
    sel(page, "#pr-product", target)
    expect(page.locator(".rp-prod-head h2")).to_have_text("P" + target)
    assert page.locator("#pr-trend .plot-container").count() == 1


def test_forecast_horizon_and_history(page):
    page.locator("#pr-horizon input[value='14']").check()
    page.wait_for_timeout(2000)
    expect(page.locator("#pr-reading")).to_contain_text("next 14 days")
    expect(page.locator("#pr-reading .rp-warn")).to_contain_text("Only the first 7 days were tested")
    page.locator("#pr-horizon input[value='7']").check()
    sel(page, "#pr-window", "all")
    expect(page.locator("#pr-header")).to_contain_text("28 Mar")
    sel(page, "#pr-window", "56")


def test_more_about_product_renders_on_open(page):
    assert page.locator("#pr-wdh .plot-container").count() == 0          # not rendered while closed
    page.get_by_text("More about this product").click()
    page.wait_for_selector("#pr-wdh .plot-container", timeout=20000)
    page.wait_for_selector("#pr-compare .rt-table", timeout=20000)
    expect(page.locator("#pr-facts")).to_contain_text("Forecast error")


def test_results_tabs_render(page):
    nav(page, "results")
    for tab, sel_ in [("prep", "#rs-dims .rt-table"), ("eda", "#rs-store_wdh .plot-container"), ("fc", "#rs-fc_tbl .rt-table"),
                      ("risk", "#rs-confusion .rp-cm"), ("downloads", "#rs-downloads .rp-csv-grid"), ("adv", "#rs-heat .plot-container")]:
        page.evaluate(f"document.querySelector(\"a[data-value='{tab}']\").click()")
        page.wait_for_selector(sel_, timeout=30000)
        assert errors_shown(page) == 0, tab


def test_advanced_details_panels(page):
    for v, sel_ in [("rules", "#rs-rules li"), ("calib", "#rs-calib .plot-container"), ("promo", "#rs-promo .rt-table"), ("replay", "#rs-replay .rp-note")]:
        page.locator(f".accordion-item[data-value='{v}'] .accordion-button").click()
        page.wait_for_selector(sel_, timeout=20000)
    expect(page.locator("#rs-replay")).to_contain_text("not a live feed")


def test_csv_downloads(page):
    tab = page.locator("a[data-value='downloads']")
    expect(tab).to_have_text("CSV Downloads")
    page.evaluate("document.querySelector(\"a[data-value='downloads']\").click()")
    page.wait_for_selector("#rs-downloads .rp-csv-grid", timeout=20000)
    body = page.locator("#rs-downloads")
    expect(body).to_contain_text("Download analytical results")
    for gone in ["Open the report", "Download report (HTML)", "Save as PDF"]:
        expect(body).not_to_contain_text(gone)
    assert page.locator("#rs-dl_report").count() == 0
    assert page.locator("#rs-downloads .shiny-download-link").count() == 5
    for btn, name in [("#rs-dl_recs", "suggested_actions"), ("#rs-dl_risk", "product_risk"), ("#rs-dl_metrics", "model_evaluation"),
                      ("#rs-dl_anoms", "unusual_days"), ("#rs-dl_alerts", "replay_alerts")]:
        with page.expect_download() as d:
            page.locator(btn).click()
        assert name in d.value.suggested_filename
        with open(d.value.path(), encoding="utf-8") as f:
            assert len(f.read().strip().splitlines()) > 1


def test_store_switch(page):
    if page.locator("#store").count() == 0:
        pytest.skip("only one store shipped")
    other = options(page, "#store")[1]
    sel(page, "#store", other)
    page.wait_for_url(re.compile(rf"store={other}"), timeout=30000)
    page.wait_for_selector("#db-kpis .rp-kpi", timeout=60000)
    expect(page.locator(".rp-hero .rp-eyebrow").first).to_contain_text(f"Store {other}")
    page.goto(URL, wait_until="networkidle")
    page.wait_for_selector("#db-kpis .rp-kpi", timeout=60000)


def test_mobile_layout(page):
    page.set_viewport_size({"width": 390, "height": 844})
    page.wait_for_timeout(2000)
    over = page.evaluate("document.documentElement.scrollWidth - window.innerWidth")
    page.set_viewport_size({"width": 1440, "height": 900})
    assert over <= 2


def test_no_javascript_errors(page):
    assert [e for e in page.errors if not any(i in e for i in IGNORED)] == []
