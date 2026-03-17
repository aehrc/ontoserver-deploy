import { Page, expect, request as playwrightRequest } from '@playwright/test';

// ---------------------------------------------------------------------------
// Licence Agreement
// ---------------------------------------------------------------------------

/**
 * Accept the SNOMED CT licence agreement if presented.
 * Shrimp shows a simple button; Snapper requires checking 3 boxes first.
 * After acceptance, waits for the redirect back to the main app.
 */
async function acceptLicenceAgreement(page: Page): Promise<void> {
  const acceptButton = page.getByRole('button', { name: /I accept the licence conditions/i });
  if (await acceptButton.isVisible({ timeout: 2_000 }).catch(() => false)) {
    // Snapper has checkboxes that must be checked before the accept button works
    const checkboxes = await page.locator('input[type=checkbox]').all();
    for (const cb of checkboxes) {
      await cb.check();
    }

    const urlBefore = page.url();
    await acceptButton.click();

    // Wait for redirect away from the licence page
    if (urlBefore.includes('licence')) {
      await page.waitForURL((url) => !url.href.includes('licence'), {
        timeout: 15_000,
      }).catch(() => {});
    }

    await page.waitForLoadState('domcontentloaded');
    await page.waitForTimeout(2_000);
  }
}

// ---------------------------------------------------------------------------
// Keycloak SMART-on-FHIR Login / Logout
// ---------------------------------------------------------------------------

/**
 * Get a bearer token for a demo user via direct access grant.
 * Uses Playwright's standalone request context (Node-level HTTP, no browser
 * security restrictions) to avoid CORS / mixed-content / PNA issues.
 */
export async function getToken(
  username: string,
  password: string = 'demo',
): Promise<string> {
  const ontocloakUrl = process.env.ONTOCLOAK_URL || 'https://localhost:9090';
  const realm = 'pathology-demo';

  const context = await playwrightRequest.newContext({ ignoreHTTPSErrors: true });
  try {
    const response = await context.post(
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
  } finally {
    await context.dispose();
  }
}

/**
 * Log in via Keycloak using the app's SMART-on-FHIR login flow.
 * Clicks the login button in the current app (Shrimp or Snapper),
 * fills the Keycloak login form, and waits for the redirect back.
 *
 * The app must already be loaded and showing its Login button.
 */
export async function loginViaKeycloak(
  page: Page,
  username: string,
  password: string = 'demo',
  fhirServerUrl?: string,
): Promise<void> {
  // Click the login button — each UI has a different element:
  //   Shrimp:    <a id="fhir-server-login">
  //   Snapper:   <button id="toggle-login-btn">
  //   Atomio UI: button/link with text "Login"
  const shrimpLogin = page.locator('#fhir-server-login');
  const snapperLogin = page.locator('#toggle-login-btn');
  const atomioLogin = page.getByRole('button', { name: 'Login' }).or(
    page.getByRole('link', { name: 'Login' }),
  );

  const isShrimp = await shrimpLogin.isVisible({ timeout: 3_000 }).catch(() => false);

  if (isShrimp) {
    await shrimpLogin.click();
  } else if (await snapperLogin.isVisible({ timeout: 3_000 }).catch(() => false)) {
    await snapperLogin.click();

    // Snapper shows a confirmation modal "Confirm FHIR Server Login?"
    // with Cancel/Login buttons — click the Login button to proceed
    const modalLogin = page.locator('.modal-footer button.btn-success');
    await modalLogin.waitFor({ state: 'visible', timeout: 5_000 });
    await modalLogin.click();
  } else if (await atomioLogin.first().isVisible({ timeout: 3_000 }).catch(() => false)) {
    await atomioLogin.first().click();
  } else {
    throw new Error('No login button found on page');
  }

  // Wait for Keycloak login page to load
  await page.waitForURL(/localhost:9090/, { timeout: 15_000 });
  await page.waitForLoadState('domcontentloaded');
  await page.waitForTimeout(1_000);

  // Fill in credentials and submit
  await page.locator('#username').fill(username);
  await page.locator('#password').fill(password);
  await page.locator('#kc-login').click();

  // Wait for redirect back to the app
  await page.waitForURL(/ontoserver\.csiro\.au/, { timeout: 15_000 });
  await page.waitForLoadState('domcontentloaded');
  await page.waitForTimeout(3_000);

  // Shrimp's OAuth callback can replace ?iss= with ?fhir= pointing to the
  // Keycloak issuer instead of the FHIR server (RFC 9207). The Keycloak
  // attribute exclude.issuer.from.auth.response=true prevents this, but if
  // the URL is still wrong, re-navigate to restore the correct FHIR server.
  if (isShrimp && fhirServerUrl) {
    const currentUrl = page.url();
    const hasFhirServer = currentUrl.includes(encodeURIComponent(fhirServerUrl))
      || currentUrl.includes(fhirServerUrl);
    if (!hasFhirServer) {
      const shrimpBase = 'https://ontoserver.csiro.au/shrimp';
      await page.goto(`${shrimpBase}?iss=${encodeURIComponent(fhirServerUrl)}`);
      await page.waitForLoadState('domcontentloaded');
      await page.waitForTimeout(3_000);
    }
  }
}

/**
 * Log out from Keycloak — clears cookies and browser storage so the next
 * login prompt shows a fresh Keycloak login form (not auto-login from
 * existing session).
 */
export async function logout(page: Page): Promise<void> {
  // Clear all cookies (Keycloak session + app state)
  await page.context().clearCookies();

  // Clear browser storage
  await page.evaluate(() => {
    try { sessionStorage.clear(); } catch {}
    try { localStorage.clear(); } catch {}
  });
}

// ---------------------------------------------------------------------------
// Navigation helpers
// ---------------------------------------------------------------------------

/**
 * Navigate to Shrimp connected to a specific FHIR server.
 * Uses ?fhir= (direct connection). Automatically accepts the licence if shown.
 */
export async function openShrimp(page: Page, fhirServerUrl: string): Promise<void> {
  const shrimpBase = 'https://ontoserver.csiro.au/shrimp';
  const shrimpUrl = `${shrimpBase}?fhir=${encodeURIComponent(fhirServerUrl)}`;
  await page.goto(shrimpUrl);
  await page.waitForLoadState('domcontentloaded');
  await page.waitForTimeout(2_000);

  // Accept SNOMED CT licence agreement if presented
  await acceptLicenceAgreement(page);

  // The licence redirect may strip the ?fhir= parameter, so re-navigate
  if (!page.url().includes('fhir=') && !page.url().includes('iss=')) {
    await page.goto(shrimpUrl);
    await page.waitForLoadState('domcontentloaded');
    await page.waitForTimeout(2_000);
  }

  // Give AngularJS time to bootstrap and render
  await page.waitForTimeout(3_000);
}

/**
 * Wait for Shrimp to show its main navigation.
 * Shrimp uses "Terminology" and "ECL" as top-level nav items.
 */
export async function waitForShrimpReady(page: Page): Promise<void> {
  // Use getByRole('link') to avoid strict mode violation — Shrimp has multiple
  // elements containing "ECL" (nav link + radio label) and "Terminology" text.
  await expect(
    page.getByRole('link', { name: 'Terminology' }),
  ).toBeVisible({ timeout: 20_000 });
}

/**
 * Navigate to Snapper connected to a specific FHIR server.
 * Uses ?iss= (SMART launch) since Snapper requires it for FHIR server
 * connection. Automatically accepts the SNOMED CT licence agreement if shown.
 */
export async function openSnapper(page: Page, fhirServerUrl: string): Promise<void> {
  const snapperBase = 'https://ontoserver.csiro.au/snapper';
  const snapperUrl = `${snapperBase}?iss=${encodeURIComponent(fhirServerUrl)}`;
  await page.goto(snapperUrl);
  await page.waitForLoadState('domcontentloaded');
  await page.waitForTimeout(2_000);

  // Accept SNOMED CT licence agreement if presented
  await acceptLicenceAgreement(page);

  // The licence redirect strips ?iss=, so re-navigate to reconnect
  if (!page.url().includes('iss=') && !page.url().includes('fhir=')) {
    await page.goto(snapperUrl);
    await page.waitForLoadState('domcontentloaded');
    await page.waitForTimeout(2_000);
  }

  // Give AngularJS time to bootstrap and render
  await page.waitForTimeout(3_000);
}

/**
 * Wait for Snapper to show a navigation tab (Code Systems, Value Sets, etc.)
 * This confirms the app has bootstrapped and connected to the FHIR server.
 */
export async function waitForSnapperReady(page: Page): Promise<void> {
  // Use .first() to avoid strict mode violation if multiple elements match
  await expect(
    page.getByText('Code Systems')
      .or(page.getByText('Value Sets'))
      .or(page.getByText('Concept Maps'))
      .first(),
  ).toBeVisible({ timeout: 20_000 });
}

/**
 * Navigate to the Ontoserver Dashboard connected to a specific server.
 * Tries ?iss= first; if the Dashboard lands on its login page instead,
 * fills in the Terminology Server URL and clicks Connect.
 */
export async function openDashboard(page: Page, fhirServerUrl: string): Promise<void> {
  const dashboardBase = 'https://ontoserver.csiro.au/ui';
  await page.goto(`${dashboardBase}?iss=${encodeURIComponent(fhirServerUrl)}`);
  await page.waitForLoadState('domcontentloaded');
  await page.waitForTimeout(3_000);

  // If we landed on the login page, fill in the URL and connect manually
  if (page.url().includes('/ui/login')) {
    const urlField = page.getByLabel('Terminology Server URL');
    await urlField.fill(fhirServerUrl);
    await page.getByRole('button', { name: 'Connect' }).click();
    await page.waitForLoadState('domcontentloaded');
    await page.waitForTimeout(5_000);
  }
}

/**
 * Navigate to the Atomio UI connected to a specific Atomio instance.
 */
export async function openAtomioUI(page: Page, atomioUrl: string): Promise<void> {
  // Navigate to the Atomio server URL directly — it redirects to the
  // cloud-hosted Atomio UI with the correct connection. The ?iss= approach
  // doesn't work because the Atomio UI SPA loses the parameter during routing.
  await page.goto(atomioUrl);
  await page.waitForLoadState('domcontentloaded');
  await page.waitForTimeout(5_000);
}
