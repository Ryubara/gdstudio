"""Runs the web export of the crowd benchmark in the installed Chrome and prints the RESULT lines.

usage: uvx --with playwright python web_bench.py <url of index.html> <log> [count:techs ...]
The page is driven by its query string (?count=40&techs=all). Chrome runs with its normal GPU, headed.
"""

import sys

from playwright.sync_api import sync_playwright

RUNS = [(10, ""), (20, ""), (40, ""), (80, ""), (10, "all"), (20, "all"), (40, "all"), (80, "all"), (160, "all")]


def main() -> None:
    base, log = sys.argv[1], sys.argv[2]
    runs = [(int(a.split(":")[0]), a.split(":")[1]) for a in sys.argv[3:]] or RUNS
    with sync_playwright() as p, open(log, "w", encoding="utf-8") as out:
        browser = p.chromium.launch(channel="chrome", headless=False)
        for count, techs in runs:
            page = browser.new_page(viewport={"width": 1280, "height": 720})
            lines: list[str] = []
            page.on("console", lambda m, lines=lines: lines.append(m.text) if m.text.startswith("RESULT") else None)
            page.goto(f"{base}?count={count}&techs={techs}&warmup=300&frames=400")
            for _ in range(90):
                if lines:
                    break
                page.wait_for_timeout(1000)
            if lines:
                page.screenshot(path=log.replace(".log", f"-{count}-{techs or 'none'}.png"))
            out.write((lines[0] if lines else f"RESULT count={count} techs={techs or 'none'} TIMEOUT") + "\n")
            out.flush()
            page.close()
        browser.close()


if __name__ == "__main__":
    main()
