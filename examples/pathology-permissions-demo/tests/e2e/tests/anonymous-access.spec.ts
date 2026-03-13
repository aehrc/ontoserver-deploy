import { test, expect } from '@playwright/test';

const PRODUCTION_URL = process.env.PRODUCTION_URL || (
  process.env.VARIANT === 'atomio' ? 'http://localhost:9085' : 'http://localhost:9082'
);

test.describe('Anonymous Access — Community Filtering', () => {
  test('anonymous cannot see Alpha CodeSystem on production', async ({ page }) => {
    const response = await page.request.get(
      `${PRODUCTION_URL}/fhir/CodeSystem?url=${encodeURIComponent(
        'http://pathology-alpha.example.com/CodeSystem/pathology-codes',
      )}`,
      { headers: { Accept: 'application/fhir+json' } },
    );

    expect(response.status()).toBe(200);
    const bundle = await response.json();
    expect(bundle.total).toBe(0);
  });

  test('anonymous cannot see Beta CodeSystem on production', async ({ page }) => {
    const response = await page.request.get(
      `${PRODUCTION_URL}/fhir/CodeSystem?url=${encodeURIComponent(
        'http://pathology-beta.example.com/CodeSystem/pathology-codes',
      )}`,
      { headers: { Accept: 'application/fhir+json' } },
    );

    expect(response.status()).toBe(200);
    const bundle = await response.json();
    expect(bundle.total).toBe(0);
  });

  test('anonymous cannot see Gamma CodeSystem on production', async ({ page }) => {
    const response = await page.request.get(
      `${PRODUCTION_URL}/fhir/CodeSystem?url=${encodeURIComponent(
        'http://pathology-gamma.example.com/CodeSystem/pathology-codes',
      )}`,
      { headers: { Accept: 'application/fhir+json' } },
    );

    expect(response.status()).toBe(200);
    const bundle = await response.json();
    expect(bundle.total).toBe(0);
  });
});
