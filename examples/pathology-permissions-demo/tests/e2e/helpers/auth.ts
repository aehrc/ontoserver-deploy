import { Page, expect } from '@playwright/test';

/**
 * Get a bearer token for a demo user via direct access grant.
 */
export async function getToken(
  page: Page,
  username: string,
  password: string = 'demo',
): Promise<string> {
  const ontocloakUrl = process.env.ONTOCLOAK_URL || 'http://localhost:9090';
  const realm = 'pathology-demo';

  const response = await page.request.post(
    `${ontocloakUrl}/auth/realms/${realm}/protocol/openid-connect/token`,
    {
      form: {
        grant_type: 'password',
        client_id: 'demo-cli',
        username,
        password,
      },
    },
  );

  const body = await response.json();
  if (!body.access_token) {
    throw new Error(`Failed to get token for ${username}: ${JSON.stringify(body)}`);
  }
  return body.access_token;
}

/**
 * Log in to Snapper via the Ontocloak login page.
 *
 * Snapper uses SMART-on-FHIR which redirects to Ontocloak.
 * This helper fills in the login form and waits for the redirect back.
 */
export async function snapperLogin(
  page: Page,
  username: string,
  password: string = 'demo',
): Promise<void> {
  // Snapper's login button - try multiple selector strategies
  const loginButton = page.getByRole('button', { name: /login|sign in|authorize/i })
    .or(page.getByRole('link', { name: /login|sign in|authorize/i }))
    .or(page.locator('[ng-click*="login"]'));
  await loginButton.first().click();

  // Wait for redirect to Ontocloak login page
  // Ontocloak may use /auth/realms/... or /realms/... depending on version
  await page.waitForURL(/.*\/realms\/pathology-demo\/protocol\/openid-connect\/auth.*/, {
    timeout: 15_000,
  });

  // Fill in credentials on the Keycloak/Ontocloak login form
  await page.locator('#username').fill(username);
  await page.locator('#password').fill(password);
  await page.locator('#kc-login').click();

  // Wait for redirect back to Snapper
  await page.waitForURL(/.*ontoserver\.csiro\.au\/snapper.*/, {
    timeout: 15_000,
  });

  // Wait for Snapper to finish loading after auth
  await page.waitForTimeout(2_000);
  await page.waitForLoadState('domcontentloaded');
}

/**
 * Log out of Snapper.
 */
export async function snapperLogout(page: Page): Promise<void> {
  const logoutButton = page.getByRole('button', { name: /logout|sign out/i })
    .or(page.getByRole('link', { name: /logout|sign out/i }))
    .or(page.locator('[ng-click*="logout"]'));
  if (await logoutButton.first().isVisible({ timeout: 3_000 }).catch(() => false)) {
    await logoutButton.first().click();
    await page.waitForTimeout(1_000);
    await page.waitForLoadState('domcontentloaded');
  }
}

/**
 * Navigate to Snapper connected to a specific FHIR server.
 */
export async function openSnapper(page: Page, fhirServerUrl: string): Promise<void> {
  const snapperBase = 'https://ontoserver.csiro.au/snapper';
  await page.goto(`${snapperBase}?iss=${encodeURIComponent(fhirServerUrl)}`);
  await page.waitForLoadState('domcontentloaded');
  // Give AngularJS time to bootstrap and render
  await page.waitForTimeout(3_000);
}

/**
 * Navigate to the Ontoserver Dashboard connected to a specific server.
 */
export async function openDashboard(page: Page, fhirServerUrl: string): Promise<void> {
  const dashboardBase = 'https://ontoserver.csiro.au/ui';
  await page.goto(`${dashboardBase}?iss=${encodeURIComponent(fhirServerUrl)}`);
  await page.waitForLoadState('domcontentloaded');
  await page.waitForTimeout(3_000);
}

/**
 * Navigate to the Atomio UI connected to a specific Atomio instance.
 */
export async function openAtomioUI(page: Page, atomioUrl: string): Promise<void> {
  const atomioUiBase = 'https://ontoserver.csiro.au/atomio/';
  await page.goto(`${atomioUiBase}?iss=${encodeURIComponent(atomioUrl)}`);
  await page.waitForLoadState('domcontentloaded');
  await page.waitForTimeout(3_000);
}

/**
 * Wait for Snapper to show a navigation tab (Code Systems, Value Sets, etc.)
 * This confirms the app has bootstrapped and connected to the FHIR server.
 */
export async function waitForSnapperReady(page: Page): Promise<void> {
  await expect(
    page.getByText('Code Systems')
      .or(page.getByText('Value Sets'))
      .or(page.getByText('Concept Maps')),
  ).toBeVisible({ timeout: 20_000 });
}

/**
 * Navigate to Shrimp connected to a specific FHIR server.
 */
export async function openShrimp(page: Page, fhirServerUrl: string): Promise<void> {
  const shrimpBase = 'https://ontoserver.csiro.au/shrimp';
  await page.goto(`${shrimpBase}?iss=${encodeURIComponent(fhirServerUrl)}`);
  await page.waitForLoadState('domcontentloaded');
  // Give AngularJS time to bootstrap and render
  await page.waitForTimeout(3_000);
}

/**
 * Wait for Shrimp to show its main navigation (Code Systems tab, etc.)
 * This confirms the app has bootstrapped and connected to the FHIR server.
 */
export async function waitForShrimpReady(page: Page): Promise<void> {
  await expect(
    page.getByText('Code Systems')
      .or(page.getByText('Value Sets'))
      .or(page.getByText('Concept Maps')),
  ).toBeVisible({ timeout: 20_000 });
}

/**
 * Log in to Shrimp via the Ontocloak login page.
 *
 * Shrimp uses SMART-on-FHIR which redirects to Ontocloak (same as Snapper).
 * This helper fills in the login form and waits for the redirect back.
 */
export async function shrimpLogin(
  page: Page,
  username: string,
  password: string = 'demo',
): Promise<void> {
  // Shrimp's login button — try multiple selector strategies
  const loginButton = page.getByRole('button', { name: /login|sign in|authorize/i })
    .or(page.getByRole('link', { name: /login|sign in|authorize/i }))
    .or(page.locator('[ng-click*="login"]'));
  await loginButton.first().click();

  // Wait for redirect to Ontocloak login page
  await page.waitForURL(/.*\/realms\/pathology-demo\/protocol\/openid-connect\/auth.*/, {
    timeout: 15_000,
  });

  // Fill in credentials on the Keycloak/Ontocloak login form
  await page.locator('#username').fill(username);
  await page.locator('#password').fill(password);
  await page.locator('#kc-login').click();

  // Wait for redirect back to Shrimp
  await page.waitForURL(/.*ontoserver\.csiro\.au\/shrimp.*/, {
    timeout: 15_000,
  });

  // Wait for Shrimp to finish loading after auth
  await page.waitForTimeout(2_000);
  await page.waitForLoadState('domcontentloaded');
}

/**
 * Log out of Shrimp.
 */
export async function shrimpLogout(page: Page): Promise<void> {
  const logoutButton = page.getByRole('button', { name: /logout|sign out/i })
    .or(page.getByRole('link', { name: /logout|sign out/i }))
    .or(page.locator('[ng-click*="logout"]'));
  if (await logoutButton.first().isVisible({ timeout: 3_000 }).catch(() => false)) {
    await logoutButton.first().click();
    await page.waitForTimeout(1_000);
    await page.waitForLoadState('domcontentloaded');
  }
}
