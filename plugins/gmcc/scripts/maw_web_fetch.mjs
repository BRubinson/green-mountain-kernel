#!/usr/bin/env node

/**
 * maw_web_fetch.mjs - GMCC Maw Web Page Downloader
 *
 * Downloads web pages using headless Playwright and saves rendered HTML + markdown
 * to maw directories for kbite crunchable processing.
 *
 * Usage: node maw_web_fetch.mjs <manifest.json>
 *
 * Manifest schema:
 * {
 *   "urls": ["https://..."],
 *   "outputDir": "/path/to/maw/axis1/axis2/resource/",
 *   "options": {
 *     "timeout": 30000,
 *     "waitAfterLoad": 3000,
 *     "waitUntil": "networkidle"
 *   }
 * }
 *
 * Exit codes:
 *   0 - Success (at least one page downloaded)
 *   1 - Runtime error (all pages failed, invalid manifest, etc.)
 *   2 - Dependency missing (playwright not installed)
 */

import { readFileSync, writeFileSync, mkdirSync } from 'fs';
import { join } from 'path';

// Dependency check
let chromium;
try {
  const pw = await import('playwright');
  chromium = pw.chromium;
} catch {
  console.error('ERROR: playwright package not found.');
  console.error('Install with: npm install playwright');
  console.error('Then install browsers: npx playwright install chromium');
  process.exit(2);
}

// Parse CLI arguments
const manifestPath = process.argv[2];
if (!manifestPath) {
  console.error('Usage: node maw_web_fetch.mjs <manifest.json>');
  process.exit(1);
}

// Read manifest
let manifest;
try {
  manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
} catch (err) {
  console.error(`ERROR: Cannot read manifest: ${err.message}`);
  process.exit(1);
}

// Validate manifest
if (!Array.isArray(manifest.urls) || manifest.urls.length === 0) {
  console.error('ERROR: Manifest must contain a non-empty "urls" array.');
  process.exit(1);
}
if (!manifest.outputDir) {
  console.error('ERROR: Manifest must contain an "outputDir" string.');
  process.exit(1);
}

const options = {
  timeout: manifest.options?.timeout ?? 30000,
  waitAfterLoad: manifest.options?.waitAfterLoad ?? 3000,
  waitUntil: manifest.options?.waitUntil ?? 'networkidle',
};

// Create output directory
mkdirSync(manifest.outputDir, { recursive: true });

// Slug generation
function urlToSlug(url) {
  try {
    const parsed = new URL(url);
    const slug = parsed.pathname
      .replace(/^\/|\/$/g, '')
      .replace(/\//g, '_')
      .replace(/[^a-z0-9_-]/gi, '_')
      .toLowerCase();
    return slug || 'index';
  } catch {
    return 'page';
  }
}

// Deduplicate slugs
const usedSlugs = new Set();
function dedupeSlug(slug) {
  if (!usedSlugs.has(slug)) {
    usedSlugs.add(slug);
    return slug;
  }
  let i = 2;
  while (usedSlugs.has(`${slug}_${i}`)) i++;
  const deduped = `${slug}_${i}`;
  usedSlugs.add(deduped);
  return deduped;
}

// Download pages
const SCRIPT_VERSION = '1.0.0';

const results = { fetchedAt: new Date().toISOString(), scriptVersion: SCRIPT_VERSION, pages: [], errors: [] };

let browser;
try {
  browser = await chromium.launch({ headless: true });
} catch (err) {
  console.error(`ERROR: Cannot launch browser: ${err.message}`);
  console.error('Try running: npx playwright install chromium');
  process.exit(1);
}

try {
  const context = await browser.newContext({
    userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36',
    viewport: { width: 1280, height: 720 },
  });

  for (const url of manifest.urls) {
    const page = await context.newPage();
    try {
      console.log(`Downloading: ${url}`);

      await page.goto(url, {
        waitUntil: options.waitUntil,
        timeout: options.timeout,
      });

      // Wait for JS rendering
      await page.waitForTimeout(options.waitAfterLoad);

      const title = await page.title();
      const html = await page.content();
      const textContent = await page.evaluate(() => document.body.innerText);

      const slug = dedupeSlug(urlToSlug(url));
      const htmlFile = `${slug}.html`;
      const mdFile = `${slug}.md`;

      // Save HTML
      const htmlPath = join(manifest.outputDir, htmlFile);
      writeFileSync(htmlPath, html, 'utf8');

      // Save Markdown
      const markdown = `# ${title}\n\nSource: ${url}\n\n${textContent}`;
      const mdPath = join(manifest.outputDir, mdFile);
      writeFileSync(mdPath, markdown, 'utf8');

      const entry = {
        url,
        file: htmlFile,
        markdownFile: mdFile,
        title,
        fetchedAt: new Date().toISOString(),
        status: 'ok',
        sizeBytes: html.length,
      };
      results.pages.push(entry);

      console.log(`  OK: ${html.length} bytes -> ${htmlFile}`);
    } catch (err) {
      results.errors.push({ url, error: err.message });
      console.error(`  FAIL: ${err.message}`);
    } finally {
      await page.close();
    }
  }

  await context.close();
} finally {
  await browser.close();
}

// Write results manifest
const manifestOutPath = join(manifest.outputDir, '_manifest.json');
writeFileSync(manifestOutPath, JSON.stringify(results, null, 2), 'utf8');

// Summary
const okCount = results.pages.length;
const failCount = results.errors.length;
const total = okCount + failCount;

console.log(`\nDone. ${okCount}/${total} succeeded.`);

// Print summary JSON to stdout for agent parsing
const summary = { ok: okCount, failed: failCount, total, outputDir: manifest.outputDir };
console.log(JSON.stringify(summary));

process.exit(okCount > 0 ? 0 : 1);
