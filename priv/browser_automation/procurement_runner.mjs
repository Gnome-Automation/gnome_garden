import { chromium } from 'playwright';
import { constants as fsConstants } from 'node:fs';
import fs from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';

const defaultUserAgent =
  'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36';

const input = deepMerge(await readJsonInput(), await readSecretInput());

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
    case 'bidnet_login':
      return await bidnetLogin(payload);
    case 'probe':
      return await probe(payload);
    default:
      throw Object.assign(new Error(`Unsupported Playwright action: ${payload.action}`), {
        code: 'unsupported_action'
      });
  }
}

async function bidnetLogin(payload) {
  requireString(payload.url, 'url');
  requireString(payload.username, 'username');
  requireString(payload.password, 'password');

  const timeoutMs = positiveInteger(payload.timeoutMs ?? payload.timeout_ms, 60000);
  const headed = payload.headed === true;
  const browser = await chromium.launch(await chromiumLaunchOptions(headed));

  const context = await browser.newContext(browserContextOptions());
  const page = await context.newPage();
  const tracePath = stringOrNull(payload.tracePath ?? payload.trace_path);
  const screenshotPath = stringOrNull(payload.screenshotPath ?? payload.screenshot_path);

  try {
    if (tracePath) {
      await ensureParentDir(tracePath);
      await context.tracing.start({ screenshots: true, snapshots: true });
    }

    const response = await page.goto(payload.url, { waitUntil: 'domcontentloaded', timeout: timeoutMs });
    ensureAllowedResponse(response, payload.url);
    await openLoginSurface(page, timeoutMs);

    const usernameInput = page
      .locator('input[type="email"], input[name*="email" i], input[id*="email" i], input[name*="user" i], input[id*="user" i], input[type="text"]')
      .first();
    await usernameInput.waitFor({ state: 'visible', timeout: timeoutMs });
    await usernameInput.fill(payload.username);

    const nextButton = page
      .getByRole('button', { name: /next|continue|sign in|log in/i })
      .or(page.locator('input[type="submit"], button[type="submit"]').first())
      .first();
    await nextButton.click({ timeout: timeoutMs }).catch(() => {});

    const passwordInput = page.locator('input[type="password"]').first();
    await passwordInput.waitFor({ state: 'visible', timeout: timeoutMs });
    await passwordInput.fill(payload.password);

    const submitButton = page
      .getByRole('button', { name: /sign in|log in|login|submit|continue/i })
      .or(page.locator('input[type="submit"], button[type="submit"]').first())
      .first();
    await submitButton.click({ timeout: timeoutMs });

    await page.waitForLoadState('domcontentloaded', { timeout: timeoutMs }).catch(() => {});
    await page
      .waitForFunction(
        () => /logout|log out|sign out|my account|dashboard|profile/i.test(document.body?.innerText || ''),
        null,
        { timeout: timeoutMs }
      )
      .catch(() => {});

    const bodyText = await page.locator('body').innerText({ timeout: 5000 }).catch(() => '');
    if (/invalid|incorrect|wrong password|login failed|unable to log/i.test(bodyText)) {
      throw Object.assign(new Error('BidNet rejected these credentials.'), {
        code: 'invalid_credentials'
      });
    }

    await writeSecretOutput({ storageState: await context.storageState() });

    if (screenshotPath) {
      await ensureParentDir(screenshotPath);
      await page.screenshot({ path: screenshotPath, fullPage: true });
    }

    if (tracePath) {
      await context.tracing.stop({ path: tracePath });
    }

    return {
      action: 'bidnet_login',
      finalUrl: page.url(),
      title: await safeTitle(page),
      status: null,
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

async function openLoginSurface(page, timeoutMs) {
  if (await page.locator('input[type="password"]').first().isVisible().catch(() => false)) {
    return;
  }

  const loginUrl = new URL('/public/authentication/login', page.url()).toString();
  const response = await page.goto(loginUrl, { waitUntil: 'domcontentloaded', timeout: timeoutMs }).catch(async () => {
    const login = page
      .getByRole('link', { name: /sign in|log in|login/i })
      .or(page.getByRole('button', { name: /sign in|log in|login/i }))
      .first();
    await login.click({ timeout: timeoutMs });

    return null;
  });

  ensureAllowedResponse(response, loginUrl);
}

async function probe(payload) {
  requireString(payload.url, 'url');

  const timeoutMs = positiveInteger(payload.timeoutMs ?? payload.timeout_ms, 60000);
  const headed = payload.headed === true;
  const browser = await chromium.launch(await chromiumLaunchOptions(headed));

  const context = await browser.newContext(browserContextOptions());
  const page = await context.newPage();
  const tracePath = stringOrNull(payload.tracePath ?? payload.trace_path);
  const screenshotPath = stringOrNull(payload.screenshotPath ?? payload.screenshot_path);

  try {
    if (tracePath) {
      await ensureParentDir(tracePath);
      await context.tracing.start({ screenshots: true, snapshots: true });
    }

    const response = await page.goto(payload.url, {
      waitUntil: payload.waitUntil || 'domcontentloaded',
      timeout: timeoutMs
    });

    await writeSecretOutput({ storageState: await context.storageState() });

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
      title: await safeTitle(page),
      status: response ? response.status() : null,
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

async function chromiumLaunchOptions(headed) {
  const executablePath = await chromiumExecutablePath();

  return {
    headless: !headed,
    args: ['--no-sandbox'],
    ...(executablePath ? { executablePath } : {})
  };
}

function browserContextOptions() {
  return {
    userAgent: process.env.GARDEN_PLAYWRIGHT_USER_AGENT || defaultUserAgent,
    locale: 'en-US',
    viewport: { width: 1280, height: 720 },
    extraHTTPHeaders: {
      'Accept-Language': 'en-US,en;q=0.9'
    }
  };
}

function ensureAllowedResponse(response, url) {
  if (response && response.status() === 403) {
    throw Object.assign(new Error(`BidNet returned HTTP 403 before login for ${new URL(url).origin}.`), {
      code: 'bidnet_forbidden'
    });
  }
}

async function safeTitle(page) {
  return await page.title().catch(() => null);
}

async function chromiumExecutablePath() {
  const configured = stringOrNull(
    process.env.GARDEN_PLAYWRIGHT_CHROMIUM_PATH || process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH
  );

  if (configured) {
    return configured;
  }

  const pathDirs = (process.env.PATH || '').split(path.delimiter).filter(Boolean);
  const binaries = ['chromium', 'chromium-browser', 'google-chrome', 'chrome'];

  for (const dir of pathDirs) {
    for (const binary of binaries) {
      const candidate = path.join(dir, binary);

      if (await executableExists(candidate)) {
        return candidate;
      }
    }
  }

  return null;
}

async function executableExists(candidate) {
  try {
    await fs.access(candidate, fsConstants.X_OK);
    return true;
  } catch (_error) {
    return false;
  }
}

async function ensureParentDir(filePath) {
  await fs.mkdir(path.dirname(filePath), { recursive: true, mode: 0o700 });
}

async function readJsonInput() {
  const payloadPath = process.env.GARDEN_PROCUREMENT_RUNNER_PAYLOAD_PATH;

  if (payloadPath) {
    const raw = await fs.readFile(payloadPath, 'utf8');
    return parseJsonPayload(raw);
  }

  return await readJsonStdin();
}

async function readSecretInput() {
  const secretPath = process.env.GARDEN_PROCUREMENT_RUNNER_SECRET_PATH;

  if (!secretPath) {
    return {};
  }

  const raw = await fs.readFile(secretPath, 'utf8');
  return parseJsonPayload(raw);
}

async function writeSecretOutput(value) {
  const outputPath = process.env.GARDEN_PROCUREMENT_RUNNER_SECRET_OUTPUT_PATH;

  if (!outputPath) {
    return;
  }

  await ensureParentDir(outputPath);
  await fs.writeFile(outputPath, JSON.stringify(value), { mode: 0o600 });
  await fs.chmod(outputPath, 0o600);
}

function deepMerge(publicValue, secretValue) {
  if (!publicValue || typeof publicValue !== 'object' || Array.isArray(publicValue)) {
    return secretValue;
  }

  if (!secretValue || typeof secretValue !== 'object' || Array.isArray(secretValue)) {
    return publicValue;
  }

  const merged = { ...publicValue };

  for (const [key, value] of Object.entries(secretValue)) {
    merged[key] = key in merged ? deepMerge(merged[key], value) : value;
  }

  return merged;
}

async function readJsonStdin() {
  const chunks = [];

  for await (const chunk of process.stdin) {
    chunks.push(chunk);
  }

  const raw = Buffer.concat(chunks).toString('utf8');
  return parseJsonPayload(raw);
}

function parseJsonPayload(raw) {
  return raw.trim() === '' ? {} : JSON.parse(raw);
}

function writeJson(value) {
  process.stdout.write(`${JSON.stringify(value)}\n`);
}
