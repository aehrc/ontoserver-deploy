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
