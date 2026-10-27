"""Browser tests for the Inventory page (catalogue, CSV import/export, simulator) and the
links between pages. Start the app first, then:
    RP_URL=http://127.0.0.1:3838 pytest tests/ui/test_inventory.py -q
"""
import csv, io, os, re, tempfile
import pytest
from playwright.sync_api import sync_playwright, expect

URL = os.environ.get("RP_URL", "http://127.0.0.1:3838").rstrip("/") + "/"


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
        pg.wait_for_selector(".plotly", timeout=60000)
        pg.evaluate("localStorage.removeItem('retailpulse.catalogue.v1')")
        pg.wait_for_timeout(5000); pg.goto(URL, wait_until="domcontentloaded"); pg.wait_for_selector(".plotly", timeout=60000)
        pg.errors = errors
        yield pg
        b.close()


def nav(pg, key):
    pg.locator(f"a.nav-link[data-value='{key}']").first.click()
    pg.wait_for_timeout(1500)


def rows(pg):
    return pg.locator("#inv-table .rt-tbody .rt-tr")


def stored(pg):
    return pg.evaluate("JSON.parse(localStorage.getItem('retailpulse.catalogue.v1') || '{\"rows\":[]}').rows")


def download_text(pg, selector):
    with pg.expect_download() as d:
        pg.locator(selector).click()
    with open(d.value.path(), encoding="utf-8") as f:
        return d.value.suggested_filename, f.read()


def test_empty_state_and_sample_records(page):
    nav(page, "inventory")
    expect(page.locator("#inv-table_wrap")).to_contain_text("Your catalogue is empty")
    expect(page.locator(".rp-info-banner").first).to_contain_text("separate from the FreshRetailNet-50K research data")
    page.locator("#inv-table_wrap button[data-rp-value='sample']").click()
    expect(rows(page)).to_have_count(8, timeout=10000)
    expect(page.locator("#inv-table")).to_contain_text("Sample record")
    assert len(stored(page)) == 8                                # saved in the browser


def test_add_product_with_validation(page):
    page.locator("#inv-add").click()
    page.wait_for_selector("#inv-f_sku")
    page.locator("#inv-f_sku").fill("SAMPLE-001")                # duplicate SKU
    page.locator("#inv-f_name").fill("")
    page.locator("#inv-f_stock").fill("-3")
    page.locator("#inv-save").click()
    errs = page.locator("#inv-form_errors")
    expect(errs).to_contain_text("already in your catalogue")
    expect(errs).to_contain_text("name is missing")
    expect(errs).to_contain_text("cannot be negative")
    page.locator("#inv-f_sku").fill("TEA-01")
    page.locator("#inv-f_name").fill("Green tea 50 bags")
    page.locator("#inv-f_stock").fill("12")
    page.locator("#inv-f_reorder").fill("5")
    page.locator("#inv-f_lead").fill("3")
    page.locator("#inv-save").click()
    expect(page.locator(".modal")).to_have_count(0, timeout=5000)
    expect(rows(page)).to_have_count(9)
    expect(page.locator(".shiny-notification").last).to_contain_text("Added Green tea")
    rec = [r for r in stored(page) if r["sku"] == "TEA-01"][0]
    assert rec["stock"] == 12 and rec["source"] == "user"


def test_edit_and_link_to_research_product(page):
    page.locator("#inv-table .rt-search").fill("TEA-01")
    page.locator("button.rp-icon-btn[title='Edit']").first.click()
    page.wait_for_selector("#inv-f_stock")
    page.locator("#inv-f_stock").fill("4")
    page.evaluate("document.querySelector('#inv-f_link').selectize.setValue('108')")
    page.locator("#inv-save").click()
    expect(page.locator(".modal")).to_have_count(0, timeout=5000)
    rec = [r for r in stored(page) if r["sku"] == "TEA-01"][0]
    assert rec["stock"] == 4 and rec["linked_product_id"] == 108
    expect(page.locator("#inv-table")).to_contain_text("P108")
    expect(page.locator("#inv-table")).to_contain_text("At or below reorder level")
    page.locator("#inv-table .rt-search").fill("")


def test_kpi_card_filters_table(page):
    page.locator("#inv-kpis .rp-kpi-click", has_text="Out of stock").click()
    page.wait_for_timeout(800)
    statuses = page.locator("#inv-table .rt-tbody .rt-tr").all_inner_texts()
    assert statuses and all("Out of stock" in s for s in statuses)
    page.locator("#inv-f_reset").click()
    page.wait_for_timeout(800)
    expect(rows(page)).to_have_count(9)


def test_delete_needs_confirmation(page):
    page.locator("#inv-table .rt-search").fill("SAMPLE-008")
    page.locator("button.rp-icon-btn[title='Delete']").first.click()
    expect(page.locator(".modal")).to_contain_text("Delete this product?")
    page.get_by_role("button", name="Keep it").click()
    expect(page.locator(".modal")).to_have_count(0, timeout=5000)
    assert any(r["sku"] == "SAMPLE-008" for r in stored(page))
    page.locator("button.rp-icon-btn[title='Delete']").first.click()
    page.locator("#inv-del_ok").click()
    expect(page.locator(".modal")).to_have_count(0, timeout=5000)
    assert not any(r["sku"] == "SAMPLE-008" for r in stored(page))
    page.locator("#inv-table .rt-search").fill("")


def test_template_and_export(page):
    name, txt = download_text(page, "#inv-template")
    assert name == "retailpulse_catalogue_template.csv" and txt.startswith('"sku","name","category"')
    name, txt = download_text(page, "#inv-export")
    data = list(csv.DictReader(io.StringIO(txt)))
    assert len(data) == 8 and {"sku", "name", "stock", "status", "source", "linked_product_id"} <= set(data[0])
    tea = [r for r in data if r["sku"] == "TEA-01"][0]
    assert tea["linked_product_id"] == "P108" and tea["source"] == "Your data"


def test_import_preview_rejects_and_skips(page):
    f = tempfile.NamedTemporaryFile("w", suffix=".csv", delete=False, encoding="utf-8")
    f.write("SKU,Product Name,Quantity,price,expiry_date,linked_product_id\n"
            "RICE-5,Basmati rice 5 kg,7,9.5,2027-03-01,\n"
            "SAMPLE-001,Milk from file,99,,,\n"
            ",No sku,3,,,\n"
            "OIL-1,Olive oil,-2,,,\n"
            "JAM-1,Jam,2,abc,31/12/2026,P999999\n")
    f.close()
    page.locator("#inv-import").click()
    page.wait_for_selector("#inv-csv")
    page.set_input_files("#inv-csv", f.name)
    prev = page.locator("#inv-import_preview")
    expect(prev).to_contain_text("5 rows read", timeout=10000)
    expect(prev).to_contain_text("2 valid")                       # RICE-5 and SAMPLE-001 (valid, but the SKU already exists)
    expect(prev).to_contain_text("1 SKUs already exist")
    expect(prev).to_contain_text("3 with problems")
    expect(prev).to_contain_text("Skipped: SKU exists")
    expect(prev).to_contain_text("SKU is missing")
    name, txt = download_text(page, "#inv-import_rejects")
    bad = list(csv.DictReader(io.StringIO(txt)))
    assert len(bad) == 3 and all(r["problems"] for r in bad)
    page.locator("#inv-import_ok").click()
    expect(page.locator(".modal")).to_have_count(0, timeout=5000)
    expect(page.locator(".shiny-notification").last).to_contain_text("1 added, 0 replaced, 1 skipped")
    st = {r["sku"]: r for r in stored(page)}
    assert "RICE-5" in st and st["RICE-5"]["source"] == "import"
    assert st["SAMPLE-001"]["stock"] == 14                        # existing record not overwritten
    assert "OIL-1" not in st and "JAM-1" not in st
    os.unlink(f.name)


def test_import_rejects_wrong_file(page):
    f = tempfile.NamedTemporaryFile("w", suffix=".csv", delete=False, encoding="utf-8")
    f.write("colour,size\nred,M\n"); f.close()
    page.locator("#inv-import").click()
    page.set_input_files("#inv-csv", f.name)
    expect(page.locator("#inv-import_preview")).to_contain_text("Missing required column", timeout=10000)
    page.get_by_role("button", name="Cancel").click()
    os.unlink(f.name)


def set_num(pg, sel, v):
    pg.locator(sel).fill(str(v)); pg.locator(sel).dispatch_event("change"); pg.wait_for_timeout(900)


def test_simulator_numbers_and_scenario(page):
    page.locator("#inv-table .rt-search").fill("SAMPLE-004")         # eggs: stock 30, lead 3, reorder 12
    page.locator("button.rp-icon-btn[title='Simulate']").first.click()
    page.wait_for_timeout(1500)
    assert page.locator("#inv-sim_stock").input_value() == "30"
    set_num(page, "#inv-sim_stock", 10)
    set_num(page, "#inv-sim_demand", 4)
    set_num(page, "#inv-sim_lead", 2)
    set_num(page, "#inv-sim_safety", 3)
    cmp = page.locator("#inv-sim_compare")
    expect(cmp).to_contain_text("2.5 days")                       # 10 / 4
    expect(cmp).to_contain_text("2 items left on day 2")
    set_num(page, "#inv-sim_delay", 2)
    page.evaluate("$('#inv-sim_mult').data('ionRangeSlider').update({from: 50}); $('#inv-sim_mult').trigger('change')")
    page.wait_for_timeout(1200)
    expect(cmp).to_contain_text("1.7 days")                       # 10 / 6
    expect(page.locator("#inv-sim_note")).to_contain_text("before a delivery ordered today would arrive")
    expect(page.locator("#inv-sim_note")).to_contain_text("Hypothetical simulation")
    assert page.evaluate("document.getElementById('inv-sim_plot').data.length") == 2
    name, txt = download_text(page, "#inv-sim_dl")
    sim = list(csv.DictReader(io.StringIO(txt)))
    assert sim[0]["stock_assumptions"] == "10" and float(sim[1]["expected_demand_scenario"]) == 6
    set_num(page, "#inv-sim_demand", 0)
    expect(page.locator("#inv-sim_note")).to_contain_text("does not run down")
    page.locator("#inv-sim_demand").fill("-1"); page.locator("#inv-sim_demand").dispatch_event("change"); page.wait_for_timeout(900)
    expect(page.locator("#inv-sim_compare")).to_contain_text("cannot be negative")
    page.locator("#inv-sim_reset").click(); page.wait_for_timeout(1000)
    assert page.locator("#inv-sim_stock").input_value() == "30"
    page.locator("#inv-table .rt-search").fill("")


def test_linked_product_pattern_and_research_box(page):
    page.locator("#inv-table .rt-search").fill("TEA-01")
    page.locator("button.rp-icon-btn[title='Simulate']").first.click()
    page.wait_for_timeout(1500)
    set_num(page, "#inv-sim_demand", 2)
    expect(page.locator("#inv-sim_pattern_ui")).to_contain_text("P108's weekday pattern")
    expect(page.locator("#inv-sim_research")).to_contain_text("Historical research data")
    page.locator("#inv-sim_pattern").check(); page.wait_for_timeout(1200)
    expect(page.locator("#inv-sim_note")).to_contain_text("relative weights")
    page.locator("#inv-sim_research button").click()
    page.wait_for_timeout(2500)
    expect(page.locator(".navbar .nav-link.active")).to_have_attribute("data-value", "product")
    expect(page.locator(".rp-prod-head h2")).to_have_text("P108")


def test_product_page_shows_linked_item_and_jumps_back(page):
    expect(page.locator("#pr-linked")).to_contain_text("Green tea 50 bags", timeout=10000)
    page.locator("#pr-linked button[data-rp-value='TEA-01']").click()
    page.wait_for_timeout(2500)
    expect(page.locator(".navbar .nav-link.active")).to_have_attribute("data-value", "inventory")
    assert page.locator("#inv-sim_sku").input_value() == "TEA-01"


def test_dashboard_kpis_open_analysis(page):
    nav(page, "dashboard")
    page.locator("#db-kpis .rp-kpi-click").nth(2).click()        # Demand missed -> Stockout risk tab
    page.wait_for_timeout(2500)
    expect(page.locator(".navbar .nav-link.active")).to_have_attribute("data-value", "results")
    expect(page.locator("a.nav-link[data-value='risk']")).to_have_class(re.compile("active"))
    nav(page, "dashboard")
    page.locator("#db-kpis .rp-kpi-click").nth(0).click()        # Recorded sales -> Exploring the data
    page.wait_for_timeout(2000)
    expect(page.locator("a.nav-link[data-value='eda']")).to_have_class(re.compile("active"))


def test_catalogue_survives_reload(page):
    before = sorted(r["sku"] for r in stored(page))
    page.wait_for_timeout(5000); page.goto(URL, wait_until="domcontentloaded"); page.wait_for_selector(".plotly", timeout=60000)
    nav(page, "inventory")
    expect(rows(page)).to_have_count(len(before), timeout=10000)
    expect(page.locator("#inv-table")).to_contain_text("Green tea 50 bags")


def test_clear_all_with_confirmation(page):
    page.locator("#inv-clear").click()
    expect(page.locator(".modal")).to_contain_text("Clear the whole catalogue?")
    page.locator("#inv-clear_ok").click()
    expect(page.locator("#inv-table_wrap")).to_contain_text("Your catalogue is empty", timeout=5000)
    assert stored(page) == []


def test_mobile_layout(page):
    page.set_viewport_size({"width": 390, "height": 844})
    page.wait_for_timeout(1200)
    over = page.evaluate("document.documentElement.scrollWidth - window.innerWidth")
    page.set_viewport_size({"width": 1440, "height": 900})
    assert over <= 2


def test_no_javascript_errors(page):
    assert page.errors == []
