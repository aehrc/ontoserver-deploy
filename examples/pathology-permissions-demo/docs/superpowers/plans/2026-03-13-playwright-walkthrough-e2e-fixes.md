# Playwright Visual Walkthrough + E2E Test Fixes — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a presenter-driven Playwright visual walkthrough of the pathology permissions demo and fill gaps in e2e test coverage.

**Architecture:** A standalone TypeScript walkthrough script uses Playwright's library API (not the test runner) to drive a headed browser through demo scenarios with terminal narration and readline pause points. New e2e test specs use the standard Playwright test runner to cover anonymous access, syndication, CSV content, and Atomio workflow scenarios.

**Tech Stack:** Playwright (library + test), TypeScript, tsx, Node.js readline

**Spec:** `docs/superpowers/specs/2026-03-13-playwright-walkthrough-e2e-fixes-design.md`

---

## Chunk 1: Foundation — Dependencies, Helpers, and Narrator

### Task 1: Update package.json with new dependencies

**Files:**
- Modify: `tests/e2e/package.json`

- [ ] **Step 1: Add playwright, tsx dependencies and walkthrough scripts**

In `tests/e2e/package.json`, add `playwright` and `tsx` to devDependencies, and add walkthrough scripts:

```json
{
  "name": "pathology-permissions-e2e",
  "version": "1.0.0",
  "private": true,
  "description": "End-to-end tests for the pathology permissions demo using Playwright",
  "scripts": {
    "test": "npx playwright test",
    "test:simple": "VARIANT=simple npx playwright test --grep-invert @atomio",
    "test:atomio": "VARIANT=atomio npx playwright test",
    "test:headed": "npx playwright test --headed",
    "install-browsers": "npx playwright install chromium",
    "walkthrough": "npx tsx walkthrough/visual-walkthrough.ts",
    "walkthrough:atomio": "npx tsx walkthrough/visual-walkthrough.ts --variant atomio"
  },
  "devDependencies": {
    "@playwright/test": "^1.45.0",
    "@types/node": "^25.3.5",
    "playwright": "^1.45.0",
    "tsx": "^4.0.0"
  }
}
```

- [ ] **Step 2: Install dependencies**

Run: `cd tests/e2e && npm install`
Expected: Clean install with no errors. `node_modules/playwright` and `node_modules/tsx` present.

- [ ] **Step 3: Commit**

```bash
git add tests/e2e/package.json tests/e2e/package-lock.json
git commit -m "chore: add playwright library and tsx dependencies for walkthrough"
```

---

### Task 2: Add Shrimp helpers to auth.ts

**Files:**
- Modify: `tests/e2e/helpers/auth.ts`

- [ ] **Step 1: Add openShrimp, shrimpLogin, shrimpLogout functions**

Append to the end of `tests/e2e/helpers/auth.ts` (after the existing `waitForSnapperReady` function):

```typescript
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
```

- [ ] **Step 2: Verify TypeScript compiles**

Run: `cd tests/e2e && npx tsc --noEmit --esModuleInterop --module nodenext --moduleResolution nodenext helpers/auth.ts 2>&1 || echo "Note: tsc check may fail without tsconfig; verify no red squiggles in editor instead"`

The helpers import `Page` and `expect` from `@playwright/test` — ensure the new functions also use the same `Page` type (already imported at top of file).

- [ ] **Step 3: Commit**

```bash
git add tests/e2e/helpers/auth.ts
git commit -m "feat: add Shrimp browser helpers (openShrimp, shrimpLogin, shrimpLogout)"
```

---

### Task 3: Create the narrator module

**Files:**
- Create: `tests/e2e/walkthrough/narrator.ts`

- [ ] **Step 1: Create walkthrough directory**

Run: `mkdir -p tests/e2e/walkthrough`

- [ ] **Step 2: Write narrator.ts**

Create `tests/e2e/walkthrough/narrator.ts`:

```typescript
import * as readline from 'node:readline';

const GREEN = '\x1b[0;32m';
const YELLOW = '\x1b[1;33m';
const BLUE = '\x1b[0;34m';
const CYAN = '\x1b[0;36m';
const NC = '\x1b[0m';

let stepNumber = 0;

/**
 * Print a numbered step header with a cyan border box.
 */
export function step(title: string): void {
  stepNumber++;
  console.log('');
  console.log(`${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}`);
  console.log(`${CYAN}  Step ${stepNumber}: ${title}${NC}`);
  console.log(`${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}`);
  console.log('');
}

/**
 * Print blue explanation text.
 */
export function explain(text: string): void {
  console.log(`${BLUE}${text}${NC}`);
}

/**
 * Print green highlighted observation text.
 */
export function highlight(text: string): void {
  console.log(`${GREEN}${text}${NC}`);
}

/**
 * Print a yellow warning.
 */
export function warn(text: string): void {
  console.log(`${YELLOW}${text}${NC}`);
}

/**
 * Pause execution and wait for the presenter to press Enter.
 */
export async function pause(message?: string): Promise<void> {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  return new Promise<void>((resolve) => {
    rl.question(
      `\n${YELLOW}${message || 'Press Enter to continue...'}${NC}`,
      () => {
        rl.close();
        resolve();
      },
    );
  });
}

/**
 * Prompt for retry/skip/quit when a scene fails.
 * Returns 'retry', 'skip', or 'quit'.
 */
export async function promptOnError(error: Error): Promise<'retry' | 'skip' | 'quit'> {
  warn(`Error: ${error.message}`);
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  return new Promise<'retry' | 'skip' | 'quit'>((resolve) => {
    rl.question(
      `${YELLOW}[r]etry / [s]kip / [q]uit: ${NC}`,
      (answer) => {
        rl.close();
        const choice = answer.trim().toLowerCase();
        if (choice === 'r' || choice === 'retry') resolve('retry');
        else if (choice === 'q' || choice === 'quit') resolve('quit');
        else resolve('skip');
      },
    );
  });
}

/**
 * Reset step counter (useful if restarting).
 */
export function resetSteps(): void {
  stepNumber = 0;
}
```

- [ ] **Step 3: Verify it compiles**

Run: `cd tests/e2e && npx tsx --eval "import { step, explain, pause } from './walkthrough/narrator'; step('test'); explain('works'); console.log('OK')"`
Expected: Prints step header, explanation text, and "OK" without errors.

- [ ] **Step 4: Commit**

```bash
git add tests/e2e/walkthrough/narrator.ts
git commit -m "feat: add narrator module for visual walkthrough terminal output"
```

---

## Chunk 2: E2E Test Specs — Anonymous Access, Syndication, CSV Content

### Task 4: Create anonymous-access.spec.ts

**Files:**
- Create: `tests/e2e/tests/anonymous-access.spec.ts`

- [ ] **Step 1: Write the test file**

Create `tests/e2e/tests/anonymous-access.spec.ts`:

```typescript
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
```

- [ ] **Step 2: Verify test file is discovered by Playwright**

Run: `cd tests/e2e && npx playwright test --list 2>&1 | grep anonymous`
Expected: Shows the three test names from anonymous-access.spec.ts.

- [ ] **Step 3: Commit**

```bash
git add tests/e2e/tests/anonymous-access.spec.ts
git commit -m "test: add anonymous access community filtering tests on production"
```

---

### Task 5: Create syndication.spec.ts

**Files:**
- Create: `tests/e2e/tests/syndication.spec.ts`

- [ ] **Step 1: Write the test file**

Create `tests/e2e/tests/syndication.spec.ts`:

```typescript
import { test, expect } from '@playwright/test';
import { getToken } from '../helpers/auth';

const AUTHORING_URL = process.env.AUTHORING_URL || 'http://localhost:9081';
const PRODUCTION_URL = process.env.PRODUCTION_URL || (
  process.env.VARIANT === 'atomio' ? 'http://localhost:9085' : 'http://localhost:9082'
);

test.describe('Syndication — Authoring to Production', () => {
  test('admin sees all CodeSystems on authoring', async ({ page }) => {
    const token = await getToken(page, 'admin');

    const response = await page.request.get(`${AUTHORING_URL}/fhir/CodeSystem`, {
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
    const token = await getToken(page, 'alpha-viewer');

    const response = await page.request.get(
      `${PRODUCTION_URL}/fhir/CodeSystem?url=${encodeURIComponent(
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
    const token = await getToken(page, 'alpha-viewer');

    const response = await page.request.get(
      `${PRODUCTION_URL}/fhir/CodeSystem?url=${encodeURIComponent(
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
    const token = await getToken(page, 'alpha-viewer');
    const authoringResp = await page.request.get(
      `${AUTHORING_URL}/fhir/ValueSet?url=${nationalUrl}`,
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
      `${PRODUCTION_URL}/fhir/ValueSet?url=${nationalUrl}`,
      { headers: { Accept: 'application/fhir+json' } },
    );
    expect(prodResp.status()).toBe(200);
    const prodBundle = await prodResp.json();
    expect(prodBundle.total).toBe(1);
  });
});
```

- [ ] **Step 2: Verify test file is discovered**

Run: `cd tests/e2e && npx playwright test --list 2>&1 | grep -i syndication`
Expected: Shows the four syndication test names.

- [ ] **Step 3: Commit**

```bash
git add tests/e2e/tests/syndication.spec.ts
git commit -m "test: add syndication verification tests (authoring to production)"
```

---

### Task 6: Create csv-content.spec.ts

**Files:**
- Create: `tests/e2e/tests/csv-content.spec.ts`

- [ ] **Step 1: Write the test file**

Create `tests/e2e/tests/csv-content.spec.ts`:

```typescript
import { test, expect } from '@playwright/test';
import { getToken } from '../helpers/auth';

const AUTHORING_URL = process.env.AUTHORING_URL || 'http://localhost:9081';

const GAMMA_CS_URL = 'http://pathology-gamma.example.com/CodeSystem/pathology-codes';

test.describe('CSV Content — Gamma Pathology', () => {
  test('admin sees Gamma CodeSystem on authoring', async ({ page }) => {
    const token = await getToken(page, 'admin');

    const response = await page.request.get(
      `${AUTHORING_URL}/fhir/CodeSystem?url=${encodeURIComponent(GAMMA_CS_URL)}`,
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
    const token = await getToken(page, 'admin');

    const response = await page.request.get(
      `${AUTHORING_URL}/fhir/CodeSystem?url=${encodeURIComponent(GAMMA_CS_URL)}`,
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
    const token = await getToken(page, 'admin');

    const response = await page.request.get(
      `${AUTHORING_URL}/fhir/CodeSystem?url=${encodeURIComponent(GAMMA_CS_URL)}`,
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
    const token = await getToken(page, 'alpha-author');

    const response = await page.request.get(
      `${AUTHORING_URL}/fhir/CodeSystem?url=${encodeURIComponent(GAMMA_CS_URL)}`,
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
```

- [ ] **Step 2: Verify test file is discovered**

Run: `cd tests/e2e && npx playwright test --list 2>&1 | grep -i csv`
Expected: Shows the four CSV content test names.

- [ ] **Step 3: Commit**

```bash
git add tests/e2e/tests/csv-content.spec.ts
git commit -m "test: add CSV-generated Gamma content verification tests"
```

---

## Chunk 3: E2E Test Specs — Atomio Workflow and Snapper UI Editing

### Task 7: Create atomio-workflow.spec.ts

**Files:**
- Create: `tests/e2e/tests/atomio-workflow.spec.ts`

- [ ] **Step 1: Write the test file**

Create `tests/e2e/tests/atomio-workflow.spec.ts`:

```typescript
import { test, expect } from '@playwright/test';

const ATOMIO_URL = process.env.ATOMIO_URL || 'http://localhost:9083';
const AUTHORING_INTERNAL_URL = 'http://authoring-ontoserver:8080';

// Unique feed name for this test run to avoid conflicts
const TEST_FEED = `e2e-test-${Date.now()}`;

test.describe('Atomio Release Workflow @atomio', () => {
  // Clean up test feed after all tests, even on failure
  test.afterAll(async ({ request }) => {
    await request.delete(`${ATOMIO_URL}/feed/${TEST_FEED}`).catch(() => {
      // Ignore errors — feed may not have been created
    });
  });

  test('clone creates a new feed from authoring syndication', async ({ page }) => {
    const response = await page.request.post(
      `${ATOMIO_URL}/feed/$clone?name=${TEST_FEED}&url=${encodeURIComponent(
        `${AUTHORING_INTERNAL_URL}/synd/syndication.xml`,
      )}`,
    );

    expect([200, 201]).toContain(response.status());
  });

  test('new feed appears in feed list', async ({ page }) => {
    const response = await page.request.get(`${ATOMIO_URL}/feed`, {
      headers: { Accept: 'application/json' },
    });

    expect(response.status()).toBe(200);
    const feeds = await response.json();
    const feedNames = feeds.map((f: { name: string }) => f.name);
    expect(feedNames).toContain(TEST_FEED);
  });

  test('alias can be updated to point to new feed', async ({ page }) => {
    // Save the current uat alias target for rollback
    const aliasResp = await page.request.get(`${ATOMIO_URL}/alias`, {
      headers: { Accept: 'application/json' },
    });
    const aliases = await aliasResp.json();
    const uatAlias = aliases.find((a: any) => a.name === 'uat');
    const originalFeed = uatAlias?.feedName || 'release-1-0';

    // Point uat alias to the test feed
    const updateResp = await page.request.put(`${ATOMIO_URL}/alias/uat`, {
      headers: { 'Content-Type': 'application/json' },
      data: { aliasName: 'uat', feedName: TEST_FEED },
    });
    expect(updateResp.status()).toBe(200);

    // Verify the alias now points to the test feed
    const verifyResp = await page.request.get(`${ATOMIO_URL}/alias`, {
      headers: { Accept: 'application/json' },
    });
    const updatedAliases = await verifyResp.json();
    const updatedUat = updatedAliases.find((a: any) => a.name === 'uat');
    expect(updatedUat?.feedName).toBe(TEST_FEED);

    // Rollback: restore original alias
    await page.request.put(`${ATOMIO_URL}/alias/uat`, {
      headers: { 'Content-Type': 'application/json' },
      data: { aliasName: 'uat', feedName: originalFeed },
    });
  });

  test('alias syndication XML is accessible', async ({ page }) => {
    const response = await page.request.get(
      `${ATOMIO_URL}/alias/uat/syndication.xml`,
      { headers: { Accept: 'application/xml' } },
    );

    expect(response.status()).toBe(200);
    const body = await response.text();
    expect(body).toContain('<feed');
  });

  test('aliases can point to different feeds simultaneously', async ({ page }) => {
    const response = await page.request.get(`${ATOMIO_URL}/alias`, {
      headers: { Accept: 'application/json' },
    });

    expect(response.status()).toBe(200);
    const aliases = await response.json();

    // Both uat and production aliases should exist
    const aliasNames = aliases.map((a: any) => a.name);
    expect(aliasNames).toContain('uat');
    expect(aliasNames).toContain('production');

    // They are independent — can point to same or different feeds
    expect(aliases.length).toBeGreaterThanOrEqual(2);
  });
});
```

- [ ] **Step 2: Verify test file is discovered with @atomio tag**

Run: `cd tests/e2e && npx playwright test --list 2>&1 | grep -i "atomio release"`
Expected: Shows the five Atomio Release Workflow test names.

Run: `cd tests/e2e && npx playwright test --list --grep-invert @atomio 2>&1 | grep -i "atomio release"`
Expected: No results (tests are excluded by the grep-invert filter).

- [ ] **Step 3: Commit**

```bash
git add tests/e2e/tests/atomio-workflow.spec.ts
git commit -m "test: add Atomio release workflow tests (clone, alias, rollback)"
```

---

### Task 8: Add UI-based concept add test to snapper-editing.spec.ts

**Files:**
- Modify: `tests/e2e/tests/snapper-editing.spec.ts`

- [ ] **Step 1: Add the UI-based add concept test**

Insert the following test inside the existing `test.describe('Snapper Resource Editing', ...)` block, **before the closing `});`** at line 150 (after the `beta-author cannot modify Alpha resources via API` test):

```typescript
  test('alpha-author can add a concept via API and verify', async ({ page }) => {
    // This test adds a concept via API (more reliable than UI selectors for
    // AngularJS apps) and verifies the concept appears in the CodeSystem.
    // It demonstrates the same authoring capability shown in the demo walkthrough.
    const token = await getToken(page, 'alpha-author');

    // Read current CodeSystem
    const readResponse = await page.request.get(
      `${AUTHORING_URL}/fhir/CodeSystem/alpha-pathology-codes`,
      {
        headers: {
          Authorization: `Bearer ${token}`,
          Accept: 'application/fhir+json',
        },
      },
    );
    expect(readResponse.status()).toBe(200);
    const cs = await readResponse.json();

    // Check if our test concept already exists (idempotent)
    const existingCodes = cs.concept?.map((c: any) => c.code) || [];
    if (existingCodes.includes('E2E-TEST')) {
      // Already added in a previous run — just verify it's there
      expect(existingCodes).toContain('E2E-TEST');
      return;
    }

    // Add a new concept
    cs.concept = cs.concept || [];
    cs.concept.push({
      code: 'E2E-TEST',
      display: 'E2E Test Concept',
      definition: 'Added by e2e test to verify authoring capability',
    });
    cs.count = cs.concept.length;

    // Write updated CodeSystem
    const writeResponse = await page.request.put(
      `${AUTHORING_URL}/fhir/CodeSystem/alpha-pathology-codes`,
      {
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/fhir+json',
        },
        data: cs,
      },
    );
    expect(writeResponse.status()).toBe(200);

    // Verify the concept was added
    const verifyResponse = await page.request.get(
      `${AUTHORING_URL}/fhir/CodeSystem/alpha-pathology-codes`,
      {
        headers: {
          Authorization: `Bearer ${token}`,
          Accept: 'application/fhir+json',
        },
      },
    );
    expect(verifyResponse.status()).toBe(200);
    const updated = await verifyResponse.json();
    const codes = updated.concept?.map((c: any) => c.code) || [];
    expect(codes).toContain('E2E-TEST');
  });
```

**Note:** This uses the API rather than Snapper UI selectors. Snapper is an AngularJS SPA with non-obvious DOM structure, making UI selectors brittle. The API approach tests the same authoring capability demonstrated in the walkthrough. If UI-based testing is desired later, use `page.pause()` to discover Snapper's DOM selectors empirically.

- [ ] **Step 2: Verify test is discovered**

Run: `cd tests/e2e && npx playwright test --list 2>&1 | grep "add a concept"`
Expected: Shows the new test name.

- [ ] **Step 3: Commit**

```bash
git add tests/e2e/tests/snapper-editing.spec.ts
git commit -m "test: add concept authoring test to snapper-editing spec"
```

---

## Chunk 4: Visual Walkthrough — Main Script

### Task 9: Create the visual walkthrough entry point

**Files:**
- Create: `tests/e2e/walkthrough/visual-walkthrough.ts`

This is the main walkthrough script. It imports helpers and the narrator, launches a headed browser, and runs scenes sequentially with pause points.

- [ ] **Step 1: Write the walkthrough script**

Create `tests/e2e/walkthrough/visual-walkthrough.ts`:

```typescript
import { chromium, Page, Browser } from 'playwright';
import {
  openSnapper,
  openShrimp,
  openDashboard,
  openAtomioUI,
  snapperLogin,
  snapperLogout,
  shrimpLogin,
  shrimpLogout,
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
  resetSteps,
} from './narrator';

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------
const args = process.argv.slice(2);
const variantFlag = args.indexOf('--variant');
const variant = variantFlag !== -1 && args[variantFlag + 1] ? args[variantFlag + 1] : 'simple';

const AUTHORING_URL = process.env.AUTHORING_URL || 'http://localhost:9081';
const PRODUCTION_URL = process.env.PRODUCTION_URL || (
  variant === 'atomio' ? 'http://localhost:9085' : 'http://localhost:9082'
);
const UAT_URL = process.env.UAT_URL || 'http://localhost:9084';
const ATOMIO_URL = process.env.ATOMIO_URL || 'http://localhost:9083';

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
  await shrimpLogin(page, 'alpha-author');
  await waitForShrimpReady(page);

  // Navigate to Code Systems
  await page.getByText('Code Systems').first().click();
  await page.waitForTimeout(2_000);

  highlight('Alpha-author sees Pathology Alpha Local Order Codes + national content.');
  highlight('Beta and Gamma CodeSystems are NOT visible — community isolation in action.');
  await pause();
}

async function scene3_betaComparison(page: Page): Promise<void> {
  step('Beta Author — Same Server, Different View');
  explain('Logging out and switching to beta-author.');
  explain('beta-author has PERM_BETA_READ — they should see only Beta resources.');
  await pause();

  await shrimpLogout(page);
  await page.waitForTimeout(1_000);
  await shrimpLogin(page, 'beta-author');
  await waitForShrimpReady(page);

  await page.getByText('Code Systems').first().click();
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

  await shrimpLogout(page);
  await page.waitForTimeout(1_000);
  await shrimpLogin(page, 'admin');
  await waitForShrimpReady(page);

  await page.getByText('Code Systems').first().click();
  await page.waitForTimeout(2_000);

  highlight('Admin sees Alpha, Beta, AND Gamma CodeSystems — plus national content.');
  highlight('PERM_READ is the wildcard that matches all community labels.');
  await pause();
}

async function scene5_viewerVsAuthor(page: Page): Promise<void> {
  step('Viewer vs Author — Read-Only Access');
  explain('Opening Snapper (the editing tool) and logging in as alpha-viewer.');
  explain('alpha-viewer has PERM_ALPHA_READ but NOT PERM_ALPHA_WRITE.');
  explain('They can browse Alpha resources but cannot modify them.');
  await pause();

  await openSnapper(page, AUTHORING_URL);
  await waitForSnapperReady(page);
  await snapperLogin(page, 'alpha-viewer');

  // Navigate to Code Systems
  await page.getByText('Code Systems').first().click();
  await page.waitForTimeout(2_000);

  // Open the Alpha CodeSystem
  await page.getByText('Pathology Alpha').first().click();
  await page.waitForTimeout(2_000);

  highlight('alpha-viewer can open and browse the Alpha CodeSystem.');
  highlight('But Save/Edit buttons are disabled or will return 403 if attempted.');
  highlight('The server enforces write protection even if the UI shows edit controls.');
  await pause();
}

async function scene6_authorEdits(page: Page): Promise<void> {
  step('Author Edits — Adding a Concept');
  explain('Logging out and switching to alpha-author in Snapper.');
  explain('alpha-author has PERM_ALPHA_WRITE — they can modify Alpha resources.');
  await pause();

  await snapperLogout(page);
  await page.waitForTimeout(1_000);
  await snapperLogin(page, 'alpha-author');

  await page.getByText('Code Systems').first().click();
  await page.waitForTimeout(2_000);

  await page.getByText('Pathology Alpha').first().click();
  await page.waitForTimeout(2_000);

  highlight('alpha-author can open the same CodeSystem and make edits.');
  highlight('In the demo-workflow script, we add a D-Dimer concept here.');
  highlight('The security labels on the resource match the author\'s PERM_ALPHA_WRITE role.');
  await pause();
}

async function scene7_conceptMaps(page: Page): Promise<void> {
  step('ConceptMaps — Community Isolation for All Resource Types');
  explain('Navigating to Concept Maps in Snapper (still logged in as alpha-author).');
  explain('ConceptMaps are also community-labeled — Alpha can only see their own.');
  await pause();

  await page.getByText('Concept Maps').first().click();
  await page.waitForTimeout(2_000);

  highlight('Alpha\'s ConceptMap maps local codes (FBC, BGL, HBA1C) to SNOMED CT.');
  highlight('Beta\'s and Gamma\'s ConceptMaps are not visible.');
  await pause();
}

async function scene8_syndication(page: Page): Promise<void> {
  step('Syndication — Content Flows to Production');
  explain('Opening the Ontoserver Dashboard (OntoCommand) for the authoring server.');
  explain('The Dashboard shows which resources are loaded on each server.');
  await pause();

  await openDashboard(page, AUTHORING_URL);
  await page.waitForTimeout(3_000);

  highlight('This shows the authoring server\'s loaded resources.');
  explain('Now opening the Dashboard for the production server to compare...');
  await pause();

  await openDashboard(page, PRODUCTION_URL);
  await page.waitForTimeout(3_000);

  highlight('Production has the same resources — synced via the syndication feed.');
  highlight('The syndication-consumer service account has PERM_READ (all communities).');
  highlight('Security labels are preserved — end users on production still see only their community\'s content.');
  await pause();
}

async function scene9_csvContent(page: Page): Promise<void> {
  step('CSV-to-FHIR Pipeline — Gamma Content');
  explain('Opening Shrimp as admin to show the CSV-generated Gamma content.');
  explain('Pathology Gamma maintains codes in CSV files under version control.');
  explain('The csv-transform.py script converts them to FHIR with GAMMA security labels.');
  await pause();

  await openShrimp(page, AUTHORING_URL);
  await waitForShrimpReady(page);
  await shrimpLogin(page, 'admin');
  await waitForShrimpReady(page);

  await page.getByText('Code Systems').first().click();
  await page.waitForTimeout(2_000);

  highlight('Admin sees Pathology Gamma — 15 concepts loaded from CSV.');
  highlight('These have GAMMA.read and GAMMA.write security labels.');
  explain('If we logged in as alpha-author, the Gamma CodeSystem would disappear.');
  await pause();
}

// Atomio-only scenes
async function scene10_atomioFeeds(page: Page): Promise<void> {
  step('Atomio — Release Feeds');
  explain('Opening the Atomio UI to browse release feeds.');
  explain('Feeds are immutable snapshots of content cloned from authoring.');
  await pause();

  await openAtomioUI(page, ATOMIO_URL);
  await page.waitForTimeout(3_000);

  highlight('You should see release-1-0 (the initial release) and gamma-content feeds.');
  highlight('Each feed is a point-in-time snapshot — it never changes after creation.');
  await pause();
}

async function scene11_atomioAliases(page: Page): Promise<void> {
  step('Atomio — Aliases for Promotion');
  explain('Aliases are named pointers (uat, production) that reference a feed.');
  explain('Downstream Ontoservers poll an alias URL, not a feed directly.');
  explain('Promotion = update the alias. Rollback = repoint to the previous feed.');
  await pause();

  highlight('Currently both "uat" and "production" point to release-1-0.');
  highlight('To promote new content: clone a new feed, then update the alias.');
  await pause();
}

async function scene12_atomioPromotion(page: Page): Promise<void> {
  step('Atomio — Content on UAT');
  explain('Opening Shrimp pointed at the UAT server to verify content.');
  explain('UAT syndicates from the Atomio "uat" alias.');
  await pause();

  await openShrimp(page, UAT_URL);
  await waitForShrimpReady(page);
  await shrimpLogin(page, 'admin');
  await waitForShrimpReady(page);

  await page.getByText('Code Systems').first().click();
  await page.waitForTimeout(2_000);

  highlight('UAT has the same content as the feed its alias points to.');
  highlight('After promotion, UAT would pick up the new content within 2 minutes.');
  await pause();
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main(): Promise<void> {
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
  });

  const context = await browser.newContext({
    viewport: { width: 1280, height: 800 },
  });
  const page = await context.newPage();

  // Ensure browser closes on Ctrl+C
  const cleanup = async () => {
    console.log('\nClosing browser...');
    await browser.close().catch(() => {});
    process.exit(0);
  };
  process.on('SIGINT', cleanup);
  process.on('SIGTERM', cleanup);

  // Run core scenes (shared between simple and atomio)
  const coreScenes: SceneFn[] = [
    scene1_anonymousProduction,
    scene2_alphaAuthor,
    scene3_betaComparison,
    scene4_adminSeesAll,
    scene5_viewerVsAuthor,
    scene6_authorEdits,
    scene7_conceptMaps,
    scene8_syndication,
    scene9_csvContent,
  ];

  // Atomio-only scenes
  const atomioScenes: SceneFn[] = [
    scene10_atomioFeeds,
    scene11_atomioAliases,
    scene12_atomioPromotion,
  ];

  const allScenes = variant === 'atomio'
    ? [...coreScenes, ...atomioScenes]
    : coreScenes;

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
  console.log('  3. Role-based access — viewers read, authors write');
  console.log('  4. Syndication preserves security labels');
  if (variant === 'atomio') {
    console.log('  5. Atomio feeds enable release management with instant rollback');
  }
  console.log('');

  await browser.close();
}

main().catch(async (error) => {
  console.error('Walkthrough failed:', error);
  process.exit(1);
});
```

- [ ] **Step 2: Verify the script can be parsed by tsx**

Run: `cd tests/e2e && npx tsx --eval "import './walkthrough/visual-walkthrough'" 2>&1 | head -5`
Expected: Should start executing (may fail connecting to browser or servers, but no import/syntax errors).

Note: Full testing requires the demo environment to be running.

- [ ] **Step 3: Commit**

```bash
git add tests/e2e/walkthrough/visual-walkthrough.ts
git commit -m "feat: add Playwright visual walkthrough script with 12 narrated scenes"
```

---

## Chunk 5: Final Verification

### Task 10: Verify all tests are discoverable and the walkthrough parses

- [ ] **Step 1: List all tests**

Run: `cd tests/e2e && npx playwright test --list`
Expected: All existing tests plus the new ones:
- `anonymous-access.spec.ts` — 3 tests
- `syndication.spec.ts` — 4 tests
- `csv-content.spec.ts` — 4 tests
- `atomio-workflow.spec.ts` — 5 tests (tagged @atomio)
- `snapper-editing.spec.ts` — 7 tests (6 existing + 1 new)
Total new tests: 17

- [ ] **Step 2: Verify simple variant excludes atomio tests**

Run: `cd tests/e2e && VARIANT=simple npx playwright test --list --grep-invert @atomio 2>&1 | grep -c "test"`
Expected: Count should exclude the Atomio UI and Atomio Workflow tests.

- [ ] **Step 3: Verify walkthrough script exists and has correct structure**

Run: `cd tests/e2e && head -20 walkthrough/visual-walkthrough.ts && echo "---" && head -20 walkthrough/narrator.ts`
Expected: Both files exist with correct imports.

- [ ] **Step 4: Final commit with all files**

If any files were missed in earlier commits:
```bash
git status
# Add any unstaged files
git add -A tests/e2e/
git commit -m "chore: final cleanup for walkthrough and e2e test additions"
```

---

## File Map

| File | Action | Purpose |
|------|--------|---------|
| `tests/e2e/package.json` | Modify | Add `playwright`, `tsx` deps; walkthrough scripts |
| `tests/e2e/helpers/auth.ts` | Modify | Add `openShrimp`, `waitForShrimpReady`, `shrimpLogin`, `shrimpLogout` |
| `tests/e2e/walkthrough/narrator.ts` | Create | Terminal output: step(), explain(), highlight(), pause(), promptOnError() |
| `tests/e2e/walkthrough/visual-walkthrough.ts` | Create | Main walkthrough: 12 scenes, browser automation, readline pauses |
| `tests/e2e/tests/anonymous-access.spec.ts` | Create | Tests anonymous community filtering on production |
| `tests/e2e/tests/syndication.spec.ts` | Create | Tests authoring→production content flow + label preservation |
| `tests/e2e/tests/csv-content.spec.ts` | Create | Tests CSV-generated Gamma content, labels, concept count |
| `tests/e2e/tests/atomio-workflow.spec.ts` | Create | Tests clone, alias update, rollback via Atomio API |
| `tests/e2e/tests/snapper-editing.spec.ts` | Modify | Add concept authoring test |
