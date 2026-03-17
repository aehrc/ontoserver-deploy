import { chromium, Page, Browser, request as playwrightRequest } from 'playwright';
import {
  openSnapper,
  openShrimp,
  openAtomioUI,
  loginViaKeycloak,
  logout,
  getToken,
  waitForSnapperReady,
  waitForShrimpReady,
} from '../helpers/auth';
import {
  step,
  explain,
  highlight,
  warn,
  pause,
  promptOnError,
  setAutoMode,
} from './narrator';

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------
const args = process.argv.slice(2);
const variantFlag = args.indexOf('--variant');
const variant = variantFlag !== -1 && args[variantFlag + 1] ? args[variantFlag + 1] : 'simple';
const autoMode = args.includes('--auto');

const AUTHORING_URL = process.env.AUTHORING_URL || 'https://localhost:9081/fhir';
const PRODUCTION_URL = process.env.PRODUCTION_URL || 'https://localhost:9082/fhir';
const UAT_URL = process.env.UAT_URL || 'https://localhost:9084/fhir';
const ATOMIO_URL = process.env.ATOMIO_URL || 'https://localhost:9083';
const AUTHORING_BASE = AUTHORING_URL.replace(/\/fhir$/, '');

// ---------------------------------------------------------------------------
// Scene runner with error handling
// ---------------------------------------------------------------------------
type SceneFn = (page: Page) => Promise<void>;

async function runScene(page: Page, sceneFn: SceneFn): Promise<boolean> {
  let attempts = 0;
  while (attempts < 3) {
    try {
      await sceneFn(page);
      return true; // success
    } catch (error) {
      attempts++;
      const choice = await promptOnError(error as Error);
      if (choice === 'quit') {
        return false; // signal to stop
      }
      if (choice === 'skip') {
        return true; // skip, continue to next scene
      }
      // retry — loop continues
    }
  }
  warn('Max retries reached, skipping scene.');
  return true;
}

// ---------------------------------------------------------------------------
// Scenes
// ---------------------------------------------------------------------------

async function scene1_anonymousProduction(page: Page): Promise<void> {
  step('Anonymous Access on Production');
  explain('Opening Shrimp pointed at the production server without logging in.');
  explain('Only resources with *.read security labels (national content) should be visible.');
  explain('Community-labeled resources (Alpha, Beta, Gamma) are silently filtered.');
  await pause();

  await logout(page);
  await openShrimp(page, PRODUCTION_URL);
  await waitForShrimpReady(page);

  highlight('Look at the Code Systems list — only national content appears.');
  highlight('No Alpha, Beta, or Gamma CodeSystems are visible.');
  await pause();
}

async function scene2_alphaAuthor(page: Page): Promise<void> {
  step('Alpha Author — Community Isolation');
  explain('Now opening Shrimp pointed at the authoring server.');
  explain('We will log in as alpha-author (password: demo).');
  explain('alpha-author has PERM_ALPHA_READ — they should see Alpha resources + national content.');
  await pause();

  await openShrimp(page, AUTHORING_URL);
  await waitForShrimpReady(page);

  // Log in via Keycloak SMART-on-FHIR flow
  await loginViaKeycloak(page, 'alpha-author', 'demo', AUTHORING_URL);
  await waitForShrimpReady(page);

  await page.getByRole('link', { name: 'Terminology' }).click();
  await page.waitForTimeout(2_000);

  highlight('Alpha-author sees Pathology Alpha Local Order Codes + national content.');
  highlight('Beta and Gamma CodeSystems are NOT visible — community isolation in action.');
  await pause();
}

async function scene3_betaComparison(page: Page): Promise<void> {
  step('Beta Author — Same Server, Different View');
  explain('Logging out and switching to beta-author on the same server.');
  explain('beta-author has PERM_BETA_READ — they should see only Beta resources.');
  await pause();

  // Logout and re-open Shrimp to get a fresh login
  await logout(page);
  await openShrimp(page, AUTHORING_URL);
  await waitForShrimpReady(page);

  await loginViaKeycloak(page, 'beta-author', 'demo', AUTHORING_URL);
  await waitForShrimpReady(page);

  await page.getByRole('link', { name: 'Terminology' }).click();
  await page.waitForTimeout(2_000);

  highlight('Same Shrimp URL, same server — but now we see Pathology Beta instead of Alpha.');
  highlight('The resource list changes based on who is logged in.');
  await pause();
}

async function scene4_adminSeesAll(page: Page): Promise<void> {
  step('Admin — Wildcard Permissions');
  explain('Logging out and switching to admin.');
  explain('admin has PERM_READ (wildcard) — they see ALL community resources.');
  await pause();

  await logout(page);
  await openShrimp(page, AUTHORING_URL);
  await waitForShrimpReady(page);

  await loginViaKeycloak(page, 'admin', 'demo', AUTHORING_URL);
  await waitForShrimpReady(page);

  await page.getByRole('link', { name: 'Terminology' }).click();
  await page.waitForTimeout(2_000);

  highlight('Admin sees Alpha, Beta, AND Gamma CodeSystems — plus national content.');
  highlight('PERM_READ is the wildcard that matches all community labels.');
  await pause();
}

/**
 * Navigate Snapper to its "Find existing FHIR Resources" search page and
 * select a resource type. The search auto-runs, showing resources visible
 * to the currently authenticated user.
 */
async function snapperSearchByType(page: Page, type: 'CodeSystem' | 'ValueSet' | 'ConceptMap'): Promise<void> {
  // Dismiss any modal that might be covering the page (e.g. syndication success, login confirmation)
  const modalDismiss = page.locator('.modal.in .modal-footer button, .modal.in .close').first();
  if (await modalDismiss.isVisible({ timeout: 1_000 }).catch(() => false)) {
    await modalDismiss.click();
    await page.waitForTimeout(1_000);
  }

  // Click the "Find existing FHIR Resources" button to go to the search page
  await page.locator('#search-view-btn').click();
  await page.waitForTimeout(2_000);

  // Select the desired resource type — auto-triggers search
  await page.locator('#search-type').selectOption({ label: type });
  await page.waitForTimeout(3_000);
}

/**
 * Import a resource from Snapper search results and open it in the editor.
 * After importing, clicks the resource in the sidebar and navigates to
 * the "Upload to FHIR Server" tab.
 */
async function snapperImportAndOpenUploadTab(
  page: Page,
  importIndex: number,
  sidebarText: string,
): Promise<void> {
  // Click the green plus (import) button on the search result
  await page.locator(`#import-resource-btn-${importIndex}`).click();
  await page.waitForTimeout(2_000);

  // Click on the imported resource in the left sidebar to open the editor
  await page.locator('.list-group-item')
    .filter({ hasText: sidebarText })
    .first()
    .click();
  await page.waitForTimeout(2_000);

  // Navigate to the "Upload to FHIR Server" tab
  await page.locator('#publish-link').click();
  await page.waitForTimeout(3_000);
}

/**
 * Dismiss Snapper's "Confirm FHIR Server Login?" modal if it appears.
 * The modal shows when Snapper needs to (re-)authenticate with the FHIR server.
 * If a Keycloak SSO session exists, the login completes without a form.
 * Otherwise, fills the Keycloak login form and waits for redirect.
 */
async function handleSnapperLoginModal(page: Page, username: string): Promise<void> {
  const loginBtn = page.locator('.modal-footer .btn-success');
  if (await loginBtn.isVisible({ timeout: 2_000 }).catch(() => false)) {
    await loginBtn.click();

    // If we land on Keycloak login form, fill it
    const onKeycloak = await page.waitForURL(/localhost:9090/, { timeout: 5_000 }).then(() => true).catch(() => false);
    if (onKeycloak) {
      await page.locator('#username').fill(username);
      await page.locator('#password').fill('demo');
      await page.locator('#kc-login').click();
      await page.waitForURL(/ontoserver\.csiro\.au/, { timeout: 15_000 });
    }

    await page.waitForTimeout(3_000);
  }
}

async function scene5_viewerVsAuthor(page: Page): Promise<void> {
  step('Viewer vs Author — Read-Only Access in Snapper');
  explain('Opening Snapper (the authoring tool) as alpha-viewer.');
  explain('alpha-viewer has PERM_ALPHA_READ but NOT PERM_ALPHA_WRITE.');
  explain('They can browse Alpha resources but cannot upload changes.');
  await pause();

  await logout(page);
  await openSnapper(page, AUTHORING_URL);
  await waitForSnapperReady(page);

  await loginViaKeycloak(page, 'alpha-viewer');
  await waitForSnapperReady(page);

  // Search for CodeSystems and import Pathology Alpha 1.0.0
  await snapperSearchByType(page, 'CodeSystem');
  explain('Importing Pathology Alpha into the Snapper editor...');
  await snapperImportAndOpenUploadTab(page, 1, 'Pathology Alpha');

  highlight('The "Upload Code System" button shows "(unauthorised)".');
  highlight('The "Syndicate" button is also disabled.');
  highlight('alpha-viewer can browse and download, but cannot write anything back.');
  explain('The server communicates the user\'s permissions to the editor via SMART scopes.');
  await pause();
}

async function scene6_authorUploads(page: Page): Promise<void> {
  step('Author Permissions — Write but Not Syndicate');
  explain('Logging in as alpha-author — has FHIR_WRITE but NOT SYND_WRITE.');
  explain('Loading the published CodeSystem 1.0.0 to show the permission gates...');
  await pause();

  await logout(page);
  await openSnapper(page, AUTHORING_URL);
  await waitForSnapperReady(page);
  await loginViaKeycloak(page, 'alpha-author');
  await waitForSnapperReady(page);

  // Search and import the published 1.0.0, then open Upload tab
  await snapperSearchByType(page, 'CodeSystem');
  explain('Importing the published Pathology Alpha 1.0.0...');
  await snapperImportAndOpenUploadTab(page, 1, 'Pathology Alpha');

  highlight('The Upload button is enabled — alpha-author has FHIR_WRITE permission.');
  highlight('The Syndicate button shows "(unauthorised)" — only approvers can syndicate.');
  explain('Let\'s try uploading this syndicated resource to see what happens...');
  await pause();

  // Click Upload on the syndicated 1.0.0 — should fail with "Operation not permitted"
  const uploadBtnFirst = page.locator('#split-publish');
  explain('Clicking Upload Code System on the syndicated 1.0.0...');
  await uploadBtnFirst.click();
  await page.waitForTimeout(3_000);

  highlight('The server rejects it: "Operation not permitted: The user is not authorised to perform this action."');
  highlight('Even with FHIR_WRITE, syndicated resources are protected — the author lacks SYND_WRITE.');
  explain('This is the governance gate: authors can write NEW content but cannot overwrite published resources.');
  explain('Next: the author creates version 1.1.0 with a new ID.');
  await pause();

  // Edit the resource: change version to 1.1.0
  explain('Editing the resource locally: changing version...');
  await page.locator('a').filter({ hasText: 'Define codes' }).first().click();
  await page.waitForTimeout(2_000);

  const versionField = page.locator('#version');
  await versionField.click({ clickCount: 3 });
  await versionField.fill('1.1.0');
  await page.waitForTimeout(500);

  highlight('Version changed to 1.1.0.');
  explain('In a real workflow the author would also add/modify concepts here.');
  await pause();

  // Navigate to Upload tab, change ID, and upload
  explain('Going to the Upload tab to change the resource ID and upload...');
  await page.locator('#publish-link').click();
  await page.waitForTimeout(2_000);

  // Handle login modal if it appears (Snapper re-checks auth on Upload tab)
  await handleSnapperLoginModal(page, 'alpha-author');

  // Change the Code System id to create a new resource instead of overwriting
  const idField = page.locator('#resource-id');
  await idField.click({ clickCount: 3 });
  await idField.fill('alpha-pathology-codes-v1-1-0');
  await page.waitForTimeout(1_000);

  highlight('Resource ID changed to alpha-pathology-codes-v1-1-0.');
  explain('This creates a new resource on the server instead of overwriting 1.0.0.');

  // Click the Upload button
  const uploadBtn = page.locator('#split-publish');
  await page.waitForTimeout(1_000);
  explain('Uploading version 1.1.0 to the authoring server...');
  await uploadBtn.click();
  await page.waitForTimeout(3_000);

  highlight('Version 1.1.0 uploaded successfully via the Snapper UI!');
  highlight('The new 1.1.0 is a draft — it has no syndication status yet.');
  explain('It will not appear in the syndication feed until an approver publishes it.');
  await pause();
}

async function scene7_approverPublishes(page: Page): Promise<void> {
  step('Approver Publishes New Version');
  explain('Switching to alpha-approver — has the Approver role with SYND_WRITE.');
  explain('Only approvers can set syndication status — this is the publication gate.');
  await pause();

  await logout(page);
  await openSnapper(page, AUTHORING_URL);
  await waitForSnapperReady(page);
  await loginViaKeycloak(page, 'alpha-approver');
  await waitForSnapperReady(page);

  // Search for CodeSystems — both 1.0.0 and 1.1.0 should appear
  await snapperSearchByType(page, 'CodeSystem');
  await page.waitForTimeout(2_000);

  // Import the 1.1.0 version (last search result)
  explain('Importing version 1.1.0 for review and approval...');
  const importButtons = page.locator('[id^="import-resource-btn-"]');
  const count = await importButtons.count();
  await snapperImportAndOpenUploadTab(page, count - 1, 'Pathology Alpha');

  highlight('The Approver role includes SYND_WRITE — the permission to publish resources.');

  // Try clicking the Syndicate button in the UI
  const syndicateBtn = page.locator('#syndicate-btn');
  const isSyndicateDisabled = await syndicateBtn.getAttribute('disabled').catch(() => 'true');

  if (!isSyndicateDisabled) {
    explain('Publishing version 1.1.0 to the syndication feed...');
    await syndicateBtn.click();
    await page.waitForTimeout(3_000);

    // Dismiss the "Code System successfully syndicated" confirmation modal
    const okBtn = page.locator('.modal.in .modal-footer button').first();
    if (await okBtn.isVisible({ timeout: 2_000 }).catch(() => false)) {
      await okBtn.click();
      await page.waitForTimeout(1_000);
    }

    highlight('Syndicate button clicked — version 1.1.0 is now published!');
  } else {
    // Fallback: set syndication status via API
    explain('Setting syndication status via the server API...');
    const approverToken = await getToken('alpha-approver');
    const syndUrl = `${AUTHORING_BASE}/synd/setSyndicationStatus`
      + '?resourceType=CodeSystem&id=alpha-pathology-codes-v1-1-0&syndicate=true';

    const ctx = await playwrightRequest.newContext({ ignoreHTTPSErrors: true });
    try {
      const response = await ctx.post(syndUrl, {
        headers: { Authorization: `Bearer ${approverToken}` },
      });
      if (response.status() === 200) {
        highlight('Syndication status set to TRUE — version 1.1.0 is now published!');
      } else {
        warn(`Unexpected status ${response.status()} setting syndication.`);
      }
    } finally {
      await ctx.dispose();
    }
  }

  highlight('The new version will appear in the syndication feed for downstream servers.');
  await pause();
}

async function scene8_conceptMaps(page: Page): Promise<void> {
  step('ConceptMaps — Community Isolation for All Resource Types');
  explain('Searching for ConceptMaps in Snapper (still as alpha-approver).');
  explain('ConceptMaps are also community-labeled — Alpha can only see their own.');
  await pause();

  // If we're still on the Snapper search page, just switch type.
  const isOnSnapper = page.url().includes('snapper');
  if (!isOnSnapper) {
    await logout(page);
    await openSnapper(page, AUTHORING_URL);
    await waitForSnapperReady(page);
    await loginViaKeycloak(page, 'alpha-approver');
    await waitForSnapperReady(page);
  }

  await snapperSearchByType(page, 'ConceptMap');
  await page.waitForTimeout(2_000);

  highlight('Alpha\'s ConceptMap maps local codes (FBC, BGL, HBA1C) to SNOMED CT.');
  highlight('Beta\'s and Gamma\'s ConceptMaps are not visible.');
  await pause();
}

async function scene9_syndication(page: Page): Promise<void> {
  step('Syndication — Content Flows to Production');
  explain('The authoring server publishes a syndication feed of approved content.');
  explain('Production subscribes to this feed and syncs automatically.');
  explain('Opening Shrimp on the production server as admin to verify...');
  await pause();

  await logout(page);
  await openShrimp(page, PRODUCTION_URL);
  await waitForShrimpReady(page);

  await loginViaKeycloak(page, 'admin', 'demo', PRODUCTION_URL);
  await waitForShrimpReady(page);

  await page.getByRole('link', { name: 'Terminology' }).click();
  await page.waitForTimeout(2_000);

  highlight('Production has the same community content — synced from authoring via the syndication feed.');
  highlight('The syndication-consumer service account has PERM_READ (all communities).');
  await pause();

  // Click on the Alpha CodeSystem to show its details including version 1.1.0
  explain('Clicking on Pathology Alpha to verify version 1.1.0 was syndicated...');
  const alphaLink = page.locator('a, td, tr, span, div')
    .filter({ hasText: /Pathology Alpha/i })
    .first();
  await alphaLink.click();
  await page.waitForTimeout(3_000);

  highlight('Version 1.1.0 is here — the new version created by the author and published by the approver.');
  highlight('Security labels are preserved end-to-end — users on production still see only their community\'s resources.');
  await pause();
}

async function scene10_csvContent(page: Page): Promise<void> {
  step('CSV-to-FHIR Pipeline — Gamma Content');
  explain('Switching Shrimp to the authoring server (still logged in as admin via SSO).');
  explain('Pathology Gamma maintains codes in CSV files under version control.');
  explain('The csv-transform.py script converts them to FHIR with GAMMA security labels.');
  await pause();

  // We're already on Shrimp as admin from scene 9 (production).
  // Switch to authoring — SSO session persists but Shrimp still shows
  // the login button. Click it to trigger OAuth; Keycloak auto-completes
  // via SSO without showing the login form.
  await openShrimp(page, AUTHORING_URL);
  await waitForShrimpReady(page);

  const loginBtn = page.locator('#fhir-server-login');
  if (await loginBtn.isVisible({ timeout: 3_000 }).catch(() => false)) {
    await loginBtn.click();
    // SSO auto-completes — just wait for Shrimp to come back
    await page.waitForURL(/ontoserver\.csiro\.au/, { timeout: 15_000 }).catch(() => {});
    await page.waitForLoadState('domcontentloaded');
    await page.waitForTimeout(3_000);
  }

  await page.getByRole('link', { name: 'Terminology' }).click();
  await page.waitForTimeout(2_000);

  highlight('Admin sees Pathology Gamma — 15 concepts loaded from CSV.');
  highlight('These have GAMMA.read and GAMMA.write security labels.');
  explain('If we logged in as alpha-author, the Gamma CodeSystem would disappear.');
  await pause();
}

// ---------------------------------------------------------------------------
// Atomio-only scenes: Release pipeline replacing simple syndication
// ---------------------------------------------------------------------------

/** Helper: open Atomio UI and handle SSO login if needed */
async function openAtomioAndLogin(page: Page): Promise<void> {
  await openAtomioUI(page, ATOMIO_URL);
  await page.waitForTimeout(3_000);

  // loginViaKeycloak detects the Atomio Login button and handles the full
  // Keycloak OAuth flow (or SSO auto-completes on subsequent visits)
  try {
    await loginViaKeycloak(page, 'admin');
    await page.waitForTimeout(3_000);
  } catch {
    // Already logged in via SSO or no login button — continue
  }
}

/** Helper: trigger Ontoserver preload/syndication via /synd/redoPreload API */
async function triggerPreload(serverBaseUrl: string): Promise<boolean> {
  const token = await getToken('admin');
  const ctx = await playwrightRequest.newContext({ ignoreHTTPSErrors: true });
  try {
    const resp = await ctx.post(`${serverBaseUrl}/synd/redoPreload`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    return resp.status() === 200 || resp.status() === 201;
  } catch {
    return false;
  } finally {
    await ctx.dispose();
  }
}

/** Helper: wait for a resource to appear on a server */
async function waitForResource(
  serverUrl: string, resourcePath: string, maxWaitSec: number = 30,
): Promise<boolean> {
  const token = await getToken('admin');
  const ctx = await playwrightRequest.newContext({ ignoreHTTPSErrors: true });
  try {
    const deadline = Date.now() + maxWaitSec * 1000;
    while (Date.now() < deadline) {
      const resp = await ctx.get(`${serverUrl}/${resourcePath}`, {
        headers: { Authorization: `Bearer ${token}`, Accept: 'application/fhir+json' },
      });
      if (resp.status() === 200) {
        const body = await resp.json();
        if (body.resourceType !== 'OperationOutcome') return true;
      }
      await new Promise(r => setTimeout(r, 3000));
    }
    return false;
  } finally {
    await ctx.dispose();
  }
}

async function scene9_atomioReleasePipeline(page: Page): Promise<void> {
  step('Atomio — Clone Release Candidate');
  explain('In the atomio variant, content flows: Authoring → Atomio → UAT → Production.');
  explain('Atomio creates immutable release snapshots. Aliases control which feed each server uses.');
  explain('Opening the Atomio UI to clone authoring\'s syndication feed into a new release...');
  await pause();

  // Open Atomio UI and log in as admin
  await logout(page);
  await openAtomioAndLogin(page);

  highlight('Current feeds: release-1-0 (initial) and gamma-content.');
  highlight('Both "uat" and "production" aliases point to release-1-0 (the old content).');
  explain('Clicking "Clone Feed" to create a new release candidate from authoring...');
  await pause();

  // Click "Clone Feed" button in the Atomio UI toolbar
  await page.getByRole('button', { name: 'Clone Feed' }).click();
  await page.waitForTimeout(2_000);

  // Dialog: "Clone existing feed" with Name and URL fields
  const cloneDialog = page.getByRole('dialog', { name: 'Clone existing feed' });
  await cloneDialog.waitFor({ state: 'visible', timeout: 5_000 });

  // Fill form fields — scope to dialog to avoid matching table headers
  await cloneDialog.getByLabel('Name').fill('release-2-0');
  await cloneDialog.getByLabel('URL').fill('http://authoring-ontoserver:8080/synd/syndication.xml');
  await page.waitForTimeout(1_000);

  // Submit — click the "Clone Feed" button inside the dialog
  await cloneDialog.getByRole('button', { name: 'Clone Feed' }).click();
  await page.waitForTimeout(8_000);

  highlight('Release candidate "release-2-0" created from authoring feed.');
  highlight('Three feeds now: release-1-0, release-2-0 (with v1.1.0), and gamma-content.');
  await pause();
}

async function scene10_atomioPromoteUAT(page: Page): Promise<void> {
  step('Atomio — Promote to UAT');
  explain('Navigating to Aliases in the Atomio UI to promote release-2-0 to UAT.');
  explain('The UAT Ontoserver polls the uat alias for changes.');
  await pause();

  // Navigate to Aliases page via left nav
  await page.getByRole('link', { name: 'Aliases' }).click();
  await page.waitForTimeout(2_000);

  // Click the "Redirect alias" (wrench) icon on the uat row
  const uatRow = page.locator('tbody tr').filter({ hasText: 'uat' }).first();
  await uatRow.getByRole('button', { name: 'Redirect alias' }).click();
  await page.waitForTimeout(2_000);

  // Dialog: "Redirect alias to feed" with FeedSelect autocomplete
  const uatDialog = page.getByRole('dialog', { name: 'Redirect alias to feed' });
  await uatDialog.waitFor({ state: 'visible', timeout: 5_000 });

  // Type into the autocomplete to filter and select release-2-0
  await uatDialog.getByLabel('Feed Name').click();
  await uatDialog.getByLabel('Feed Name').fill('release-2-0');
  await page.waitForTimeout(1_000);
  // Select from the autocomplete dropdown
  await page.locator('[role="listbox"] li').filter({ hasText: 'release-2-0' }).click();
  await page.waitForTimeout(500);

  // Submit
  await uatDialog.getByRole('button', { name: 'Redirect Alias' }).click();
  await page.waitForTimeout(3_000);

  highlight('"uat" alias now points to release-2-0.');
  highlight('Atomio shows uat → release-2-0, production → release-1-0 (unchanged).');
  explain('Triggering UAT to syndicate now via the Ontoserver redoPreload API...');

  // Trigger UAT preload via API and wait for v1.1.0.
  // Ontoserver caches feed responses by URL — the alias URL hasn't changed,
  // just its content. We trigger preload, wait, then retry to bust the cache.
  const uatBase = UAT_URL.replace(/\/fhir$/, '');
  await triggerPreload(uatBase);
  let uatSynced = await waitForResource(UAT_URL, 'CodeSystem/alpha-pathology-codes-v1-1-0', 30);
  if (!uatSynced) {
    // Cache may be stale — wait for it to expire and retry
    await new Promise(r => setTimeout(r, 5000));
    await triggerPreload(uatBase);
    uatSynced = await waitForResource(UAT_URL, 'CodeSystem/alpha-pathology-codes-v1-1-0', 60);
  }
  if (uatSynced) {
    highlight('v1.1.0 is now on UAT!');
  } else {
    warn('v1.1.0 not yet on UAT — syndication may still be in progress.');
  }
  await pause();

  // Open Shrimp on UAT to show the content visually
  explain('Opening Shrimp on UAT to verify...');
  await openShrimp(page, UAT_URL);
  await waitForShrimpReady(page);
  await loginViaKeycloak(page, 'admin', 'demo', UAT_URL);
  await waitForShrimpReady(page);

  await page.getByRole('link', { name: 'Terminology' }).click();
  await page.waitForTimeout(3_000);

  highlight('UAT has the content from release-2-0 — including the new v1.1.0.');
  await pause();

  // Now check production — it should NOT have v1.1.0 yet
  explain('Now checking production — it still points to release-1-0 (the old feed)...');
  await logout(page);
  await openShrimp(page, PRODUCTION_URL);
  await waitForShrimpReady(page);
  await loginViaKeycloak(page, 'admin', 'demo', PRODUCTION_URL);
  await waitForShrimpReady(page);

  await page.getByRole('link', { name: 'Terminology' }).click();
  await page.waitForTimeout(2_000);

  highlight('Production does NOT have v1.1.0 yet — it is still on release-1-0.');
  highlight('This is the governance gate: UAT can test before production gets the update.');
  await pause();
}

async function scene11_atomioPromoteProduction(page: Page): Promise<void> {
  step('Atomio — Promote to Production');
  explain('After UAT testing passes, updating the "production" alias to release-2-0.');
  explain('Navigating back to the Atomio UI Aliases page...');
  await pause();

  // Navigate back to Atomio UI Aliases page
  await openAtomioAndLogin(page);
  await page.getByRole('link', { name: 'Aliases' }).click();
  await page.waitForTimeout(2_000);

  // Click the "Redirect alias" (wrench) icon on the production row
  const prodRow = page.locator('tbody tr').filter({ hasText: 'production' }).first();
  await prodRow.getByRole('button', { name: 'Redirect alias' }).click();
  await page.waitForTimeout(2_000);

  // Dialog: "Redirect alias to feed" — select release-2-0
  const prodDialog = page.getByRole('dialog', { name: 'Redirect alias to feed' });
  await prodDialog.waitFor({ state: 'visible', timeout: 5_000 });
  await prodDialog.getByLabel('Feed Name').click();
  await prodDialog.getByLabel('Feed Name').fill('release-2-0');
  await page.waitForTimeout(1_000);
  await page.locator('[role="listbox"] li').filter({ hasText: 'release-2-0' }).click();
  await page.waitForTimeout(500);

  // Submit
  await prodDialog.getByRole('button', { name: 'Redirect Alias' }).click();
  await page.waitForTimeout(3_000);

  highlight('"production" alias now points to release-2-0.');
  highlight('Both aliases now point to release-2-0.');
  explain('Opening OntoCommand on production to trigger syndication via the Preload button...');
  await pause();

  // Open OntoCommand on production (FHIR root redirects to OntoCommand)
  await page.goto(PRODUCTION_URL);
  await page.waitForLoadState('domcontentloaded');
  await page.waitForTimeout(3_000);

  // Log in and trigger preload
  await loginViaKeycloak(page, 'admin');
  await page.waitForTimeout(3_000);

  await page.getByText('Syndication').click();
  await page.waitForTimeout(2_000);
  await page.getByRole('button', { name: 'Preload' }).click();
  await page.waitForTimeout(2_000);

  highlight('Preload triggered — production is now syndicating from Atomio.');
  explain('Waiting for v1.1.0 to appear on production...');

  const prodBase = PRODUCTION_URL.replace(/\/fhir$/, '');
  let prodSynced = await waitForResource(PRODUCTION_URL, 'CodeSystem/alpha-pathology-codes-v1-1-0', 30);
  if (!prodSynced) {
    // Cache may be stale — retry
    await new Promise(r => setTimeout(r, 5000));
    await triggerPreload(prodBase);
    prodSynced = await waitForResource(PRODUCTION_URL, 'CodeSystem/alpha-pathology-codes-v1-1-0', 60);
  }
  if (prodSynced) {
    highlight('v1.1.0 is now on production!');
  } else {
    warn('v1.1.0 not yet on production — syndication may still be in progress.');
  }
  await pause();

  // Open Shrimp on production to show the content visually
  explain('Opening Shrimp on production to verify...');
  await openShrimp(page, PRODUCTION_URL);
  await waitForShrimpReady(page);
  await loginViaKeycloak(page, 'admin', 'demo', PRODUCTION_URL);
  await waitForShrimpReady(page);

  await page.getByRole('link', { name: 'Terminology' }).click();
  await page.waitForTimeout(3_000);

  highlight('Production now has the content from release-2-0!');
  highlight('The full pipeline: Author → Approve → Clone to Atomio → UAT → Production.');
  highlight('Security labels preserved end-to-end through the entire release pipeline.');
  await pause();
}

async function scene12_csvContent(page: Page): Promise<void> {
  step('CSV-to-FHIR Pipeline — Gamma Content');
  explain('Switching Shrimp to the authoring server (still logged in as admin via SSO).');
  explain('Pathology Gamma maintains codes in CSV files under version control.');
  explain('The csv-transform.py script converts them to FHIR with GAMMA security labels.');
  await pause();

  await openShrimp(page, AUTHORING_URL);
  await waitForShrimpReady(page);

  const loginBtn = page.locator('#fhir-server-login');
  if (await loginBtn.isVisible({ timeout: 3_000 }).catch(() => false)) {
    await loginBtn.click();
    await page.waitForURL(/ontoserver\.csiro\.au/, { timeout: 15_000 }).catch(() => {});
    await page.waitForLoadState('domcontentloaded');
    await page.waitForTimeout(3_000);
  }

  await page.getByRole('link', { name: 'Terminology' }).click();
  await page.waitForTimeout(2_000);

  highlight('Admin sees Pathology Gamma — 15 concepts loaded from CSV.');
  highlight('These have GAMMA.read and GAMMA.write security labels.');
  explain('If we logged in as alpha-author, the Gamma CodeSystem would disappear.');
  await pause();
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main(): Promise<void> {
  if (autoMode) setAutoMode(true);

  console.log('');
  console.log('============================================================');
  console.log('  Pathology Permissions Demo — Visual Walkthrough');
  console.log(`  Variant: ${variant}`);
  console.log('============================================================');
  console.log('');
  console.log('This walkthrough drives the browser through each demo scenario');
  console.log('with explanations. Press Enter at each pause to continue.');
  console.log('');

  await pause('Press Enter to start the walkthrough...');

  const browser: Browser = await chromium.launch({
    headless: false,
    slowMo: 500,
    args: [
      // Cloud-hosted Shrimp/Snapper at ontoserver.csiro.au makes XHR requests to
      // localhost FHIR servers. Chromium blocks this by default (Private Network
      // Access + CORS + mixed content). This flag disables web security to allow
      // the cross-origin localhost requests needed for the demo.
      '--disable-web-security',
      // Also allow HTTPS pages to fetch from HTTP localhost
      '--allow-running-insecure-content',
    ],
  });

  const context = await browser.newContext({
    viewport: { width: 1280, height: 800 },
    ignoreHTTPSErrors: true,
  });
  const page = await context.newPage();

  // Inject a visible cursor overlay that follows mouse movements.
  // Uses page.on('load') + page.evaluate to inject after each navigation,
  // since addInitScript can be blocked by CSP on some sites.
  const installCursor = async () => {
    await page.evaluate(() => {
      if (document.getElementById('pw-cursor')) return;
      const cursor = document.createElement('div');
      cursor.id = 'pw-cursor';
      cursor.style.cssText = [
        'width: 20px', 'height: 20px', 'border-radius: 50%',
        'background: rgba(255, 50, 50, 0.5)', 'border: 2px solid red',
        'position: fixed', 'z-index: 2147483647', 'pointer-events: none',
        'transform: translate(-50%, -50%)', 'transition: left 0.05s linear, top 0.05s linear',
        'left: -100px', 'top: -100px',
      ].join(';');
      document.body.appendChild(cursor);
      document.addEventListener('mousemove', (e) => {
        cursor.style.left = e.clientX + 'px';
        cursor.style.top = e.clientY + 'px';
      });
    }).catch(() => {}); // ignore if page navigated away
  };
  page.on('load', installCursor);

  // Ensure browser closes on Ctrl+C
  const cleanup = async () => {
    console.log('\nClosing browser...');
    await browser.close().catch(() => {});
    process.exit(0);
  };
  process.on('SIGINT', cleanup);
  process.on('SIGTERM', cleanup);

  try {
    // Scenes 1-8 are shared between simple and atomio
    const sharedScenes: SceneFn[] = [
      scene1_anonymousProduction,
      scene2_alphaAuthor,
      scene3_betaComparison,
      scene4_adminSeesAll,
      scene5_viewerVsAuthor,
      scene6_authorUploads,
      scene7_approverPublishes,
      scene8_conceptMaps,
    ];

    // Simple: direct syndication to production + CSV content
    const simpleScenes: SceneFn[] = [
      scene9_syndication,
      scene10_csvContent,
    ];

    // Atomio: release pipeline (clone → UAT → production) + CSV content
    const atomioScenes: SceneFn[] = [
      scene9_atomioReleasePipeline,
      scene10_atomioPromoteUAT,
      scene11_atomioPromoteProduction,
      scene12_csvContent,
    ];

    const allScenes = variant === 'atomio'
      ? [...sharedScenes, ...atomioScenes]
      : [...sharedScenes, ...simpleScenes];

    for (const sceneFn of allScenes) {
      const shouldContinue = await runScene(page, sceneFn);
      if (!shouldContinue) {
        break;
      }
    }

    // Wrap up
    console.log('');
    console.log('============================================================');
    console.log('  Walkthrough Complete!');
    console.log('============================================================');
    console.log('');
    console.log('Key takeaways:');
    console.log('  1. Community isolation — each provider sees only their resources');
    console.log('  2. Shared national content — visible to everyone via *.read label');
    console.log('  3. Role-based access — viewers read, authors write, approvers publish');
    console.log('  4. Syndication preserves security labels end-to-end');
    if (variant === 'atomio') {
      console.log('  5. Atomio: clone → UAT alias → test → production alias → promote');
      console.log('  6. Rollback = repoint alias to previous feed (instant)');
    }
    console.log('');
  } finally {
    await browser.close();
  }
}

main().catch(async (error) => {
  console.error('Walkthrough failed:', error);
  process.exit(1);
});
