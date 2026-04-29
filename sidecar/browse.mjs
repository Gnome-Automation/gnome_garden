#!/usr/bin/env node
/**
 * Headless browser helper for pi.
 * Pi calls this via bash to navigate JS-rendered pages.
 *
 * Usage:
 *   node browse.mjs <url>                          # Get full page text
 *   node browse.mjs <url> --select "css selector"  # Extract elements matching selector
 *   node browse.mjs <url> --links                  # Extract all links
 *   node browse.mjs <url> --screenshot out.png     # Take screenshot
 *   node browse.mjs <url> --wait 5000              # Wait ms before extracting
 *   node browse.mjs <url> --click "selector"       # Click something first, then extract
 *   node browse.mjs <url> --planetbids             # PlanetBids-specific bid extraction
 *   node browse.mjs <url> --planetbids-detail      # PlanetBids bid detail + docs + bidders
 *   node browse.mjs --search "SCADA Orange County" # Search via DuckDuckGo (no API key needed)
 */

import { chromium } from "playwright";

const args = process.argv.slice(2);
const url = args[0]?.startsWith("--") ? null : args[0];

// Check for --search before requiring url
const hasSearch = args.includes("--search");
if (!url && !hasSearch) {
  console.error("Usage: node browse.mjs <url> [options]");
  console.error("       node browse.mjs --search <query>");
  console.error("  --select <css>     Extract elements matching selector");
  console.error("  --links            Extract all links");
  console.error("  --screenshot <f>   Save screenshot");
  console.error("  --wait <ms>        Wait before extracting (default 3000)");
  console.error("  --click <css>      Click element first");
  console.error("  --planetbids       PlanetBids portal bid extraction");
  console.error("  --search <query>   Search via DuckDuckGo (no API key needed)");
  process.exit(1);
}

// Parse flags
let selector = null;
let links = false;
let screenshot = null;
let waitMs = 3000;
let clickSelector = null;
let planetbids = false;
let planetbidsDetail = false;
let downloadDir = null;
let searchQuery = null;

for (let i = (url ? 1 : 0); i < args.length; i++) {
  switch (args[i]) {
    case "--select": selector = args[++i]; break;
    case "--links": links = true; break;
    case "--screenshot": screenshot = args[++i]; break;
    case "--wait": waitMs = parseInt(args[++i]); break;
    case "--click": clickSelector = args[++i]; break;
    case "--planetbids": planetbids = true; waitMs = Math.max(waitMs, 10000); break;
    case "--planetbids-detail": planetbidsDetail = true; waitMs = Math.max(waitMs, 10000); break;
    case "--download": downloadDir = args[++i]; break;
    case "--search": searchQuery = args[++i]; break;
  }
}

let browser;
try {
  // Headed mode with virtual display — avoids bot detection without showing windows
  browser = await chromium.launch({
    headless: false,
    args: [
      "--disable-blink-features=AutomationControlled",
      "--window-position=-9999,-9999",
      "--window-size=1,1",
    ],
  });
  const context = await browser.newContext({
    userAgent:
      "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
  });
  const page = await context.newPage();

  // --- DuckDuckGo search mode ---
  if (searchQuery) {
    const searchUrl = `https://duckduckgo.com/?q=${encodeURIComponent(searchQuery)}`;
    await page.goto(searchUrl, { waitUntil: "load", timeout: 30000 });
    await page.waitForTimeout(4000);

    const results = await page.evaluate(() => {
      return Array.from(document.querySelectorAll("h2")).map(h => {
        const link = h.closest("a") || h.querySelector("a") || h.parentElement?.querySelector("a");
        const parent = h.closest("article") || h.parentElement?.parentElement;
        const snippet = parent?.querySelector("span, p:not(:has(a))")?.innerText?.trim() || "";
        return {
          title: h.innerText.trim(),
          url: link?.href || "",
          snippet: snippet.slice(0, 200),
        };
      }).filter(r => r.url && !r.url.includes("duckduckgo.com"));
    });

    for (const r of results.slice(0, 15)) {
      console.log(`${r.title}`);
      console.log(`  ${r.url}`);
      if (r.snippet) console.log(`  ${r.snippet}`);
      console.log("");
    }

    await browser.close();
    process.exit(0);
  }

  await page
    .goto(url, { waitUntil: "load", timeout: 45000 })
    .catch(() => page.goto(url, { waitUntil: "domcontentloaded", timeout: 15000 }));

  if (waitMs > 0) {
    await page.waitForTimeout(waitMs);
  }

  if (clickSelector) {
    try {
      await page.click(clickSelector, { timeout: 5000 });
      await page.waitForTimeout(2000);
    } catch {
      console.error(`Could not click: ${clickSelector}`);
    }
  }

  // --- PlanetBids-specific extraction ---
  if (planetbids) {
    const bids = await page.evaluate(() => {
      const rows = document.querySelectorAll("table tbody tr");
      return Array.from(rows).map((row) => {
        const cells = row.querySelectorAll("td");
        if (cells.length < 4) return null;

        // Find the link in the row
        const link = row.querySelector("a[href]");
        const href = link ? link.href : "";

        return {
          posted: cells[0]?.innerText?.trim() || "",
          title: cells[1]?.innerText?.trim() || "",
          invitation: cells[2]?.innerText?.trim() || "",
          due_date: cells[3]?.innerText?.trim() || "",
          remaining: cells[4]?.innerText?.trim() || "",
          stage: cells[5]?.innerText?.trim() || "",
          url: href,
        };
      }).filter(Boolean);
    });

    if (bids.length === 0) {
      // Fallback — try to get the page text
      const text = await page.evaluate(() => document.body.innerText.slice(0, 10000));
      console.log("No table rows found. Page text:");
      console.log(text);
    } else {
      // Get portal name from page
      const portalName = await page.evaluate(() => {
        const h1 = document.querySelector("h1, .agency-name, .portal-name");
        return h1 ? h1.innerText.trim() : "";
      });
      if (portalName) console.log(`Portal: ${portalName}`);
      console.log(`Found ${bids.length} bids\n`);

      for (const bid of bids) {
        console.log(`Title: ${bid.title}`);
        console.log(`Posted: ${bid.posted}`);
        console.log(`Due: ${bid.due_date}`);
        console.log(`Remaining: ${bid.remaining}`);
        console.log(`Stage: ${bid.stage}`);
        console.log(`Invitation #: ${bid.invitation}`);
        if (bid.url) console.log(`URL: ${bid.url}`);
        console.log("---");
      }
    }
  } else if (planetbidsDetail) {
    // --- PlanetBids bid detail page extraction ---
    // Extract bid information
    const bidInfo = await page.evaluate(() => {
      const getText = (label) => {
        const els = document.querySelectorAll("td, th, dt, dd, div, span, p");
        for (const el of els) {
          if (el.innerText?.trim() === label) {
            const next = el.nextElementSibling;
            if (next) return next.innerText?.trim();
          }
        }
        return "";
      };
      return {
        title: document.querySelector("h1, h2, .bid-title")?.innerText?.trim() ||
               document.title,
        body: document.body.innerText.slice(0, 8000),
      };
    });

    console.log("=== BID DETAIL ===");
    console.log(bidInfo.body);

    // Click Documents tab and extract doc list
    try {
      await page.click("text=Documents", { timeout: 5000 });
      await page.waitForTimeout(4000);

      const docs = await page.evaluate(() => {
        const rows = document.querySelectorAll("table tr, .document-row, [class*=document]");
        const results = [];
        const text = document.body.innerText;
        // Parse document entries from page text
        const lines = text.split("\n").map(l => l.trim()).filter(Boolean);
        for (let i = 0; i < lines.length; i++) {
          if (lines[i].match(/\.pdf|\.doc|\.xlsx|\.zip/i)) {
            results.push({
              filename: lines[i],
              size: lines[i + 1]?.match(/kb|mb|gb/i) ? lines[i + 1] : "",
            });
          }
        }
        return results;
      });

      if (docs.length > 0) {
        console.log("\n=== DOCUMENTS ===");
        for (const doc of docs) {
          console.log(`  ${doc.filename} ${doc.size ? `(${doc.size})` : ""}`);
        }
      }
    } catch {
      console.log("\n(Could not access Documents tab)");
    }

    // Click Prospective Bidders tab
    try {
      await page.click("text=Prospective Bidders", { timeout: 5000 });
      await page.waitForTimeout(4000);

      const bidders = await page.evaluate(() => {
        const text = document.body.innerText;
        const match = text.match(/Showing (\d+) Prospective Bidders/);
        const count = match ? parseInt(match[1]) : 0;

        // Extract bidder names
        const entries = [];
        const els = document.querySelectorAll("[class*=vendor], [class*=bidder], td");
        for (const el of els) {
          const t = el.innerText?.trim();
          if (t && t.length > 3 && t.length < 100 && !t.includes("\n") &&
              !t.match(/^(Vendor|Type|Status|Phone|Contact|Showing)/)) {
            entries.push(t);
          }
        }
        return { count, entries: entries.slice(0, 30) };
      });

      console.log(`\n=== PROSPECTIVE BIDDERS (${bidders.count}) ===`);
      // Just get the full text of the tab
      const biddersText = await page.evaluate(() => {
        return document.body.innerText.slice(
          document.body.innerText.indexOf("Prospective Bidders"),
          document.body.innerText.indexOf("Prospective Bidders") + 5000
        );
      });
      console.log(biddersText);
    } catch {
      console.log("\n(Could not access Prospective Bidders tab)");
    }

    // Click Addenda tab
    try {
      await page.click("text=Addenda", { timeout: 3000 });
      await page.waitForTimeout(3000);
      const addendaText = await page.evaluate(() => {
        const text = document.body.innerText;
        const start = text.indexOf("Addenda");
        return text.slice(start, start + 3000);
      });
      if (addendaText.length > 20) {
        console.log("\n=== ADDENDA ===");
        console.log(addendaText);
      }
    } catch {}

  } else if (screenshot) {
    await page.screenshot({ path: screenshot, fullPage: true });
    console.log(`Screenshot saved to ${screenshot}`);
  } else if (links) {
    const allLinks = await page.evaluate(() => {
      return Array.from(document.querySelectorAll("a[href]"))
        .map((a) => ({
          text: a.innerText.trim().slice(0, 100),
          href: a.href,
        }))
        .filter((l) => l.text && l.href.startsWith("http"));
    });
    for (const link of allLinks) {
      console.log(`${link.text}\n  ${link.href}\n`);
    }
  } else if (selector) {
    const elements = await page.evaluate((sel) => {
      return Array.from(document.querySelectorAll(sel)).map((el) => {
        const cells = el.querySelectorAll("td, th");
        if (cells.length > 0) {
          return Array.from(cells)
            .map((c) => c.innerText.trim())
            .join(" | ");
        }
        return el.innerText.trim();
      });
    }, selector);
    for (const el of elements) {
      console.log(el);
      console.log("---");
    }
  } else {
    const text = await page.evaluate(() => {
      document
        .querySelectorAll("script, style, nav, footer, header")
        .forEach((el) => el.remove());
      return document.body.innerText;
    });
    console.log(text.slice(0, 50000));
  }
} catch (err) {
  console.error(`Browser error: ${err.message}`);
  process.exit(1);
} finally {
  if (browser) await browser.close();
}
