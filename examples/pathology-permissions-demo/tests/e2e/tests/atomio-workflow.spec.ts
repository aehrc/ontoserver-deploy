import { test, expect } from '@playwright/test';

const ATOMIO_URL = process.env.ATOMIO_URL || 'http://localhost:9083';
const AUTHORING_INTERNAL_URL = 'http://authoring-ontoserver:8080';

// Unique feed name for this test run to avoid conflicts
const TEST_FEED = `e2e-test-${Date.now()}`;

test.describe('Atomio Release Workflow @atomio', () => {
  // Clean up test feed after all tests, even on failure
  test.afterAll(async ({ request }) => {
    await request.delete(`${ATOMIO_URL}/feed/${TEST_FEED}`).catch(() => {
      // Ignore errors — feed may not have been created
    });
  });

  test('clone creates a new feed from authoring syndication', async ({ page }) => {
    const response = await page.request.post(
      `${ATOMIO_URL}/feed/$clone?name=${TEST_FEED}&url=${encodeURIComponent(
        `${AUTHORING_INTERNAL_URL}/synd/syndication.xml`,
      )}`,
    );

    expect([200, 201]).toContain(response.status());
  });

  test('new feed appears in feed list', async ({ page }) => {
    const response = await page.request.get(`${ATOMIO_URL}/feed`, {
      headers: { Accept: 'application/json' },
    });

    expect(response.status()).toBe(200);
    const feeds = await response.json();
    const feedNames = feeds.map((f: { name: string }) => f.name);
    expect(feedNames).toContain(TEST_FEED);
  });

  test('alias can be updated to point to new feed', async ({ page }) => {
    // Save the current uat alias target for rollback
    const aliasResp = await page.request.get(`${ATOMIO_URL}/alias`, {
      headers: { Accept: 'application/json' },
    });
    const aliases = await aliasResp.json();
    const uatAlias = aliases.find((a: any) => a.aliasName === 'uat');
    const originalFeed = uatAlias?.feedName || 'release-1-0';

    try {
      // Point uat alias to the test feed
      const updateResp = await page.request.put(`${ATOMIO_URL}/alias/uat`, {
        headers: { 'Content-Type': 'application/json' },
        data: { aliasName: 'uat', feedName: TEST_FEED },
      });
      expect(updateResp.status()).toBe(200);

      // Verify the alias now points to the test feed
      const verifyResp = await page.request.get(`${ATOMIO_URL}/alias`, {
        headers: { Accept: 'application/json' },
      });
      const updatedAliases = await verifyResp.json();
      const updatedUat = updatedAliases.find((a: any) => a.aliasName === 'uat');
      expect(updatedUat?.feedName).toBe(TEST_FEED);
    } finally {
      // Rollback: restore original alias even if assertions fail
      await page.request.put(`${ATOMIO_URL}/alias/uat`, {
        headers: { 'Content-Type': 'application/json' },
        data: { aliasName: 'uat', feedName: originalFeed },
      });
    }
  });

  test('alias syndication XML is accessible', async ({ page }) => {
    const response = await page.request.get(
      `${ATOMIO_URL}/alias/uat/syndication.xml`,
      { headers: { Accept: 'application/xml' } },
    );

    expect(response.status()).toBe(200);
    const body = await response.text();
    expect(body).toContain('<feed');
  });

  test('aliases can point to different feeds simultaneously', async ({ page }) => {
    const response = await page.request.get(`${ATOMIO_URL}/alias`, {
      headers: { Accept: 'application/json' },
    });

    expect(response.status()).toBe(200);
    const aliases = await response.json();

    // Both uat and production aliases should exist
    const aliasNames = aliases.map((a: any) => a.aliasName);
    expect(aliasNames).toContain('uat');
    expect(aliasNames).toContain('production');

    // They are independent — can point to same or different feeds
    expect(aliases.length).toBeGreaterThanOrEqual(2);
  });
});
