import { test, expect } from '@playwright/test';
import { getToken } from '../helpers/auth';

const AUTHORING_URL = process.env.AUTHORING_URL || 'https://localhost:9081/fhir';

test.describe('Snapper Resource Visibility', () => {
  test('alpha-author sees Alpha CodeSystem but not Beta', async ({ page }) => {
    const token = await getToken('alpha-author');

    // Alpha CodeSystem should be visible
    const alphaResp = await page.request.get(
      `${AUTHORING_URL}/CodeSystem?url=${encodeURIComponent('http://pathology-alpha.example.com/CodeSystem/pathology-codes')}`,
      { headers: { Authorization: `Bearer ${token}`, Accept: 'application/fhir+json' } },
    );
    expect(alphaResp.status()).toBe(200);
    const alphaBundle = await alphaResp.json();
    expect(alphaBundle.total).toBe(1);

    // Beta CodeSystem should NOT be visible
    const betaResp = await page.request.get(
      `${AUTHORING_URL}/CodeSystem?url=${encodeURIComponent('http://pathology-beta.example.com/CodeSystem/pathology-codes')}`,
      { headers: { Authorization: `Bearer ${token}`, Accept: 'application/fhir+json' } },
    );
    expect(betaResp.status()).toBe(200);
    const betaBundle = await betaResp.json();
    expect(betaBundle.total).toBe(0);
  });

  test('beta-author sees Beta CodeSystem but not Alpha', async ({ page }) => {
    const token = await getToken('beta-author');

    const betaResp = await page.request.get(
      `${AUTHORING_URL}/CodeSystem?url=${encodeURIComponent('http://pathology-beta.example.com/CodeSystem/pathology-codes')}`,
      { headers: { Authorization: `Bearer ${token}`, Accept: 'application/fhir+json' } },
    );
    expect(betaResp.status()).toBe(200);
    expect((await betaResp.json()).total).toBe(1);

    const alphaResp = await page.request.get(
      `${AUTHORING_URL}/CodeSystem?url=${encodeURIComponent('http://pathology-alpha.example.com/CodeSystem/pathology-codes')}`,
      { headers: { Authorization: `Bearer ${token}`, Accept: 'application/fhir+json' } },
    );
    expect(alphaResp.status()).toBe(200);
    expect((await alphaResp.json()).total).toBe(0);
  });

  test('admin sees all CodeSystems', async ({ page }) => {
    const token = await getToken('admin');

    const resp = await page.request.get(
      `${AUTHORING_URL}/CodeSystem`,
      { headers: { Authorization: `Bearer ${token}`, Accept: 'application/fhir+json' } },
    );
    expect(resp.status()).toBe(200);
    const bundle = await resp.json();
    const urls = bundle.entry?.map((e: any) => e.resource?.url) || [];
    expect(urls).toContain('http://pathology-alpha.example.com/CodeSystem/pathology-codes');
    expect(urls).toContain('http://pathology-beta.example.com/CodeSystem/pathology-codes');
    expect(urls).toContain('http://pathology-gamma.example.com/CodeSystem/pathology-codes');
  });

  test('all users see the national valueset', async ({ page }) => {
    const token = await getToken('alpha-viewer');

    const resp = await page.request.get(
      `${AUTHORING_URL}/ValueSet?url=${encodeURIComponent('http://example.org/ValueSet/national-pathology-refset')}`,
      { headers: { Authorization: `Bearer ${token}`, Accept: 'application/fhir+json' } },
    );
    expect(resp.status()).toBe(200);
    expect((await resp.json()).total).toBe(1);
  });

  test('alpha-author sees ConceptMaps for Alpha only', async ({ page }) => {
    const token = await getToken('alpha-author');

    const alphaResp = await page.request.get(
      `${AUTHORING_URL}/ConceptMap?url=${encodeURIComponent('http://pathology-alpha.example.com/ConceptMap/pathology-to-national')}`,
      { headers: { Authorization: `Bearer ${token}`, Accept: 'application/fhir+json' } },
    );
    expect(alphaResp.status()).toBe(200);
    expect((await alphaResp.json()).total).toBe(1);

    const betaResp = await page.request.get(
      `${AUTHORING_URL}/ConceptMap?url=${encodeURIComponent('http://pathology-beta.example.com/ConceptMap/pathology-to-national')}`,
      { headers: { Authorization: `Bearer ${token}`, Accept: 'application/fhir+json' } },
    );
    expect(betaResp.status()).toBe(200);
    expect((await betaResp.json()).total).toBe(0);
  });

  test('beta-author sees ConceptMaps for Beta only', async ({ page }) => {
    const token = await getToken('beta-author');

    const betaResp = await page.request.get(
      `${AUTHORING_URL}/ConceptMap?url=${encodeURIComponent('http://pathology-beta.example.com/ConceptMap/pathology-to-national')}`,
      { headers: { Authorization: `Bearer ${token}`, Accept: 'application/fhir+json' } },
    );
    expect(betaResp.status()).toBe(200);
    expect((await betaResp.json()).total).toBe(1);

    const alphaResp = await page.request.get(
      `${AUTHORING_URL}/ConceptMap?url=${encodeURIComponent('http://pathology-alpha.example.com/ConceptMap/pathology-to-national')}`,
      { headers: { Authorization: `Bearer ${token}`, Accept: 'application/fhir+json' } },
    );
    expect(alphaResp.status()).toBe(200);
    expect((await alphaResp.json()).total).toBe(0);
  });

  test('admin sees all ConceptMaps', async ({ page }) => {
    const token = await getToken('admin');

    const resp = await page.request.get(
      `${AUTHORING_URL}/ConceptMap`,
      { headers: { Authorization: `Bearer ${token}`, Accept: 'application/fhir+json' } },
    );
    expect(resp.status()).toBe(200);
    const bundle = await resp.json();
    const urls = bundle.entry?.map((e: any) => e.resource?.url) || [];
    expect(urls).toContain('http://pathology-alpha.example.com/ConceptMap/pathology-to-national');
    expect(urls).toContain('http://pathology-beta.example.com/ConceptMap/pathology-to-national');
  });
});
