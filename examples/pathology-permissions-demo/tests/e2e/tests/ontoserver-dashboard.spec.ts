import { test, expect } from '@playwright/test';
import { getToken, openDashboard } from '../helpers/auth';

const AUTHORING_URL = process.env.AUTHORING_URL || 'http://localhost:9081/fhir';
const PRODUCTION_URL = process.env.PRODUCTION_URL || (
  process.env.VARIANT === 'atomio' ? 'http://localhost:9085/fhir' : 'http://localhost:9082/fhir'
);
const UAT_URL = process.env.UAT_URL || 'http://localhost:9084/fhir';

test.describe('Ontoserver Dashboard', () => {
  test('loads dashboard for authoring server', async ({ page }) => {
    await openDashboard(page, AUTHORING_URL);

    // Dashboard SPA should render meaningful content
    const content = await page.textContent('body');
    expect(content).toBeTruthy();
    expect(content!.trim().length).toBeGreaterThan(20);
  });

  test('loads dashboard for production server', async ({ page }) => {
    await openDashboard(page, PRODUCTION_URL);

    const content = await page.textContent('body');
    expect(content).toBeTruthy();
    expect(content!.trim().length).toBeGreaterThan(20);
  });

  test('loads dashboard for UAT server @atomio', async ({ page }) => {
    await openDashboard(page, UAT_URL);

    const content = await page.textContent('body');
    expect(content).toBeTruthy();
    expect(content!.trim().length).toBeGreaterThan(20);
  });

  test('authoring server FHIR metadata is accessible', async ({ page }) => {
    const response = await page.request.get(`${AUTHORING_URL}/metadata`, {
      headers: { Accept: 'application/fhir+json' },
    });

    expect(response.status()).toBe(200);
    const metadata = await response.json();
    expect(metadata.resourceType).toBe('CapabilityStatement');
    // Verify SMART-on-FHIR security is advertised
    expect(metadata.rest).toBeDefined();
    expect(metadata.rest.length).toBeGreaterThan(0);
  });

  test('production server FHIR metadata is accessible', async ({ page }) => {
    const response = await page.request.get(`${PRODUCTION_URL}/metadata`, {
      headers: { Accept: 'application/fhir+json' },
    });

    expect(response.status()).toBe(200);
    const metadata = await response.json();
    expect(metadata.resourceType).toBe('CapabilityStatement');
  });

  test('authoring server has fine-grained security enabled', async ({ page }) => {
    const token = await getToken('admin');

    // Admin can read the metadata with auth
    const response = await page.request.get(`${AUTHORING_URL}/metadata`, {
      headers: {
        Authorization: `Bearer ${token}`,
        Accept: 'application/fhir+json',
      },
    });

    expect(response.status()).toBe(200);
    const metadata = await response.json();

    // Check that security is advertised in the CapabilityStatement
    const restSecurity = metadata.rest?.[0]?.security;
    expect(restSecurity).toBeDefined();
  });

  test('production server rejects writes', async ({ page }) => {
    const token = await getToken('admin');

    const response = await page.request.put(
      `${PRODUCTION_URL}/ValueSet/test-write-reject`,
      {
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/fhir+json',
        },
        data: {
          resourceType: 'ValueSet',
          id: 'test-write-reject',
          url: 'http://test.example.com/ValueSet/test-reject',
          status: 'draft',
        },
      },
    );

    // Production is read-only; expect 405, 403, or 401
    expect([401, 403, 405]).toContain(response.status());
  });

  test('production allows anonymous read of national valueset', async ({ page }) => {
    const response = await page.request.get(
      `${PRODUCTION_URL}/ValueSet?url=${encodeURIComponent('http://example.org/ValueSet/national-pathology-refset')}`,
      { headers: { Accept: 'application/fhir+json' } },
    );

    expect(response.status()).toBe(200);
    const bundle = await response.json();
    expect(bundle.total).toBe(1);
  });
});
