import { test, expect } from '@playwright/test';
import { getToken } from '../helpers/auth';

const AUTHORING_URL = process.env.AUTHORING_URL || 'https://localhost:9081/fhir';
const PRODUCTION_URL = process.env.PRODUCTION_URL || (
  process.env.VARIANT === 'atomio' ? 'https://localhost:9085/fhir' : 'https://localhost:9082/fhir'
);

test.describe('Syndication — Authoring to Production', () => {
  test('admin sees all CodeSystems on authoring', async ({ page }) => {
    const token = await getToken('admin');

    const response = await page.request.get(`${AUTHORING_URL}/CodeSystem`, {
      headers: {
        Authorization: `Bearer ${token}`,
        Accept: 'application/fhir+json',
      },
    });

    expect(response.status()).toBe(200);
    const bundle = await response.json();

    // Admin should see at least Alpha, Beta, Gamma CodeSystems
    const urls = bundle.entry?.map((e: any) => e.resource?.url) || [];
    expect(urls).toContain('http://pathology-alpha.example.com/CodeSystem/pathology-codes');
    expect(urls).toContain('http://pathology-beta.example.com/CodeSystem/pathology-codes');
    expect(urls).toContain('http://pathology-gamma.example.com/CodeSystem/pathology-codes');
  });

  test('alpha user sees Alpha CodeSystem on production (syndicated)', async ({ page }) => {
    const token = await getToken('alpha-viewer');

    const response = await page.request.get(
      `${PRODUCTION_URL}/CodeSystem?url=${encodeURIComponent(
        'http://pathology-alpha.example.com/CodeSystem/pathology-codes',
      )}`,
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

  test('alpha user cannot see Beta CodeSystem on production (labels preserved)', async ({ page }) => {
    const token = await getToken('alpha-viewer');

    const response = await page.request.get(
      `${PRODUCTION_URL}/CodeSystem?url=${encodeURIComponent(
        'http://pathology-beta.example.com/CodeSystem/pathology-codes',
      )}`,
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

  test('national valueset exists on both authoring and production', async ({ page }) => {
    const nationalUrl = encodeURIComponent('http://example.org/ValueSet/national-pathology-refset');

    // Check authoring (needs auth since no readOnly.fhir)
    const token = await getToken('alpha-viewer');
    const authoringResp = await page.request.get(
      `${AUTHORING_URL}/ValueSet?url=${nationalUrl}`,
      {
        headers: {
          Authorization: `Bearer ${token}`,
          Accept: 'application/fhir+json',
        },
      },
    );
    expect(authoringResp.status()).toBe(200);
    const authoringBundle = await authoringResp.json();
    expect(authoringBundle.total).toBe(1);

    // Check production (anonymous works due to readOnly.fhir + *.read label)
    const prodResp = await page.request.get(
      `${PRODUCTION_URL}/ValueSet?url=${nationalUrl}`,
      { headers: { Accept: 'application/fhir+json' } },
    );
    expect(prodResp.status()).toBe(200);
    const prodBundle = await prodResp.json();
    expect(prodBundle.total).toBe(1);
  });
});
