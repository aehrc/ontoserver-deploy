# Claude Code Notes — ontoserver-deploy

## Releasing a chart

Two mechanisms exist. **Release Please is the intended path**; `release.sh` and the tag-triggered
`release.yml` are kept for manual releases and recovery.

### Release Please (per-chart)

`release-please-config.json` + `.release-please-manifest.json` drive
`.github/workflows/release-please.yml`. On every push to `master`, Release Please maintains **one
open release PR per chart**. Merging a chart's PR stamps its `changelog.md`, bumps its `Chart.yaml`,
tags `<chart>-vX.Y.Z`, creates the GitHub Release, and then the same workflow packages that one
chart and publishes it to the gh-pages Helm index and GHCR.

**How the three charts stay separate:** Release Please decides what to bump from the **file paths** a
commit touches, not from the commit scope. A commit touching only `charts/ontoserver-indexer/` opens
a release PR for the indexer alone. `separate-pull-requests: true` keeps the PRs independent so one
chart can be released without dragging the others along. A commit touching two charts opens two PRs.

Version bumps come from Conventional Commits: `fix:` → patch, `feat:` → minor, `feat!:`/
`BREAKING CHANGE:` → **minor** while below 1.0.0 (`bump-minor-pre-major: true`), so a breaking change
gives 0.4.0 → 0.5.0 rather than 1.0.0. Commit scopes are free-form; only paths matter.

⚠️ **This inverts the old convention.** Under `release.sh`, `Chart.yaml` held the *in-development*
version. Under Release Please, `Chart.yaml` holds the **last released** version and the release PR
bumps it. `.release-please-manifest.json` must always agree with the `version:` in each `Chart.yaml`
— if they drift, Release Please computes the next version from the manifest and the two disagree
about what is released.

⚠️ **Publishing runs inside `release-please.yml`, deliberately.** A tag created with `GITHUB_TOKEN`
does not trigger other workflows, so the tag-triggered `release.yml` would never fire for a Release
Please tag — the chart would be tagged and GitHub-Released but never reach the Helm index or GHCR, a
silent half-release. Both workflows share the `release-charts` concurrency group because both rewrite
`index.yaml` on `gh-pages`.

Both paths gate on tests: publishing refuses unless the Unit Tests and Integration Tests runs for
that exact commit succeeded.

### Adoption — done

The manifest is seeded with `ontoserver 0.4.0`, `ontoserver-extras 0.1.1`, `ontoserver-indexer 0.2.0`,
matching the `Chart.yaml` files and the changelog entries stamped for this review. All three were
tagged and published by hand as the branch merged, so the manifest's claim that they are released is
true and Release Please bumps *past* them. Nothing further is needed; from here on the release PRs
do the stamping and bumping.

### Manual release (`release.sh`)

```bash
cd charts
bash release.sh <chart> [--patch|--minor|--major]
```

`release.sh` does the full release cycle in one command:
1. Checks all preconditions **before writing anything**: clean tree, on `master`, branch not behind
   or diverged from its upstream, and the tag does not already exist locally or on the remote
2. Stamps `## [Unreleased]` → `## [X.Y.Z] - YYYY-MM-DD` in `changelog.md` and commits it (pre-release commit)
3. Creates and pushes the annotated tag `<chart>-vX.Y.Z` — this triggers the GitHub Actions release workflow
4. Bumps `Chart.yaml` to the next version and adds a fresh `## [Unreleased]` section to `changelog.md`
5. Commits and pushes both

Step 1 matters because steps 2–5 are not atomic: the tag is pushed before the bump commit, so a
precondition that fails midway leaves either a stray commit or a published release with no bump.
Use `--allow-any-branch` to release from somewhere other than `master` (e.g. a pre-release from a
feature branch) — it warns rather than failing, but the upstream check still applies.

The GitHub Actions workflow (`release.yml`) then:
- **Gates on tests first** (`verify-tests` job). The test workflows trigger on `branches: ['**']`,
  which excludes tags, so without this a tag would publish whatever the tagged commit is. The gate
  looks up the Unit Tests and Integration Tests runs for that exact commit and refuses to publish
  unless both succeeded — polling for up to 10 minutes if a run is still in flight, since the tag
  usually lands moments after the branch push that triggered them. If it reports no run found, the
  commit was never pushed to a branch; push it before tagging.
- Packages all charts via `helm/chart-releaser-action` (`skip_existing: true` so only the new chart gets a release)
- Creates a GitHub Release with the chart `.tgz` as an asset
- Updates the `gh-pages` branch `index.yaml` (Helm repo index)
- Pushes the chart to GHCR. It is pushed to `oci://ghcr.io/aehrc/<chart>-helm`, but `helm push`
  appends the chart name from the package, so the **pullable reference repeats it**:
  `oci://ghcr.io/aehrc/<chart>-helm/<chart>`. Pulling `oci://ghcr.io/aehrc/<chart>-helm` fails with
  `not found`. Note that GHCR also answers `not found` for a package you lack `read:packages` for, so
  a local `helm show chart` failure is not evidence the push failed — check the workflow log.

### ⚠️ Push release tags one at a time

`cancel-in-progress: false` does **not** give the `release-charts` concurrency group an unbounded
queue. GitHub holds at most one *running* plus one *pending* run per group; a third arrival
**cancels the pending one**. Pushing all three tags at once (observed 2026-08-12) left the middle
run cancelled.

The damage is limited but real: `chart-releaser` packages every chart with `skip_existing: true`, so
the first run to survive creates all the GitHub Releases and the merged `index.yaml`. What a
cancelled run loses is its own `index.html` badge bump and its GHCR push. Recover with
`gh run rerun <id>` once the group is free — the tag still exists, so the re-run is safe and
idempotent.

Release Please's `publish` job is not exposed to this: its `max-parallel: 1` matrix runs inside a
single workflow run, so the charts serialise without ever queueing separate runs.

### If the workflow fails with 403

The `GITHUB_TOKEN` 403 happens when a re-run uses the old workflow commit (before the workflow-level `permissions:` block was added). Re-runs always use the workflow at the original tag commit, so the fix only applies to future tags.

**Manual recovery steps** (do these in order):

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
  --notes "..."   # paste from changelog.md

# 3. Push to GHCR
echo "$(gh auth token)" | helm registry login ghcr.io --username "$(gh api user --jq .login)" --password-stdin
helm push /tmp/cr-packages/<chart>-X.Y.Z.tgz oci://ghcr.io/aehrc/<chart>-helm

# 4. Update gh-pages index
git clone --branch gh-pages --single-branch https://github.com/aehrc/ontoserver-deploy.git /tmp/gh-pages
helm repo index /tmp/cr-packages/ \
  --url https://github.com/aehrc/ontoserver-deploy/releases/download/<chart>-vX.Y.Z \
  --merge /tmp/gh-pages/index.yaml
mv /tmp/cr-packages/index.yaml /tmp/gh-pages/index.yaml
cd /tmp/gh-pages
git config user.name "$(gh api user --jq .login)"
git config user.email "$(gh api user --jq .login)@users.noreply.github.com"
git remote set-url origin https://$(gh auth token)@github.com/aehrc/ontoserver-deploy.git
git add index.yaml && git commit -m "Release <chart> X.Y.Z [skip ci]" && git push origin gh-pages
```

### Pre-release flag

Mark a release as pre-release while the chart is still stabilising:
```bash
gh release edit <chart>-vX.Y.Z --repo aehrc/ontoserver-deploy --prerelease
```

Remove the flag when ready to promote to stable:
```bash
gh release edit <chart>-vX.Y.Z --repo aehrc/ontoserver-deploy --latest
```

### Tag schemes

Two tag forms exist for historical reasons: `<chart>-vX.Y.Z` and `<chart>-X.Y.Z`. Only the **`-v`
form** triggers `release.yml` — that is what `release.sh` creates. The non-`v` form is created by
`chart-releaser` as part of the release itself, so both end up in the repo for every release. Do
not tag the non-`v` form by hand expecting a release.

### Chart versions

| Chart | Latest release | Notes |
|---|---|---|
| `ontoserver` | **0.4.0** | breaking: bundled nginx-ingress subchart removed |
| `ontoserver-extras` | **0.1.1** | |
| `ontoserver-indexer` | **0.2.0** | |

Under Release Please, `Chart.yaml` holds the **last released** version, not the next one, and there
is no standing `## [Unreleased]` section — the open release PR for a chart *is* the pending version,
and merging it stamps the heading. Releases 0.1.0–0.3.0 are flagged pre-release on GitHub; 0.4.0 /
0.1.1 / 0.2.0 are normal releases. The pre-release flag is not automated — set it by hand if a
future release needs it (see above).
