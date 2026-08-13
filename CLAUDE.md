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
  it, so it goes stale silently after a release.

- **Merging one release PR used to conflict the others**, because all three edit
  `.release-please-manifest.json`. Fixed by `always-update: true` in `release-please-config.json`;
  without it Release Please rewrites a release branch only when the generated *release notes*
  change, so a straggler keeps a stale base and conflicts. Don't remove that flag.

Current releases: `ontoserver` 0.5.0, `ontoserver-extras` 0.1.2, `ontoserver-indexer` 0.2.1.
