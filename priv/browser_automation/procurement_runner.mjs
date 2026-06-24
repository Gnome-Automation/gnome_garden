import { chromium } from '@playwright/test';
import fs from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';

const input = await readJsonStdin();

try {
  const result = await run(input);
  writeJson({ ok: true, ...result });
} catch (error) {
  writeJson({
    ok: false,
    error: error && error.message ? error.message : String(error),
    code: error && error.code ? error.code : 'playwright_runner_failed'
  });
  process.exitCode = 1;
}

async function run(payload) {
  switch (payload.action) {
    case 'probe':
      return await probe(payload);
    default:
      throw Object.assign(new Error(`Unsupported Playwright action: ${payload.action}`), {
        code: 'unsupported_action'
      });
  }
}

async function probe(payload) {
  requireString(payload.url, 'url');

  const timeoutMs = positiveInteger(payload.timeoutMs ?? payload.timeout_ms, 60000);
  const headed = payload.headed === true;
  const browser = await chromium.launch({
    headless: !headed,
    args: ['--no-sandbox']
  });

  const context = await browser.newContext();
  const page = await context.newPage();
  const tracePath = stringOrNull(payload.tracePath ?? payload.trace_path);
  const screenshotPath = stringOrNull(payload.screenshotPath ?? payload.screenshot_path);
  const storageStatePath = stringOrNull(payload.storageStatePath ?? payload.storage_state_path);

  try {
    if (tracePath) {
      await ensureParentDir(tracePath);
      await context.tracing.start({ screenshots: true, snapshots: true });
    }

    const response = await page.goto(payload.url, {
      waitUntil: payload.waitUntil || 'domcontentloaded',
      timeout: timeoutMs
    });

    if (storageStatePath) {
      await ensureParentDir(storageStatePath);
      await context.storageState({ path: storageStatePath });
    }

    if (screenshotPath) {
      await ensureParentDir(screenshotPath);
      await page.screenshot({ path: screenshotPath, fullPage: true });
    }

    if (tracePath) {
      await context.tracing.stop({ path: tracePath });
    }

    return {
      action: 'probe',
      url: payload.url,
      finalUrl: page.url(),
      title: await page.title(),
      status: response ? response.status() : null,
      storageStatePath,
      tracePath,
      screenshotPath
    };
  } catch (error) {
    if (screenshotPath) {
      await ensureParentDir(screenshotPath);
      await page.screenshot({ path: screenshotPath, fullPage: true }).catch(() => {});
    }

    if (tracePath) {
      await context.tracing.stop({ path: tracePath }).catch(() => {});
    }

    throw error;
  } finally {
    await browser.close();
  }
}

function requireString(value, field) {
  if (typeof value !== 'string' || value.trim() === '') {
    throw Object.assign(new Error(`${field} is required`), { code: 'invalid_input' });
  }
}

function stringOrNull(value) {
  return typeof value === 'string' && value.trim() !== '' ? value : null;
}

function positiveInteger(value, fallback) {
  const parsed = Number.parseInt(value, 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

async function ensureParentDir(filePath) {
  await fs.mkdir(path.dirname(filePath), { recursive: true, mode: 0o700 });
}

async function readJsonStdin() {
  const chunks = [];

  for await (const chunk of process.stdin) {
    chunks.push(chunk);
  }

  const raw = Buffer.concat(chunks).toString('utf8');
  return raw.trim() === '' ? {} : JSON.parse(raw);
}

function writeJson(value) {
  process.stdout.write(`${JSON.stringify(value)}\n`);
}
