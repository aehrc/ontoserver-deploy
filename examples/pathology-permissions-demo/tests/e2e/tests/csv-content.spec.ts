import { test, expect } from '@playwright/test';
import { getToken } from '../helpers/auth';

const AUTHORING_URL = process.env.AUTHORING_URL || 'https://localhost:9081/fhir';

const GAMMA_CS_URL = 'http://pathology-gamma.example.com/CodeSystem/pathology-codes';

test.describe('CSV Content — Gamma Pathology', () => {
  test('admin sees Gamma CodeSystem on authoring', async ({ page }) => {
    const token = await getToken('admin');

    const response = await page.request.get(
      `${AUTHORING_URL}/CodeSystem?url=${encodeURIComponent(GAMMA_CS_URL)}`,
      {
        headers: {
          Authorization: `Bearer ${token}`,
          Accept: 'application/fhir+json',
        },
      },
    );

    expect(response.status()).toBe(200);
    const bundle = await response.json();
    expect(bundle.total).toBe(1);
  });

  test('Gamma CodeSystem has correct security labels', async ({ page }) => {
    const token = await getToken('admin');

    const response = await page.request.get(
      `${AUTHORING_URL}/CodeSystem?url=${encodeURIComponent(GAMMA_CS_URL)}`,
      {
        headers: {
          Authorization: `Bearer ${token}`,
          Accept: 'application/fhir+json',
        },
      },
    );

    expect(response.status()).toBe(200);
    const bundle = await response.json();
    const cs = bundle.entry?.[0]?.resource;
    expect(cs).toBeDefined();

    const securityCodes = cs.meta?.security?.map((s: any) => s.code) || [];
    expect(securityCodes).toContain('GAMMA.read');
    expect(securityCodes).toContain('GAMMA.write');
  });

  test('Gamma CodeSystem has expected concept count', async ({ page }) => {
    const token = await getToken('admin');

    const response = await page.request.get(
      `${AUTHORING_URL}/CodeSystem?url=${encodeURIComponent(GAMMA_CS_URL)}`,
      {
        headers: {
          Authorization: `Bearer ${token}`,
          Accept: 'application/fhir+json',
        },
      },
    );

    expect(response.status()).toBe(200);
    const bundle = await response.json();
    const cs = bundle.entry?.[0]?.resource;
    expect(cs).toBeDefined();

    // CSV has 15 concepts
    expect(cs.count).toBe(15);
  });

  test('alpha user cannot see Gamma CodeSystem (community isolation)', async ({ page }) => {
    const token = await getToken('alpha-author');

    const response = await page.request.get(
      `${AUTHORING_URL}/CodeSystem?url=${encodeURIComponent(GAMMA_CS_URL)}`,
      {
        headers: {
          Authorization: `Bearer ${token}`,
          Accept: 'application/fhir+json',
        },
      },
    );

    expect(response.status()).toBe(200);
    const bundle = await response.json();
    expect(bundle.total).toBe(0);
  });
});
