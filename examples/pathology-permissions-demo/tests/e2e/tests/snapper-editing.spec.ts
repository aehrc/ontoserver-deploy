import { test, expect } from '@playwright/test';
import { getToken, openSnapper, loginViaKeycloak, waitForSnapperReady } from '../helpers/auth';

const AUTHORING_URL = process.env.AUTHORING_URL || 'https://localhost:9081/fhir';

test.describe('Snapper Resource Editing', () => {
  test('alpha-author can read Alpha CodeSystem details via API', async ({ page }) => {
    const token = await getToken('alpha-author');

    const resp = await page.request.get(
      `${AUTHORING_URL}/CodeSystem/alpha-pathology-codes`,
      { headers: { Authorization: `Bearer ${token}`, Accept: 'application/fhir+json' } },
    );
    expect(resp.status()).toBe(200);
    const cs = await resp.json();
    expect(cs.resourceType).toBe('CodeSystem');
    expect(cs.url).toBe('http://pathology-alpha.example.com/CodeSystem/pathology-codes');
    expect(cs.concept?.length).toBeGreaterThan(0);
  });

  test('alpha-author can successfully write to own resources via API', async ({ page }) => {
    const token = await getToken('alpha-author');

    // Existing CodeSystems are syndicated (secureSyndicated=true), so authors
    // can't modify them without SYND_WRITE. Test write by creating a new resource.
    const testId = `alpha-write-test-${Date.now()}`;
    const writeResponse = await page.request.put(
      `${AUTHORING_URL}/CodeSystem/${testId}`,
      {
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/fhir+json',
        },
        data: {
          resourceType: 'CodeSystem',
          id: testId,
          url: 'http://pathology-alpha.example.com/CodeSystem/write-test',
          status: 'draft',
          content: 'complete',
          concept: [{ code: 'TEST', display: 'Test' }],
          meta: { security: [{ code: 'ALPHA.read' }, { code: 'ALPHA.write' }] },
        },
      },
    );
    expect([200, 201]).toContain(writeResponse.status());

    // Clean up
    await page.request.delete(`${AUTHORING_URL}/CodeSystem/${testId}`, {
      headers: { Authorization: `Bearer ${token}` },
    });
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

    const testId = `beta-write-test-${Date.now()}`;
    const writeResponse = await page.request.put(
      `${AUTHORING_URL}/CodeSystem/${testId}`,
      {
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/fhir+json',
        },
        data: {
          resourceType: 'CodeSystem',
          id: testId,
          url: 'http://pathology-beta.example.com/CodeSystem/write-test',
          status: 'draft',
          content: 'complete',
          concept: [{ code: 'TEST', display: 'Test' }],
          meta: { security: [{ code: 'BETA.read' }, { code: 'BETA.write' }] },
        },
      },
    );
    expect([200, 201]).toContain(writeResponse.status());

    // Clean up
    await page.request.delete(`${AUTHORING_URL}/CodeSystem/${testId}`, {
      headers: { Authorization: `Bearer ${token}` },
    });
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

  test('alpha-author can create a CodeSystem with concepts and verify', async ({ page }) => {
    // Creates a new CodeSystem (not syndicated), verifies the concepts appear,
    // then cleans up. This demonstrates authoring capability without conflicting
    // with secureSyndicated protection on existing resources.
    const token = await getToken('alpha-author');
    const testId = `alpha-concept-test-${Date.now()}`;

    const writeResponse = await page.request.put(
      `${AUTHORING_URL}/CodeSystem/${testId}`,
      {
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/fhir+json',
        },
        data: {
          resourceType: 'CodeSystem',
          id: testId,
          url: 'http://pathology-alpha.example.com/CodeSystem/concept-test',
          status: 'draft',
          content: 'complete',
          count: 2,
          concept: [
            { code: 'E2E-TEST', display: 'E2E Test Concept', definition: 'Added by e2e test' },
            { code: 'E2E-VERIFY', display: 'Verify Concept' },
          ],
          meta: { security: [{ code: 'ALPHA.read' }, { code: 'ALPHA.write' }] },
        },
      },
    );
    expect([200, 201]).toContain(writeResponse.status());

    // Verify the concepts exist
    const verifyResponse = await page.request.get(
      `${AUTHORING_URL}/CodeSystem/${testId}`,
      {
        headers: {
          Authorization: `Bearer ${token}`,
          Accept: 'application/fhir+json',
        },
      },
    );
    expect(verifyResponse.status()).toBe(200);
    const cs = await verifyResponse.json();
    const codes = cs.concept?.map((c: any) => c.code) || [];
    expect(codes).toContain('E2E-TEST');
    expect(codes).toContain('E2E-VERIFY');

    // Clean up
    await page.request.delete(`${AUTHORING_URL}/CodeSystem/${testId}`, {
      headers: { Authorization: `Bearer ${token}` },
    });
  });
});
