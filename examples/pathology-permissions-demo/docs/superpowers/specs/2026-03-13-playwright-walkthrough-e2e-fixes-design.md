# Playwright Visual Walkthrough + E2E Test Fixes

## Summary

Two deliverables built on the existing Playwright e2e infrastructure:

1. **Visual walkthrough** — a standalone script that drives a headed browser through demo scenarios with terminal narration and pause points, suitable for live presentations.
2. **E2E test gap fixes** — new test specs covering demo scenarios not currently tested (anonymous access, syndication, CSV content, Atomio workflow).

## Visual Walkthrough

### Architecture

A standalone TypeScript script using Playwright's library API (not the test runner). This avoids test timeouts, assertions, and parallel execution — the walkthrough is sequential and presenter-controlled.

**Files:**

- `tests/e2e/walkthrough/visual-walkthrough.ts` — main entry point, scene orchestration
- `tests/e2e/walkthrough/narrator.ts` — terminal output utilities (colored step headers, explanations, readline pauses)
- `tests/e2e/helpers/auth.ts` — extended with `openShrimp()`, `shrimpLogin()`, `shrimpLogout()`

**Execution:**

```bash
cd tests/e2e/
npx tsx walkthrough/visual-walkthrough.ts                  # defaults to simple
npx tsx walkthrough/visual-walkthrough.ts --variant atomio # includes Atomio scenes
```

**Browser configuration:**

- `chromium.launch({ headless: false, slowMo: 500 })` — visible, slow enough to follow
- Single browser context, single page — presenter sees one window
- Viewport sized to 1280x800 for readable web tool UI

### Narrator Module

`walkthrough/narrator.ts` exports:

- `step(title: string)` — prints a numbered step header with cyan box border
- `explain(text: string)` — prints blue explanation text
- `highlight(text: string)` — prints green highlighted observation text
- `pause(message?: string)` — readline-based "Press Enter to continue..." prompt
- `warn(text: string)` — prints yellow warning (used for error recovery)

All output goes to stdout with ANSI color codes matching the demo-workflow.sh style.

### Scenes

Each scene follows the pattern: narrate → act → observe → pause.

| # | Scene | Browser Actions | Narration Focus |
|---|-------|----------------|-----------------|
| 1 | Anonymous production | Open Shrimp→production (no login), browse CodeSystems | National content visible, community content hidden |
| 2 | Alpha author login | Shrimp→authoring, login as alpha-author, click Code Systems | Alpha sees only their resources + national |
| 3 | Beta comparison | Logout, login as beta-author, click Code Systems | Same server, different view — Beta resources only |
| 4 | Admin sees all | Logout, login as admin, click Code Systems | Admin has wildcard PERM_READ, sees Alpha+Beta+Gamma |
| 5 | Viewer vs Author | Open Snapper→authoring, login as alpha-viewer, open Alpha CS, show read-only state | Viewer can browse but not edit (Save button hidden or disabled, or 403 on attempt) |
| 6 | Author edits | Logout, login as alpha-author, add D-DIM concept, save | Author can modify their community's resources |
| 7 | ConceptMaps | Navigate to Concept Maps tab | Community isolation applies to all resource types |
| 8 | Syndication | Open OntoCommand→authoring (admin), then →production | Content synced, same resources on both servers |
| 9 | CSV content | Shrimp→authoring as admin, find Gamma CS | CSV-generated content loaded with GAMMA security labels |
| 10 | Atomio feeds | (atomio only) Open Atomio UI, browse feeds | Immutable snapshots of content |
| 11 | Atomio aliases | (atomio only) Browse aliases, show uat/production pointers | Alias indirection enables promotion/rollback |
| 12 | Atomio promotion | (atomio only) Show UAT content via Shrimp→UAT | Content flows through alias to downstream servers |

### Error Handling

If a browser action fails (selector not found, timeout):
1. Narrator prints a yellow warning with the error
2. Offers three options: `[r]etry / [s]kip / [q]uit`
3. Retry re-attempts the failed action; skip moves to the next scene; quit exits cleanly

Process exit handler closes the browser on Ctrl+C.

### Helper Additions

Added to `tests/e2e/helpers/auth.ts`:

- `openShrimp(page, fhirServerUrl)` — navigates to `https://ontoserver.csiro.au/shrimp?iss={url}`, waits for load
- `shrimpLogin(page, username, password)` — clicks login, fills Ontocloak form, waits for redirect back to Shrimp
- `shrimpLogout(page)` — clicks logout if visible

Shrimp uses the same SMART-on-FHIR authentication flow as Snapper — it redirects to Ontocloak for login. The `shrimpLogin` helper follows the same pattern as `snapperLogin`: click the login/authorize button, wait for redirect to Ontocloak, fill credentials, wait for redirect back to Shrimp (matching `/shrimp/` in the URL instead of `/snapper/`). The `shrimpLogout` helper similarly mirrors `snapperLogout`.

**Note on Shrimp selectors:** Shrimp is an AngularJS application. Login/logout button selectors and the Code Systems navigation may differ from Snapper. The implementer should use `page.pause()` during development to inspect the Shrimp DOM and identify correct selectors empirically. Use broad role-based or text-based selectors (e.g., `getByRole('button', { name: /login/i })`) for resilience.

### Walkthrough TypeScript / Import Strategy

The walkthrough uses Playwright's **library API** (`playwright` or `playwright-core`), not `@playwright/test`. However, the existing `helpers/auth.ts` imports `Page` and `expect` from `@playwright/test`.

To resolve this without duplicating helpers:
- The `Page` type from `@playwright/test` is compatible with the library API's `Page` type (they are the same underlying type)
- `tsx` can resolve these imports without a `tsconfig.json` since `@playwright/test` re-exports from `playwright-core`
- The walkthrough script imports `chromium` from `playwright` (the library package) for `chromium.launch()`, and imports helpers from `../helpers/auth` which use the `Page` type from `@playwright/test`
- Add `playwright` as a dev dependency alongside `@playwright/test` (the test package already depends on it, but an explicit dependency ensures the library API is importable)

### Walkthrough Environment Variables

The walkthrough uses the same environment variables and defaults as the e2e tests:
- `ONTOCLOAK_URL` (default: `http://localhost:9090`)
- `AUTHORING_URL` (default: `http://localhost:9081`)
- `PRODUCTION_URL` (default: `http://localhost:9082` for simple, `http://localhost:9085` for atomio)
- `UAT_URL` (default: `http://localhost:9084`, atomio only)
- `ATOMIO_URL` (default: `http://localhost:9083`, atomio only)

## E2E Test Fixes

### New Test Specs

**`tests/anonymous-access.spec.ts`**

Tests the demo scenario: anonymous users see national content but not community content.

- Anonymous GET on production: Alpha CodeSystem returns total=0
- Anonymous GET on production: Beta CodeSystem returns total=0
- (All via Playwright's `page.request` API, no browser UI needed)

**Note:** The test "production allows anonymous read of national valueset" already exists in `ontoserver-dashboard.spec.ts`. It is NOT duplicated here — only the community-filtering tests are new.

**`tests/syndication.spec.ts`**

Tests the demo scenario: content flows from authoring to production preserving security labels.

- Admin on authoring sees Alpha, Beta, Gamma CodeSystems via API
- Authenticated Alpha user on production sees Alpha CodeSystem (syndicated)
- Authenticated Alpha user on production cannot see Beta CodeSystem (labels preserved)
- National valueset exists on both authoring and production

**`tests/csv-content.spec.ts`**

Tests the demo scenario: CSV-generated Gamma content is loaded with correct labels.

- Admin on authoring sees Gamma CodeSystem via API
- Gamma CodeSystem has GAMMA.read and GAMMA.write security labels
- Gamma CodeSystem has expected concept count (15)
- Alpha user on authoring cannot see Gamma CodeSystem (community isolation)

**`tests/atomio-workflow.spec.ts`** (tagged `@atomio` in the describe block name, e.g., `test.describe('Atomio Release Workflow @atomio', ...)`)

Tests the demo scenario: release candidate management via Atomio API.

- Clone feed creates new feed (POST /feed/$clone?name=test-release&url=...)
- New feed appears in feed list (GET /feed)
- Alias update changes feed pointer (PUT /alias/{name} with body `{"aliasName": "uat", "feedName": "test-release"}`) — **Note:** Atomio uses `aliasName`/`feedName` fields in request JSON, not `name`/`feed`
- Alias syndication XML is accessible after update (GET /alias/{name}/syndication.xml)
- Rollback (repoint alias to previous feed) succeeds
- Both aliases can point to different feeds simultaneously
- Cleanup via `test.afterAll()` to ensure test feeds are deleted even on failure (DELETE /feed/{name})

**Updates to `snapper-editing.spec.ts`**

- New test: alpha-author opens Alpha CodeSystem in Snapper UI, clicks Add Concept, fills code/display/definition, clicks Save, verifies success (200 status or no error banner)
- **Note on Snapper selectors:** Snapper is an AngularJS SPA with non-obvious DOM structure. The implementer should use `page.pause()` to inspect the DOM and identify selectors for the "Add Concept" button, code/display/definition input fields, and Save button empirically. Use text-based or role-based selectors where possible. If the DOM makes reliable UI testing infeasible, fall back to an API-based test that reads the CodeSystem, adds a concept via jq-style manipulation, PUTs it back, and verifies the new concept appears.

### Test Organization

All new specs follow existing patterns:
- Import helpers from `../helpers/auth`
- Use environment variables for server URLs with sensible defaults
- Atomio-specific tests tagged with `@atomio`
- `test:simple` script excludes `@atomio` tagged tests
- Workers: 1 (sequential, same as current config)

### package.json Updates

Add `tsx` as a dev dependency for running the walkthrough:

```json
"devDependencies": {
  "@playwright/test": "^1.45.0",
  "@types/node": "^25.3.5",
  "playwright": "^1.45.0",
  "tsx": "^4.0.0"
}
```

`playwright` (the library package) is needed for the walkthrough's `chromium.launch()` call. `@playwright/test` re-exports from `playwright-core` but doesn't expose the top-level `chromium` launcher directly.

Add walkthrough script:

```json
"scripts": {
  "walkthrough": "npx tsx walkthrough/visual-walkthrough.ts",
  "walkthrough:atomio": "npx tsx walkthrough/visual-walkthrough.ts --variant atomio"
}
```
