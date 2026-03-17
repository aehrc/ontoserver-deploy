import { test, expect } from '@playwright/test';
import { getToken, openSnapper, loginViaKeycloak, waitForSnapperReady } from '../helpers/auth';

const AUTHORING_URL = process.env.AUTHORING_URL || 'https://localhost:9081/fhir';

test.describe('Snapper Resource Editing', () => {
  test('alpha-author can open Alpha CodeSystem detail view', async ({ page }) => {
    await openSnapper(page, AUTHORING_URL);
    await waitForSnapperReady(page);
    await loginViaKeycloak(page, 'alpha-author');

    // Navigate to Code Systems
    await page.getByText('Code Systems').first().click();
    await page.waitForTimeout(2_000);
    await page.waitForLoadState('domcontentloaded');

    // Click on the Alpha CodeSystem
    await page.getByText('Pathology Alpha').first().click();
    await page.waitForTimeout(2_000);
    await page.waitForLoadState('domcontentloaded');

    // Should be able to see CodeSystem details (URL or concept codes)
    await expect(
      page.getByText('pathology-alpha.example.com')
        .or(page.getByText('pathology-codes'))
        .or(page.getByText('FBC')),
    ).toBeVisible({ timeout: 15_000 });
  });

  test('alpha-author can successfully write to own resources via API', async ({ page }) => {
    const token = await getToken('alpha-author');

    // Read the current resource first
    const readResponse = await page.request.get(
      `${AUTHORING_URL}/CodeSystem/alpha-pathology-codes`,
      { headers: { Authorization: `Bearer ${token}`, Accept: 'application/fhir+json' } },
    );
    expect(readResponse.status()).toBe(200);
    const original = await readResponse.json();

    // Write it back unchanged (safe non-destructive write test)
    const writeResponse = await page.request.put(
      `${AUTHORING_URL}/CodeSystem/alpha-pathology-codes`,
      {
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/fhir+json',
        },
        data: original,
      },
    );
    expect(writeResponse.status()).toBe(200);
  });

  test('alpha-viewer cannot modify resources via API', async ({ page }) => {
    const token = await getToken('alpha-viewer');

    const response = await page.request.put(
      `${AUTHORING_URL}/CodeSystem/alpha-pathology-codes`,
      {
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/fhir+json',
        },
        data: {
          resourceType: 'CodeSystem',
          id: 'alpha-pathology-codes',
          url: 'http://pathology-alpha.example.com/CodeSystem/pathology-codes',
          status: 'active',
          content: 'complete',
          concept: [{ code: 'HACK', display: 'Should Not Work' }],
        },
      },
    );

    // Should be rejected (403 Forbidden)
    expect(response.status()).toBe(403);
  });

  test('alpha-author cannot modify Beta resources via API', async ({ page }) => {
    const token = await getToken('alpha-author');

    const response = await page.request.put(
      `${AUTHORING_URL}/CodeSystem/beta-pathology-codes`,
      {
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/fhir+json',
        },
        data: {
          resourceType: 'CodeSystem',
          id: 'beta-pathology-codes',
          url: 'http://pathology-beta.example.com/CodeSystem/pathology-codes',
          status: 'active',
          content: 'complete',
          concept: [{ code: 'HACK', display: 'Cross-Community Hack' }],
        },
      },
    );

    expect([401, 403]).toContain(response.status());
  });

  test('beta-author can write to own resources via API', async ({ page }) => {
    const token = await getToken('beta-author');

    const readResponse = await page.request.get(
      `${AUTHORING_URL}/CodeSystem/beta-pathology-codes`,
      { headers: { Authorization: `Bearer ${token}`, Accept: 'application/fhir+json' } },
    );
    expect(readResponse.status()).toBe(200);
    const original = await readResponse.json();

    const writeResponse = await page.request.put(
      `${AUTHORING_URL}/CodeSystem/beta-pathology-codes`,
      {
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/fhir+json',
        },
        data: original,
      },
    );
    expect(writeResponse.status()).toBe(200);
  });

  test('beta-author cannot modify Alpha resources via API', async ({ page }) => {
    const token = await getToken('beta-author');

    const response = await page.request.put(
      `${AUTHORING_URL}/CodeSystem/alpha-pathology-codes`,
      {
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/fhir+json',
        },
        data: {
          resourceType: 'CodeSystem',
          id: 'alpha-pathology-codes',
          url: 'http://pathology-alpha.example.com/CodeSystem/pathology-codes',
          status: 'active',
          content: 'complete',
          concept: [{ code: 'HACK', display: 'Cross-Community Hack' }],
        },
      },
    );

    expect([401, 403]).toContain(response.status());
  });

  test('alpha-author can add a concept via API and verify', async ({ page }) => {
    // This test adds a concept via API (more reliable than UI selectors for
    // AngularJS apps) and verifies the concept appears in the CodeSystem.
    // It demonstrates the same authoring capability shown in the demo walkthrough.
    const token = await getToken('alpha-author');

    // Read current CodeSystem
    const readResponse = await page.request.get(
      `${AUTHORING_URL}/CodeSystem/alpha-pathology-codes`,
      {
        headers: {
          Authorization: `Bearer ${token}`,
          Accept: 'application/fhir+json',
        },
      },
    );
    expect(readResponse.status()).toBe(200);
    const cs = await readResponse.json();

    // Check if our test concept already exists (idempotent)
    const existingCodes = cs.concept?.map((c: any) => c.code) || [];
    if (existingCodes.includes('E2E-TEST')) {
      // Already added in a previous run — just verify it's there
      expect(existingCodes).toContain('E2E-TEST');
      return;
    }

    // Add a new concept
    cs.concept = cs.concept || [];
    cs.concept.push({
      code: 'E2E-TEST',
      display: 'E2E Test Concept',
      definition: 'Added by e2e test to verify authoring capability',
    });
    cs.count = cs.concept.length;

    // Write updated CodeSystem
    const writeResponse = await page.request.put(
      `${AUTHORING_URL}/CodeSystem/alpha-pathology-codes`,
      {
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/fhir+json',
        },
        data: cs,
      },
    );
    expect(writeResponse.status()).toBe(200);

    // Verify the concept was added
    const verifyResponse = await page.request.get(
      `${AUTHORING_URL}/CodeSystem/alpha-pathology-codes`,
      {
        headers: {
          Authorization: `Bearer ${token}`,
          Accept: 'application/fhir+json',
        },
      },
    );
    expect(verifyResponse.status()).toBe(200);
    const updated = await verifyResponse.json();
    const codes = updated.concept?.map((c: any) => c.code) || [];
    expect(codes).toContain('E2E-TEST');
  });
});
