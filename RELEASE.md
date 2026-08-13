# Releasing the Helm charts

The three charts under `charts/` are versioned and released **independently**. Release Please is the
normal path; everything else in this document is fallback and recovery.

- [The normal flow](#the-normal-flow-release-please)
- [How the three charts stay separate](#how-the-three-charts-stay-separate)
- [What lands where](#what-lands-where)
- [Conventions you must not break](#conventions-you-must-not-break)
- [Release PRs and workflow approval (GitHub App token)](#release-prs-and-workflow-approval-github-app-token)
- [Manual release (`release.sh`)](#manual-release-releasesh)
- [Recovery](#recovery)
- [Artifact Hub](#artifact-hub)
- [Current versions](#current-versions)

---

## The normal flow (Release Please)

You never edit a version number or stamp a changelog by hand. The flow is:

1. **Merge normal work to `master`** using [Conventional Commits](https://www.conventionalcommits.org/).
2. **Release Please opens a release PR for each chart you touched** — automatically, on every push to
   `master`. The PR shows the version it will cut and the changelog it will write.
3. **Review the PR.** This is the moment to sanity-check the computed version. If the bump looks
   wrong, the fix is a commit message convention problem, not a manual edit — see below.
4. **Merge the release PR.** That single merge does everything: stamps `changelog.md`, bumps
   `Chart.yaml`, tags `<chart>-vX.Y.Z`, creates the GitHub Release with generated notes, then
   packages the chart and publishes it to the Helm repo index and GHCR.

Leave a release PR open as long as you like — Release Please keeps amending it as more commits land.
Merging it is the act of releasing.

### How version numbers are computed

| Commit prefix | Effect |
|---|---|
| `fix:` | patch — 0.4.0 → 0.4.1 |
| `feat:` | minor — 0.4.0 → 0.5.0 |
| `feat!:` or `BREAKING CHANGE:` | **minor** while below 1.0.0 — 0.4.0 → 0.5.0, *not* 1.0.0 |
| `docs:`, `refactor:`, `perf:`, `revert:` | appear in the changelog, per `changelog-sections` |
| `test:`, `ci:`, `chore:` | hidden, and do not trigger a release on their own |

Breaking changes give a minor bump because `bump-minor-pre-major: true` is set — appropriate while
the charts are pre-1.0. Remove that flag when a chart is ready to promise stability.

> If Release Please opens no PR after you pushed chart changes, your commits were all hidden types
> (`chore:`, `ci:`, `test:`). That is working as intended, not a bug.

## How the three charts stay separate

**Release Please decides what to bump from the file paths a commit touches, not from the commit
scope.** This is the single most important thing to understand:

- A commit touching only `charts/ontoserver-indexer/` opens a release PR for the indexer alone.
- A commit touching two charts opens **two** PRs.
- `separate-pull-requests: true` keeps the PRs independent, so you can release one chart without
  dragging the others along.
- Commit **scopes are free-form**. `fix(indexer):` on a commit that edits `charts/ontoserver/` will
  release **ontoserver**. The scope is documentation for humans; the paths are what count.

Practical consequence: **keep a commit to one chart** where you can. A commit that sweeps all three
charts forces all three to release together.

- `always-update: true` keeps the open release PRs rebased on `master` as each one merges. All three
  edit the shared `.release-please-manifest.json`, so without it merging one leaves the rest
  conflicting — see [Recovery](#a-release-pr-conflicts-after-another-one-merged).

Configuration lives in `release-please-config.json` (what the packages are) and
`.release-please-manifest.json` (what version each is currently at).

## What lands where

Merging a release PR publishes to four places. All of it is automated in
`.github/workflows/release-please.yml`.

| Destination | What appears |
|---|---|
| Git tag | `<chart>-vX.Y.Z` |
| GitHub Release | notes generated from the commits, with the `.tgz` attached |
| Helm repo (`gh-pages`) | a new entry in `index.yaml`, plus the version badge on `index.html` |
| GHCR | `oci://ghcr.io/aehrc/<chart>-helm/<chart>` |

### The GHCR path repeats the chart name

Charts are *pushed* to `oci://ghcr.io/aehrc/<chart>-helm`, but `helm push` appends the chart name
from the package. The **pullable** reference therefore contains it twice:

```bash
helm show chart oci://ghcr.io/aehrc/ontoserver-helm/ontoserver --version 0.4.0   # correct
helm show chart oci://ghcr.io/aehrc/ontoserver-helm            --version 0.4.0   # not found
```

Beware when debugging: **GHCR also answers `not found` when your token lacks `read:packages`**, so a
local pull failure is not evidence that the push failed. Check the workflow log instead.

### Verifying a release actually landed

Workflow-green is not proof. Check the artifacts:

```bash
helm repo add ontoserver https://aehrc.github.io/ontoserver-deploy --force-update
helm repo update ontoserver
helm search repo ontoserver --versions

mkdir -p /tmp/pull && helm pull ontoserver/ontoserver --version X.Y.Z -d /tmp/pull
helm template t /tmp/pull/ontoserver-X.Y.Z.tgz > /dev/null && echo "renders"
```

## Conventions you must not break

### `Chart.yaml` holds the *last released* version

Under Release Please, `Chart.yaml` records what **is** released; the open release PR is the pending
version. There is **no standing `## [Unreleased]` changelog section** — merging the PR creates the
version heading.

> This **inverted** the older `release.sh` convention, where `Chart.yaml` held the *in-development*
> version and the changelog carried `## [Unreleased]`. Documentation or habits from before
> 2026-08-12 will have it the other way round.

### The manifest and `Chart.yaml` must agree

Every `version:` in `charts/*/Chart.yaml` must match its entry in `.release-please-manifest.json`.
If they drift, Release Please computes the next version from the **manifest** while the chart claims
something else, and the two disagree about what is published. Don't hand-edit either one.

### Publishing lives in `release-please.yml` deliberately

A tag created with `GITHUB_TOKEN` **does not trigger other workflows**. So the tag-triggered
`release.yml` would never fire for a Release Please tag — the chart would be tagged and
GitHub-Released but never reach the Helm index or GHCR, a silent half-release. Publishing therefore
runs inside the same workflow that creates the tag.

Both workflows share the `release-charts` concurrency group, because both rewrite `index.yaml` on
`gh-pages`.

### Releases are gated on tests

Neither path publishes unless the **Unit Tests** and **Integration Tests** runs for that exact commit
succeeded. The test workflows trigger on `branches: ['**']`, which excludes tags, so the gate looks
up the runs by commit SHA and polls for up to 10 minutes if one is still in flight.

If the gate reports *no run found*, the commit was never pushed to a branch. Push it before tagging.

## Release PRs and workflow approval (GitHub App token)

A PR opened with the default `GITHUB_TOKEN` cannot trigger workflow runs — GitHub's recursion guard.
On a release PR that shows up two ways:

- its `pull_request` checks queue at **action_required** until a human clicks approve;
- **Integration Tests never runs on a release PR at all**, because it triggers on `push` only and
  the bot's push is suppressed. The suite only runs after the merge, against master.

`release-please.yml` will author its PRs as a GitHub App when one is configured, which makes both
events fire normally. It is optional: with the variable unset the step is skipped and the action
falls back to `GITHUB_TOKEN`, behaving exactly as before. To switch over — no workflow edit needed:

1. Create a GitHub App under the **aehrc** org (Settings → Developer settings → GitHub Apps).
   Permissions: **Contents: Read and write**, **Pull requests: Read and write**,
   **Issues: Read and write** (Release Please labels its PRs, and labels are the issues API).
2. Install it on `aehrc/ontoserver-deploy`, and generate a private key.
3. Add repo **variable** `RELEASE_PLEASE_APP_ID` (the numeric App ID) and repo **secret**
   `RELEASE_PLEASE_APP_PRIVATE_KEY` (the whole PEM, `BEGIN`/`END` lines included).

Verify by pushing a chart change: the release PR's author becomes the App, and its checks — now
including Integration Tests — start without an approval prompt.

## Manual release (`release.sh`)

Kept for recovery and for releasing from a feature branch. **It still follows the old convention** —
it bumps `Chart.yaml` past the release and re-adds `## [Unreleased]`, which will put the manifest out
of step with `Chart.yaml`. If you use it, reconcile `.release-please-manifest.json` afterwards.

```bash
./charts/release.sh <chart>                    # interactive, prompts for the next version
./charts/release.sh <chart> --patch            # or --minor / --major / --auto-increment
./charts/release.sh <chart> --next-version 1.0.0
./charts/release.sh <chart> --dry-run          # preview, writes nothing
./charts/release.sh <chart> --allow-any-branch # release from somewhere other than master
```

It checks every precondition **before writing anything** — clean tree, on `master`, branch not
behind or diverged from upstream, tag absent locally and remotely — because steps 2–5 are not
atomic. The tag is pushed before the bump commit, so a precondition failing midway would leave
either a stray commit or a published release with no bump.

### ⚠️ Push release tags one at a time

`cancel-in-progress: false` does **not** give the `release-charts` group an unbounded queue. GitHub
holds at most one *running* plus one *pending* run per group, and **a third arrival cancels the
pending one**. Pushing all three tags together (observed 2026-08-12) left the middle run cancelled.

The damage is contained: `chart-releaser` packages every chart with `skip_existing: true`, so the
first surviving run creates all the GitHub Releases and the merged `index.yaml`. What a cancelled
run loses is its own `index.html` badge bump and its GHCR push. Recover with `gh run rerun <id>` once
the group is free — the tag still exists, so the re-run is safe and idempotent.

Release Please's publish job is immune: its `max-parallel: 1` matrix runs inside a *single* workflow
run, so charts serialise without queueing separate runs.

### Tag schemes

Two forms exist for historical reasons: `<chart>-vX.Y.Z` and `<chart>-X.Y.Z`. Only the **`-v` form**
triggers `release.yml`. The non-`v` form is created by `chart-releaser` as part of the release, so
both end up in the repo. Do not tag the non-`v` form by hand expecting a release.

## Recovery

### The workflow failed with 403

This happens when a re-run uses an old workflow commit from before the workflow-level `permissions:`
block existed. Re-runs always use the workflow as of the original tag commit, so the fix only applies
to future tags — an old tag must be recovered by hand.

### Publishing by hand

```bash
# 1. Extract and package the chart from the release tag
mkdir -p /tmp/chart-src /tmp/cr-packages
git archive <chart>-vX.Y.Z charts/<chart> | tar -x -C /tmp/chart-src/
helm dependency build /tmp/chart-src/charts/<chart>
helm package /tmp/chart-src/charts/<chart> -d /tmp/cr-packages/

# 2. Create the GitHub Release
gh release create <chart>-vX.Y.Z /tmp/cr-packages/<chart>-X.Y.Z.tgz \
  --repo aehrc/ontoserver-deploy \
  --title "<chart>-X.Y.Z" \
  --notes-file <(sed -n '/^## \[X.Y.Z\]/,/^## \[/p' charts/<chart>/changelog.md | sed '$d')

# 3. Push to GHCR
echo "$(gh auth token)" | helm registry login ghcr.io \
  --username "$(gh api user --jq .login)" --password-stdin
helm push /tmp/cr-packages/<chart>-X.Y.Z.tgz oci://ghcr.io/aehrc/<chart>-helm

# 4. Update the gh-pages index — --merge, or you delete every other chart version
git clone --branch gh-pages --single-branch \
  https://github.com/aehrc/ontoserver-deploy.git /tmp/gh-pages
helm repo index /tmp/cr-packages/ \
  --url https://github.com/aehrc/ontoserver-deploy/releases/download/<chart>-vX.Y.Z \
  --merge /tmp/gh-pages/index.yaml
mv /tmp/cr-packages/index.yaml /tmp/gh-pages/index.yaml
cd /tmp/gh-pages
sed -i "s|data-chart=\"<chart>\">[0-9][0-9.]*<|data-chart=\"<chart>\">X.Y.Z<|g" index.html
git add index.yaml index.html
git commit -m "Release <chart> X.Y.Z [skip ci]"
git push origin gh-pages
```

### A release PR conflicts after another one merged

Every release PR edits `.release-please-manifest.json`, so merging one used to leave the others
`CONFLICTING`. **`always-update: true` in `release-please-config.json` fixes this** — it is the
supported option for exactly this case:

> if true, always update existing pull requests when changes are added, instead of only when the
> release notes change. […] can be useful if pull requests must not be out-of-date with the base
> branch.

The default is `false`, which only rewrites a release branch when the *generated release notes*
change. Merging extras changes the shared manifest but not the indexer's notes, so the straggler was
left pointing at a stale base — and neither the post-merge run nor an explicit `workflow_dispatch`
repaired it (observed 2026-08-13, before the option was set). It costs extra API calls per run,
which is irrelevant at three charts.

Requires release-please ≥ 16.15.0; `release-please-action@v4` depends on `^17.6.1`, so it is live.

If you ever hit a conflict anyway, rebase by hand. The resolution is always the union: each chart's
own new version, plus whatever the merged release just published.

```bash
BR=release-please--branches--master--components--<chart>
git fetch origin && git checkout -B "$BR" "origin/$BR"
git rebase origin/master                 # conflicts in .release-please-manifest.json
# resolve: keep every chart at its highest version, then
git add .release-please-manifest.json && git rebase --continue
git push --force-with-lease origin "$BR"
```

Afterwards check the invariant before merging — every `version:` must equal its manifest entry:

```bash
cat .release-please-manifest.json
grep '^version:' charts/*/Chart.yaml
```

A useful side effect: the branch is now pushed by *you* rather than `GITHUB_TOKEN`, so its checks
run without needing manual approval, and Integration Tests covers the PR for once.

Avoid the whole situation by keeping a commit to one chart, so only one release PR is ever open.

### Marking a release as pre-release

Not automated — deliberately. Set it by hand if a chart needs it:

```bash
gh release edit <chart>-X.Y.Z --repo aehrc/ontoserver-deploy --prerelease   # mark
gh release edit <chart>-X.Y.Z --repo aehrc/ontoserver-deploy --latest       # promote to stable
```

### "Latest release" only ever shows one chart

GitHub's *Latest* marker is a **repository-wide singleton**, so a monorepo publishing three charts
can never mark all three. It lands on whichever non-prerelease release is newest by timestamp.
Nothing in the install path depends on it — `index.yaml` carries explicit per-version download URLs.
To pin it to the flagship chart:

```bash
gh release edit ontoserver-X.Y.Z --repo aehrc/ontoserver-deploy --latest
```

## Artifact Hub

[Artifact Hub](https://artifacthub.io) indexes the published Helm repository. It is a *pull* model:
once registered, it re-scans `https://aehrc.github.io/ontoserver-deploy/index.yaml` on a schedule
(roughly every 30 minutes) and picks up new versions with no action from us.

### One-time registration

1. Sign in at <https://artifacthub.io> with GitHub and create (or join) the **CSIRO AEHRC**
   organisation, so the charts are owned by the org rather than a personal account.
2. **Control Panel → Repositories → Add**, and enter:
   - Kind: **Helm charts**
   - Name: `ontoserver` (this becomes the URL slug, `artifacthub.io/packages/helm/ontoserver/...`)
   - URL: `https://aehrc.github.io/ontoserver-deploy`
3. Artifact Hub assigns a **repository ID** (a UUID). Copy it.
4. Put it in [`artifacthub-repo.yml`](artifacthub-repo.yml) at the repo root, uncommenting the key:

   ```yaml
   repositoryID: <uuid-from-the-control-panel>
   owners:
     - name: CSIRO AEHRC
       email: ontoserver-support@csiro.au
   ```

5. Commit and merge. Both release workflows copy that file to the `gh-pages` root, so it becomes
   reachable at `https://aehrc.github.io/ontoserver-deploy/artifacthub-repo.yml`.
6. Artifact Hub fetches it, matches the ID, and marks the repository **verified publisher**.

The file is already deployed to `gh-pages` and served — only the `repositoryID` is missing, so the
ownership claim is what is outstanding, not the plumbing.

### Per-chart metadata

Everything Artifact Hub shows comes from each chart's `Chart.yaml` and `README.md`, which are already
populated: `description`, `home`, `icon`, `sources`, `keywords`, `maintainers`, and the
`artifacthub.io/category` and `artifacthub.io/license` annotations.

⚠️ **`artifacthub.io/changes` is hand-maintained and Release Please does not touch it.** The
annotation describes the version in `version:` above it, but a release PR bumps `version:` and leaves
the annotation alone — so it silently goes stale and starts describing the *previous* release. Either
update it in the release PR before merging, or drop the annotation and let the changelog and the
generated GitHub Release notes carry that information.

### Optional annotations worth knowing

| Annotation | Use |
|---|---|
| `artifacthub.io/prerelease: "true"` | flags the chart version as a pre-release |
| `artifacthub.io/images` | lists container images so Artifact Hub can run security scans |
| `artifacthub.io/crds` / `artifacthub.io/crdsExamples` | documents CRDs the chart expects |
| `artifacthub.io/links` | extra links (changelog, support, docs) |
| `artifacthub.io/signKey` | provenance key, if charts are ever signed |
| `artifacthub.io/containsSecurityUpdates: "true"` | highlights a security release |

### Notes

- The chart icons resolve from `master` over `raw.githubusercontent.com` and are live, but they are
  ~800 KB at ~1030×900 px. Artifact Hub accepts them; downscaling to 256×256 would render faster.
- Artifact Hub reads only the **Helm repo index**, not GHCR and not the GitHub Releases. A release
  that reached GitHub but not `index.yaml` will not appear.

## Current versions

| Chart | Latest release | Notes |
|---|---|---|
| `ontoserver` | **0.4.1** | |
| `ontoserver-extras` | **0.1.2** | |
| `ontoserver-indexer` | **0.2.1** | |

The 0.4.1 / 0.1.2 / 0.2.1 round fixed a `.helmignore` that excluded `README.md` from the packaged
charts, so Artifact Hub had no README to render. 0.4.0 was the breaking release that removed the
bundled nginx-ingress subchart.

Releases 0.1.0–0.3.0 are flagged pre-release on GitHub; 0.4.0 / 0.1.1 / 0.2.0 are normal releases.

Release Please was adopted on 2026-08-12. Those three versions were tagged and published by hand as
the `update-charts` branch merged, because the manifest asserts them as already released. That
one-time adoption step is complete.
