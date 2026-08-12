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

### Adopting it — one-time step

The manifest is seeded with `ontoserver 0.4.0`, `ontoserver-extras 0.1.1`, `ontoserver-indexer 0.2.0`,
matching the current `Chart.yaml` files and the hand-written changelog entries for this review.
**Those three versions still need to be tagged and published once** (via `release.sh` below, or by
hand) — the manifest asserts they are released, so Release Please will bump *past* them. Skip it and
the Helm repo index will simply never contain them.

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
- Pushes the chart to GHCR (`ghcr.io/aehrc/<chart>-helm`)

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

| Chart | Published | In development |
|---|---|---|
| `ontoserver` | 0.3.0 (pre-release) | **0.4.0** (breaking: nginx-ingress subchart removed) |
| `ontoserver-extras` | 0.1.0 | 0.1.1 |
| `ontoserver-indexer` | 0.1.0 | 0.2.0 |

`Chart.yaml` always holds the *in-development* version — the one `release.sh` will tag next —
and the changelog's `## [Unreleased]` section holds its notes. Both extras and indexer were left
at their published version after the 0.1.0 release (which predates `release.sh`), so their
Chart.yaml lagged behind the template changes on this branch.
