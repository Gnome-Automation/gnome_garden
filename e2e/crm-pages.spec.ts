import { test, expect } from '@playwright/test';

test.describe('CRM Pages', () => {
  test('companies page loads with table', async ({ page }) => {
    await page.goto('/crm/companies');

    // Page should load
    await expect(page).toHaveTitle(/Companies|Gnome Garden/);

    // Should have navigation sidebar
    await expect(page.locator('nav')).toBeVisible();

    // Should have Companies link in nav
    await expect(page.getByRole('link', { name: 'Companies' })).toBeVisible();

    // Should have Add Company button
    await expect(page.getByRole('link', { name: /Add Company/i })).toBeVisible();

    // Should have a table or loading state
    const table = page.locator('table');
    const loading = page.locator('.loading');
    await expect(table.or(loading)).toBeVisible();

    // Take screenshot
    await page.screenshot({ path: 'e2e/screenshots/companies.png', fullPage: true });
  });

  test('contacts page loads', async ({ page }) => {
    await page.goto('/crm/contacts');

    await expect(page.getByRole('link', { name: 'Contacts' })).toBeVisible();
    await expect(page.getByRole('link', { name: /Add Contact/i })).toBeVisible();

    await page.screenshot({ path: 'e2e/screenshots/contacts.png', fullPage: true });
  });

  test('opportunities page loads', async ({ page }) => {
    await page.goto('/crm/opportunities');

    await expect(page.getByRole('link', { name: 'Opportunities' })).toBeVisible();

    await page.screenshot({ path: 'e2e/screenshots/opportunities.png', fullPage: true });
  });

  test('leads page loads', async ({ page }) => {
    await page.goto('/crm/leads');

    await expect(page.getByRole('link', { name: 'Leads' })).toBeVisible();

    await page.screenshot({ path: 'e2e/screenshots/leads.png', fullPage: true });
  });

  test('tasks page loads', async ({ page }) => {
    await page.goto('/crm/tasks');

    await expect(page.getByRole('link', { name: 'Tasks' })).toBeVisible();

    await page.screenshot({ path: 'e2e/screenshots/tasks.png', fullPage: true });
  });

  test('navigation between pages works', async ({ page }) => {
    await page.goto('/crm/companies');
    await page.waitForLoadState('networkidle');

    // Click Contacts link in sidebar nav
    const contactsLink = page.locator('aside').getByRole('link', { name: 'Contacts' });
    await contactsLink.waitFor({ state: 'visible' });
    await contactsLink.click();
    await page.waitForURL(/.*contacts/, { timeout: 10000 });

    // Click Opportunities link
    const oppsLink = page.locator('aside').getByRole('link', { name: 'Opportunities' });
    await oppsLink.click();
    await page.waitForURL(/.*opportunities/, { timeout: 10000 });

    // Click back to Companies
    const companiesLink = page.locator('aside').getByRole('link', { name: 'Companies' });
    await companiesLink.click();
    await page.waitForURL(/.*companies/, { timeout: 10000 });
  });

  test('theme toggle works', async ({ page }) => {
    await page.goto('/crm/companies');

    // Find theme toggle buttons
    const darkButton = page.locator('button[data-phx-theme="dark"]');
    const lightButton = page.locator('button[data-phx-theme="light"]');

    // Click dark theme
    await darkButton.click();
    await page.waitForTimeout(500);
    await page.screenshot({ path: 'e2e/screenshots/companies-dark.png', fullPage: true });

    // Click light theme
    await lightButton.click();
    await page.waitForTimeout(500);
    await page.screenshot({ path: 'e2e/screenshots/companies-light.png', fullPage: true });
  });

  test('background has zinc hue', async ({ page }) => {
    await page.goto('/crm/companies');

    // Check main container has zinc-200 background
    const mainContainer = page.locator('.drawer');
    await expect(mainContainer).toHaveClass(/bg-zinc-200/);

    // Check sidebar has white background
    const sidebar = page.locator('aside');
    await expect(sidebar).toHaveClass(/bg-white/);
  });

  test('table loading spinner is small', async ({ page }) => {
    await page.goto('/crm/companies');

    // If loading spinner appears, it should be small (not full page)
    const loadingSpinner = page.locator('.loading-spinner');
    if (await loadingSpinner.isVisible()) {
      await expect(loadingSpinner).toHaveClass(/loading-sm/);
    }
  });
});

test.describe('Agents Pages', () => {
  test('bids page loads', async ({ page }) => {
    await page.goto('/agents/sales/bids');

    await expect(page.getByRole('link', { name: 'Bids' })).toBeVisible();

    await page.screenshot({ path: 'e2e/screenshots/bids.png', fullPage: true });
  });

  test('prospects page loads', async ({ page }) => {
    await page.goto('/agents/sales/prospects');

    await expect(page.getByRole('link', { name: 'Prospects' })).toBeVisible();

    await page.screenshot({ path: 'e2e/screenshots/prospects.png', fullPage: true });
  });

  test('lead sources page loads', async ({ page }) => {
    await page.goto('/agents/sales/lead-sources');

    await expect(page.getByRole('link', { name: 'Lead Sources' })).toBeVisible();

    await page.screenshot({ path: 'e2e/screenshots/lead-sources.png', fullPage: true });
  });
});
