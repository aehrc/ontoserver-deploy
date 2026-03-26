# Chart Release Script Design

**Date:** 2026-03-26
**Status:** Approved

## Overview

A single bash script `charts/release.sh` that automates releasing a Helm chart by tagging the current version, triggering the GitHub Actions release pipeline, then bumping the version in `Chart.yaml` and pushing the updated chart for the next development cycle.

## Flow

```
read Chart.yaml version
  → create git tag <chart-name>-v<version>
  → push tag  (triggers GH Actions: chart-releaser + GHCR push)
  → determine next version
      if --next-version X.Y.Z  → use as-is, no prompt
      if --auto-increment / --minor / --patch / --major → compute, no prompt
      otherwise → compute minor bump, prompt "Next version [X.Y.Z]: "
  → update Chart.yaml version
  → git commit
  → git push (current branch)
```

## Interface

```
Usage: release.sh <chart> [OPTIONS]

Arguments:
  <chart>                     Chart name: ontoserver | ontoserver-extras | ontoserver-indexer

Version bump options (choose one):
  --auto-increment            Bump minor version automatically, no prompt
  --minor                     Bump minor version, no prompt (same as --auto-increment)
  --patch                     Bump patch version, no prompt
  --major                     Bump major version, no prompt
  --next-version <X.Y.Z>      Set next version explicitly, no prompt

Other:
  --dry-run                   Show what would happen without making changes
  -h, --help                  Show this help message
```

Examples:
```bash
# Interactive — tags current version, prompts for next
./release.sh ontoserver

# Fully automated minor bump
./release.sh ontoserver --auto-increment
./release.sh ontoserver --minor

# Automated patch bump
./release.sh ontoserver --patch

# Explicit next version
./release.sh ontoserver --next-version 1.0.0

# Dry run to preview
./release.sh ontoserver --dry-run
```

## Implementation Details

### Chart path resolution
The script lives in `charts/`. It resolves the chart directory as `$(dirname "$0")/<chart>` so it works when called from any working directory.

### Version reading
Use `grep`/`sed` to read `version:` from `Chart.yaml` — no external deps beyond standard Unix tools and `git`.

### Tag format
`<chart-name>-v<version>` — matches the patterns in `.github/workflows/release.yml` that trigger releases.

### Tagging the current version
- Check the tag doesn't already exist (local and remote) — fail fast with a clear error if it does.
- Create annotated tag with message `Release <chart> <version>`.
- Push tag to origin.

### Version bump logic
Given semver `MAJOR.MINOR.PATCH`:
- `--patch` / `-p`: increment PATCH, reset nothing
- `--minor` / `-m` / `--auto-increment`: increment MINOR, reset PATCH to 0
- `--major`: increment MAJOR, reset MINOR and PATCH to 0

### Interactive prompt
When no bump flag is given, show:
```
Current version: 0.3.0
Next version [0.4.0]:
```
User can press Enter to accept the default (minor bump) or type any valid semver. Validate the entered version is a valid `X.Y.Z` semver before proceeding.

### Updating Chart.yaml
Use `sed -i` to replace the `version:` line in `Chart.yaml`. No `yq` required.

### Commit and push
Commit message: `chore(chart): bump <chart> version to <new-version>`
Push to the current branch (`git push origin HEAD`).

### Dry run
With `--dry-run`, print each action prefixed with `[DRY RUN]` without executing git or file operations.

### Safety checks
- Verify `charts/<chart>/Chart.yaml` exists.
- Verify git working tree is clean before making changes (warn but don't block on untracked files; block on staged/modified tracked files).
- Verify the tag does not already exist locally or on the remote.

## Files Changed

- **New:** `charts/release.sh` (executable)

No other files are created or modified by the script itself.
