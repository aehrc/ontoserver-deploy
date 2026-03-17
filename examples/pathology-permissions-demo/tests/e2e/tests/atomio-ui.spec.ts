import { test, expect } from '@playwright/test';
import { openAtomioUI } from '../helpers/auth';

const ATOMIO_URL = process.env.ATOMIO_URL || 'https://localhost:9083';

test.describe('Atomio UI @atomio', () => {
  test('loads Atomio UI with iss parameter', async ({ page }) => {
    await openAtomioUI(page, ATOMIO_URL);

    // Atomio UI is a JavaScript SPA - verify it rendered meaningful content
    const content = await page.textContent('body');
    expect(content).toBeTruthy();
    // Should have rendered some text beyond just a loading spinner
    expect(content!.trim().length).toBeGreaterThan(20);
  });

  test('shows feeds list', async ({ page }) => {
    await openAtomioUI(page, ATOMIO_URL);

    // Look for feed names created during setup
    await expect(
      page.getByText('release-1-0').or(page.getByText('release')).first(),
    ).toBeVisible({ timeout: 20_000 });
  });

  test('shows aliases', async ({ page }) => {
    await openAtomioUI(page, ATOMIO_URL);

    // Look for alias names - check for either one
    await expect(
      page.getByText('uat').or(page.getByText('production')).first(),
    ).toBeVisible({ timeout: 20_000 });
  });

  test('Atomio API returns feeds in JSON', async ({ page }) => {
    const response = await page.request.get(`${ATOMIO_URL}/feed`, {
      headers: { Accept: 'application/json' },
    });

    expect(response.status()).toBe(200);
    const feeds = await response.json();
    expect(Array.isArray(feeds)).toBe(true);

    const feedNames = feeds.map((f: { name: string }) => f.name);
    expect(feedNames).toContain('release-1-0');
  });

  test('Atomio API returns aliases in JSON', async ({ page }) => {
    const response = await page.request.get(`${ATOMIO_URL}/alias`, {
      headers: { Accept: 'application/json' },
    });

    expect(response.status()).toBe(200);
    const aliases = await response.json();
    expect(Array.isArray(aliases)).toBe(true);

    const aliasNames = aliases.map((a: { aliasName: string }) => a.aliasName);
    expect(aliasNames).toContain('uat');
    expect(aliasNames).toContain('production');
  });

  test('Atomio syndication feed accessible via alias', async ({ page }) => {
    const response = await page.request.get(
      `${ATOMIO_URL}/alias/uat/syndication.xml`,
      { headers: { Accept: 'application/xml' } },
    );

    expect(response.status()).toBe(200);
    const body = await response.text();
    expect(body).toContain('<feed');
  });

  test('Atomio responds with HTML when Accept header requests it', async ({ page }) => {
    const response = await page.request.get(ATOMIO_URL, {
      headers: { Accept: 'text/html' },
    });

    // Atomio serves its UI when HTML is requested at root
    expect(response.status()).toBe(200);
    const body = await response.text();
    expect(body).toContain('<');
  });
});
