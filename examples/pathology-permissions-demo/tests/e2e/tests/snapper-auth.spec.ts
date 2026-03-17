import { test, expect } from '@playwright/test';
import { openSnapper, loginViaKeycloak, logout, waitForSnapperReady } from '../helpers/auth';

const AUTHORING_URL = process.env.AUTHORING_URL || 'http://localhost:9081/fhir';
const PRODUCTION_URL = process.env.PRODUCTION_URL || (
  process.env.VARIANT === 'atomio' ? 'http://localhost:9085/fhir' : 'http://localhost:9082/fhir'
);

test.describe('Snapper Authentication', () => {
  test('loads Snapper with iss parameter for authoring', async ({ page }) => {
    await openSnapper(page, AUTHORING_URL);
    await waitForSnapperReady(page);
  });

  test('loads Snapper with iss parameter for production', async ({ page }) => {
    await openSnapper(page, PRODUCTION_URL);
    await waitForSnapperReady(page);
  });

  test('can log in as alpha-author', async ({ page }) => {
    await openSnapper(page, AUTHORING_URL);
    await waitForSnapperReady(page);
    await loginViaKeycloak(page, 'alpha-author');

    // After login, should see logout option or username
    await expect(
      page.getByText(/logout|sign out|alpha-author/i).first(),
    ).toBeVisible({ timeout: 10_000 });
  });

  test('can log in as beta-author', async ({ page }) => {
    await openSnapper(page, AUTHORING_URL);
    await waitForSnapperReady(page);
    await loginViaKeycloak(page, 'beta-author');

    await expect(
      page.getByText(/logout|sign out|beta-author/i).first(),
    ).toBeVisible({ timeout: 10_000 });
  });

  test('can log in as admin', async ({ page }) => {
    await openSnapper(page, AUTHORING_URL);
    await waitForSnapperReady(page);
    await loginViaKeycloak(page, 'admin');

    await expect(
      page.getByText(/logout|sign out|admin/i).first(),
    ).toBeVisible({ timeout: 10_000 });
  });

  test('can log out after login', async ({ page }) => {
    await openSnapper(page, AUTHORING_URL);
    await waitForSnapperReady(page);
    await loginViaKeycloak(page, 'alpha-author');

    // Verify logged in
    await expect(
      page.getByText(/logout|sign out/i).first(),
    ).toBeVisible({ timeout: 10_000 });

    // Log out
    await logout(page);

    // Login button should reappear
    await expect(
      page.getByText(/login|sign in/i).first(),
    ).toBeVisible({ timeout: 10_000 });
  });
});
