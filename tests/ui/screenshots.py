"""Capture screenshots of every page of a running RetailPulse app (for review and README).
Usage: python tests/ui/screenshots.py http://127.0.0.1:3838 out_dir
"""
import sys, os
from playwright.sync_api import sync_playwright

url = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:3838"
out = sys.argv[2] if len(sys.argv) > 2 else "docs/screenshots"
os.makedirs(out, exist_ok=True)
pages = [("overview", "Overview"), ("product", "Product"), ("monitor", "Monitoring"),
         ("scenario", "Forecast & Scenarios"), ("methods", "Data & Methods"), ("report", "Report")]
with sync_playwright() as p:
    b = p.chromium.launch()
    for w, h, tag in [(1440, 900, "desktop"), (390, 844, "mobile")]:
        pg = b.new_page(viewport={"width": w, "height": h})
        pg.goto(url, wait_until="networkidle")
        pg.wait_for_selector(".plotly", timeout=60000)
        pg.wait_for_timeout(2500)
        for key, label in pages:
            if tag == "mobile" and key not in ("overview", "product"):
                continue
            if key != "overview":
                pg.evaluate(f"document.querySelector(\"a.nav-link[data-value='{key}']\").click()")
                pg.wait_for_timeout(6000)
            pg.screenshot(path=f"{out}/{tag}_{key}.png", full_page=True)
        pg.close()
    b.close()
print("saved to", out)
