"""Capture screenshots of the three pages of a running RetailPulse app (for review and README).
Usage: python tests/ui/screenshots.py http://127.0.0.1:3838 docs/screenshots
"""
import sys, os
from playwright.sync_api import sync_playwright

url = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:3838"
out = sys.argv[2] if len(sys.argv) > 2 else "docs/screenshots"
os.makedirs(out, exist_ok=True)
with sync_playwright() as p:
    b = p.chromium.launch()
    for w, h, tag in [(1440, 900, "desktop"), (390, 844, "mobile")]:
        pg = b.new_page(viewport={"width": w, "height": h})
        pg.route("**/fonts.g*/**", lambda r: r.abort())
        pg.goto(url, wait_until="networkidle")
        pg.wait_for_selector("#db-kpis .rp-kpi", timeout=60000)
        pg.wait_for_timeout(2500)
        pg.screenshot(path=f"{out}/{tag}_dashboard.png", full_page=True)
        if tag == "mobile":
            pg.close(); continue
        pg.evaluate("document.querySelector(\"a.nav-link[data-value='product']\").click()")
        pg.wait_for_timeout(4000)
        pg.screenshot(path=f"{out}/{tag}_product.png", full_page=True)
        pg.evaluate("document.querySelector(\"a.nav-link[data-value='results']\").click()")
        pg.wait_for_timeout(1500)
        pg.evaluate("document.querySelector(\"a[data-value='fc']\").click()")
        pg.wait_for_timeout(3500)
        pg.screenshot(path=f"{out}/{tag}_results.png", full_page=True)
        pg.close()
    b.close()
print("saved to", out)
