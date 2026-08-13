# Claude Code Notes — ontoserver-deploy

## Releasing a chart

**[`RELEASE.md`](RELEASE.md) is the authority.** Read it before touching anything release-related —
it covers the Release Please flow, the manual `release.sh` fallback, recovery steps, and Artifact Hub.
Do not restate its content here; keep this file to the things an agent gets wrong.

The traps, in short:

- **Never hand-edit a chart `version:` or stamp a changelog heading.** Release Please owns both. The
  `version:` in each `charts/*/Chart.yaml` must always equal its entry in
  `.release-please-manifest.json`; if they drift, Release Please computes the next version from the
  manifest and the two disagree about what is published.
- **`Chart.yaml` holds the *last released* version, and there is no `## [Unreleased]` section.** This
  inverted the pre-2026-08-12 convention, so older docs and habits have it backwards.
- **Which chart gets released comes from the file paths a commit touches, not the commit scope.**
  `fix(indexer):` on a commit editing `charts/ontoserver/` releases *ontoserver*. Keep a commit to
  one chart where possible.
- **A GHCR pull path repeats the chart name**: `oci://ghcr.io/aehrc/<chart>-helm/<chart>`. And GHCR
  answers `not found` for a package your token lacks `read:packages` for, so a failed local
  `helm show chart` is not evidence a push failed — check the workflow log.
- **Push release tags one at a time.** The `release-charts` concurrency group holds one running plus
  one pending run; a third arrival cancels the pending one.
- **`artifacthub.io/changes` in `Chart.yaml` is hand-maintained** and Release Please does not update
  it, so it goes stale silently after a release. Rewrite it *on the release PR branch* — push a
  `chore(<chart>):` commit to `release-please--branches--master--components--<chart>` before merging,
  so the new list lands in the same commit range as the version bump. Describe only the version being
  cut, one entry per user-visible change, and use a `kind` Artifact Hub accepts: `added`, `changed`,
  `deprecated`, `removed`, `fixed`, `security`. Anything a chart user must act on (a changed default)
  belongs here as `changed`, not just in the changelog. Verify by parsing it — the annotation value is
  a YAML string that must itself parse as a list of `kind`/`description` maps.
- **Do the same pass on the stale prose while you are there:** the current-versions table in
  `RELEASE.md` and the `Current releases:` line at the bottom of this file. Nothing regenerates them.
- **Merge feature PRs with a merge commit, not a squash.** A squash collapses several conventional
  commits into the PR title alone, so a branch carrying two `feat`s and a `fix` releases as a patch
  bump and the features vanish from the changelog. The side effect to expect: when the PR *title* is
  also conventional, Release Please logs the merge commit as its own changelog entry restating the
  real ones — delete that line on the release PR branch, or give the merge commit a non-conventional
  subject.
- **Release PR checks still need a human to approve them**, and `Integration Tests` (a `push`-only
  workflow) never runs on a release PR at all. `release-please.yml` has the fix plumbed — it authors
  the PR as a GitHub App when `vars.RELEASE_PLEASE_APP_ID` is set — but the variable and
  `secrets.RELEASE_PLEASE_APP_PRIVATE_KEY` are **not configured**, so it silently falls back to
  `GITHUB_TOKEN`, whose PRs cannot start workflow runs. Do not "fix" this in the workflow; it needs an
  App created and installed in the org.

- **Merging one release PR used to conflict the others**, because all three edit
  `.release-please-manifest.json`. Fixed by `always-update: true` in `release-please-config.json`;
  without it Release Please rewrites a release branch only when the generated *release notes*
  change, so a straggler keeps a stale base and conflicts. Don't remove that flag.

Current releases: `ontoserver` 0.5.0, `ontoserver-extras` 0.1.2, `ontoserver-indexer` 0.2.1.

## Editing a chart

- **The README parameter tables are generated, and CI fails if they drift from `values.yaml`.** Do not
  hand-write or hand-pad a row; add the `## @param` comment in `values.yaml` and regenerate with the
  same generator and version CI pins in `README_GENERATOR_VERSION`:

  ```sh
  cd charts/<chart>
  npx --yes @bitnami/readme-generator-for-helm@2.7.2 -v values.yaml -r README.md
  ```

  It edits `README.md` in place and replaces only the generated tables, leaving hand-written prose
  sections alone. Expect it to reflow padding across the whole table, so commit it separately from the
  change it documents. A different version reflows differently and CI will reject it. (There is a
  `helm-readme-generator` skill wrapping this, but it is a personal skill other contributors do not
  have — keep the `npx` command as the documented route.)
- **A new value needs four edits, not one:** `values.yaml` (with its `## @param` line), the matching
  `values.schema.json` entry (with an `enum` where the field is closed, which is what turns a typo
  into a render-time error), a `helm unittest` assertion on the rendered output, and the regenerated
  README table.
- **Keep a new value's default equal to the old hardcoded literal** when replacing one, so existing
  installs render byte-identically and the change is purely additive.
