import { test, expect } from '@playwright/test';
import { openSnapper, loginViaKeycloak, waitForSnapperReady } from '../helpers/auth';

const AUTHORING_URL = process.env.AUTHORING_URL || 'http://localhost:9081/fhir';

test.describe('Snapper Resource Visibility', () => {
  test('alpha-author sees Alpha CodeSystem but not Beta', async ({ page }) => {
    await openSnapper(page, AUTHORING_URL);
    await waitForSnapperReady(page);
    await loginViaKeycloak(page, 'alpha-author');

    // Navigate to Code Systems section
    await page.getByText('Code Systems').first().click();
    await page.waitForTimeout(2_000);
    await page.waitForLoadState('domcontentloaded');

    // Should see Alpha's CodeSystem
    await expect(page.getByText('Pathology Alpha').first()).toBeVisible({ timeout: 15_000 });

    // Should NOT see Beta's CodeSystem
    await expect(page.getByText('Pathology Beta')).not.toBeVisible();
  });

  test('beta-author sees Beta CodeSystem but not Alpha', async ({ page }) => {
    await openSnapper(page, AUTHORING_URL);
    await waitForSnapperReady(page);
    await loginViaKeycloak(page, 'beta-author');

    await page.getByText('Code Systems').first().click();
    await page.waitForTimeout(2_000);
    await page.waitForLoadState('domcontentloaded');

    // Should see Beta's CodeSystem
    await expect(page.getByText('Pathology Beta').first()).toBeVisible({ timeout: 15_000 });

    // Should NOT see Alpha's CodeSystem
    await expect(page.getByText('Pathology Alpha')).not.toBeVisible();
  });

  test('admin sees all CodeSystems', async ({ page }) => {
    await openSnapper(page, AUTHORING_URL);
    await waitForSnapperReady(page);
    await loginViaKeycloak(page, 'admin');

    await page.getByText('Code Systems').first().click();
    await page.waitForTimeout(2_000);
    await page.waitForLoadState('domcontentloaded');

    // Admin should see all providers' CodeSystems
    await expect(page.getByText('Pathology Alpha').first()).toBeVisible({ timeout: 15_000 });
    await expect(page.getByText('Pathology Beta').first()).toBeVisible({ timeout: 15_000 });
    await expect(page.getByText('Pathology Gamma').first()).toBeVisible({ timeout: 15_000 });
  });

  test('all users see the national valueset', async ({ page }) => {
    await openSnapper(page, AUTHORING_URL);
    await waitForSnapperReady(page);
    await loginViaKeycloak(page, 'alpha-viewer');

    await page.getByText('Value Sets').first().click();
    await page.waitForTimeout(2_000);
    await page.waitForLoadState('domcontentloaded');

    // Should see the national valueset
    await expect(
      page.getByText('National Pathology').first(),
    ).toBeVisible({ timeout: 15_000 });
  });

  test('alpha-author sees ConceptMaps for Alpha only', async ({ page }) => {
    await openSnapper(page, AUTHORING_URL);
    await waitForSnapperReady(page);
    await loginViaKeycloak(page, 'alpha-author');

    await page.getByText('Concept Maps').first().click();
    await page.waitForTimeout(2_000);
    await page.waitForLoadState('domcontentloaded');

    // Should see Alpha's mapping (check for specific URL substring to avoid matching username)
    await expect(
      page.getByText('pathology-alpha').first(),
    ).toBeVisible({ timeout: 15_000 });

    // Should NOT see Beta's mapping
    await expect(page.getByText('pathology-beta')).not.toBeVisible();
  });

  test('beta-author sees ConceptMaps for Beta only', async ({ page }) => {
    await openSnapper(page, AUTHORING_URL);
    await waitForSnapperReady(page);
    await loginViaKeycloak(page, 'beta-author');

    await page.getByText('Concept Maps').first().click();
    await page.waitForTimeout(2_000);
    await page.waitForLoadState('domcontentloaded');

    // Should see Beta's mapping
    await expect(
      page.getByText('pathology-beta').first(),
    ).toBeVisible({ timeout: 15_000 });

    // Should NOT see Alpha's mapping
    await expect(page.getByText('pathology-alpha')).not.toBeVisible();
  });

  test('admin sees all ConceptMaps', async ({ page }) => {
    await openSnapper(page, AUTHORING_URL);
    await waitForSnapperReady(page);
    await loginViaKeycloak(page, 'admin');

    await page.getByText('Concept Maps').first().click();
    await page.waitForTimeout(2_000);
    await page.waitForLoadState('domcontentloaded');

    await expect(page.getByText('pathology-alpha').first()).toBeVisible({ timeout: 15_000 });
    await expect(page.getByText('pathology-beta').first()).toBeVisible({ timeout: 15_000 });
  });
});
