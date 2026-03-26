# Chart Release Script Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create `charts/release.sh` — a single bash script that tags the current chart version, pushes the tag (triggering GH Actions), then bumps the version in `Chart.yaml`, commits, and pushes the branch.

**Architecture:** Single self-contained bash script with no external dependencies beyond `git` and standard Unix tools (`grep`, `sed`, `awk`). The script is structured in clearly named functions. `--dry-run` mode is wired throughout so all logic can be verified without touching git or the filesystem.

**Tech Stack:** bash, git, sed, grep

---

## Files

- **Create:** `charts/release.sh` (executable)

---

### Task 1: Script skeleton, argument parsing, and usage

**Files:**
- Create: `charts/release.sh`

- [ ] **Step 1: Create the script with skeleton and argument parsing**

```bash
#!/usr/bin/env bash
# release.sh — Tag the current chart version and bump for next development cycle
#
# Usage: release.sh <chart> [OPTIONS]
#
# See --help for full usage.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="$(basename "$0")"

# Defaults
CHART=""
BUMP_MODE=""        # patch | minor | major
NEXT_VERSION=""     # explicit next version, overrides BUMP_MODE
AUTO=false          # true = no prompt
DRY_RUN=false

# Colors (disabled if not a terminal)
if [[ -t 1 ]]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; CYAN='\033[0;36m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; CYAN=''; NC=''
fi

log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_dry()   { echo -e "${CYAN}[DRY RUN]${NC} $*"; }
die()       { log_error "$*"; exit 1; }

usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} <chart> [OPTIONS]

Tag the current Helm chart version (triggering a GitHub Actions release), then
bump the version in Chart.yaml, commit, and push the current branch.

Arguments:
  <chart>                     Chart name: ontoserver | ontoserver-extras | ontoserver-indexer

Version bump options (choose at most one):
  --auto-increment            Bump minor version, no prompt (same as --minor)
  --minor                     Bump minor version, no prompt
  --patch                     Bump patch version, no prompt
  --major                     Bump major version, no prompt
  --next-version <X.Y.Z>      Set next version explicitly, no prompt

Other:
  --dry-run                   Show what would happen without making changes
  -h, --help                  Show this help message

Examples:
  # Interactive — tags current version, prompts for next
  ${SCRIPT_NAME} ontoserver

  # Fully automated minor bump
  ${SCRIPT_NAME} ontoserver --auto-increment

  # Automated patch bump
  ${SCRIPT_NAME} ontoserver --patch

  # Explicit next version, no prompt
  ${SCRIPT_NAME} ontoserver --next-version 1.0.0

  # Preview without making changes
  ${SCRIPT_NAME} ontoserver --dry-run
EOF
}

parse_args() {
    [[ $# -eq 0 ]] && { usage; exit 0; }

    # First positional arg is the chart name
    case "$1" in
        -h|--help) usage; exit 0 ;;
        -*) die "Expected chart name as first argument. Got: $1. Use --help for usage." ;;
        *)  CHART="$1"; shift ;;
    esac

    local bump_count=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --auto-increment|--minor) BUMP_MODE="minor"; AUTO=true; ((bump_count++)); shift ;;
            --patch)                  BUMP_MODE="patch";  AUTO=true; ((bump_count++)); shift ;;
            --major)                  BUMP_MODE="major";  AUTO=true; ((bump_count++)); shift ;;
            --next-version)
                [[ -z "${2:-}" ]] && die "--next-version requires a value"
                NEXT_VERSION="$2"; AUTO=true; ((bump_count++)); shift 2 ;;
            --dry-run) DRY_RUN=true; shift ;;
            -h|--help) usage; exit 0 ;;
            *) die "Unknown option: $1. Use --help for usage." ;;
        esac
    done

    [[ $bump_count -gt 1 ]] && die "Specify at most one of --patch, --minor, --major, --auto-increment, --next-version"
}

main() {
    parse_args "$@"
    echo "Chart: $CHART, Bump: ${BUMP_MODE:-interactive}, NextVersion: ${NEXT_VERSION:-auto}, DryRun: $DRY_RUN"
}

main "$@"
```

- [ ] **Step 2: Make executable**

```bash
chmod +x charts/release.sh
```

- [ ] **Step 3: Verify usage output**

```bash
cd /path/to/ontoserver-deploy
./charts/release.sh --help
```

Expected: prints usage with examples, exits 0.

```bash
./charts/release.sh
```

Expected: prints usage (no args = help), exits 0.

```bash
./charts/release.sh ontoserver --dry-run
```

Expected: prints `Chart: ontoserver, Bump: interactive, NextVersion: auto, DryRun: true`

```bash
./charts/release.sh ontoserver --minor
```

Expected: prints `Chart: ontoserver, Bump: minor, NextVersion: auto, DryRun: false`

```bash
./charts/release.sh ontoserver --minor --patch
```

Expected: error "Specify at most one of..."

- [ ] **Step 4: Commit**

```bash
git add charts/release.sh
git commit -m "feat(charts): add release script skeleton with argument parsing"
```

---

### Task 2: Safety checks and version reading

**Files:**
- Modify: `charts/release.sh`

- [ ] **Step 1: Add safety check and version reading functions**

Replace the `main()` function and add new functions after `parse_args()`:

```bash
CHART_DIR=""
CHART_YAML=""
CURRENT_VERSION=""

resolve_chart() {
    CHART_DIR="${SCRIPT_DIR}/${CHART}"
    CHART_YAML="${CHART_DIR}/Chart.yaml"

    [[ -d "$CHART_DIR" ]] || die "Chart directory not found: $CHART_DIR"
    [[ -f "$CHART_YAML" ]] || die "Chart.yaml not found: $CHART_YAML"
}

check_git_clean() {
    # Block on staged or modified tracked files; allow untracked
    local dirty
    dirty=$(git -C "$SCRIPT_DIR" status --porcelain | grep -v '^??' || true)
    if [[ -n "$dirty" ]]; then
        log_error "Working tree has uncommitted changes:"
        echo "$dirty" >&2
        die "Commit or stash changes before releasing."
    fi
}

read_current_version() {
    CURRENT_VERSION=$(grep -E '^version:' "$CHART_YAML" | head -1 | sed 's/version:[[:space:]]*//')
    [[ -n "$CURRENT_VERSION" ]] || die "Could not read version from $CHART_YAML"

    # Validate it looks like semver X.Y.Z
    if ! [[ "$CURRENT_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        die "version '$CURRENT_VERSION' in Chart.yaml is not valid semver (X.Y.Z)"
    fi
}

main() {
    parse_args "$@"
    resolve_chart
    if [[ "$DRY_RUN" == false ]]; then
        check_git_clean
    fi
    read_current_version
    log_info "Chart:           $CHART"
    log_info "Chart.yaml:      $CHART_YAML"
    log_info "Current version: $CURRENT_VERSION"
}
```

- [ ] **Step 2: Verify safety checks**

```bash
# Should succeed with clean tree
./charts/release.sh ontoserver --dry-run
```

Expected output includes:
```
[INFO]  Chart:           ontoserver
[INFO]  Chart.yaml:      .../charts/ontoserver/Chart.yaml
[INFO]  Current version: 0.3.0
```

```bash
# Should fail on unknown chart
./charts/release.sh nonexistent --dry-run
```

Expected: `[ERROR] Chart directory not found: .../charts/nonexistent`

- [ ] **Step 3: Commit**

```bash
git add charts/release.sh
git commit -m "feat(charts): add chart resolution, git clean check, and version reading"
```

---

### Task 3: Semver bump logic and next-version resolution

**Files:**
- Modify: `charts/release.sh`

- [ ] **Step 1: Add semver bump and next-version prompt functions**

Add these functions after `read_current_version()`:

```bash
bump_version() {
    local version="$1"
    local mode="$2"   # patch | minor | major
    local major minor patch
    IFS='.' read -r major minor patch <<< "$version"
    case "$mode" in
        major) echo "$((major + 1)).0.0" ;;
        minor) echo "${major}.$((minor + 1)).0" ;;
        patch) echo "${major}.${minor}.$((patch + 1))" ;;
        *)     die "Unknown bump mode: $mode" ;;
    esac
}

validate_semver() {
    local v="$1"
    [[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Invalid semver: '$v'. Expected X.Y.Z"
}

resolve_next_version() {
    local suggested

    if [[ -n "$NEXT_VERSION" ]]; then
        # Explicit version provided
        validate_semver "$NEXT_VERSION"
        suggested="$NEXT_VERSION"
    else
        # Auto-compute from bump mode (default: minor)
        local mode="${BUMP_MODE:-minor}"
        suggested=$(bump_version "$CURRENT_VERSION" "$mode")
    fi

    if [[ "$AUTO" == true ]]; then
        NEXT_VERSION="$suggested"
        log_info "Next version:    $NEXT_VERSION (auto)"
    else
        # Interactive prompt
        echo ""
        echo -n "Next version [${suggested}]: "
        local input
        read -r input
        if [[ -z "$input" ]]; then
            NEXT_VERSION="$suggested"
        else
            validate_semver "$input"
            NEXT_VERSION="$input"
        fi
        log_info "Next version:    $NEXT_VERSION"
    fi
}
```

Update `main()` to call `resolve_next_version`:

```bash
main() {
    parse_args "$@"
    resolve_chart
    if [[ "$DRY_RUN" == false ]]; then
        check_git_clean
    fi
    read_current_version
    log_info "Chart:           $CHART"
    log_info "Chart.yaml:      $CHART_YAML"
    log_info "Current version: $CURRENT_VERSION"
    resolve_next_version
}
```

- [ ] **Step 2: Verify bump logic**

```bash
# Interactive default — should prompt "Next version [0.4.0]: "
./charts/release.sh ontoserver --dry-run
# Press Enter — should accept 0.4.0

# Auto minor
./charts/release.sh ontoserver --minor --dry-run
# Expected: [INFO]  Next version:    0.4.0 (auto)

# Auto patch
./charts/release.sh ontoserver --patch --dry-run
# Expected: [INFO]  Next version:    0.3.1 (auto)

# Auto major
./charts/release.sh ontoserver --major --dry-run
# Expected: [INFO]  Next version:    1.0.0 (auto)

# Explicit version
./charts/release.sh ontoserver --next-version 0.5.0 --dry-run
# Expected: [INFO]  Next version:    0.5.0 (auto)

# Bad semver
./charts/release.sh ontoserver --next-version abc --dry-run
# Expected: [ERROR] Invalid semver: 'abc'. Expected X.Y.Z
```

- [ ] **Step 3: Commit**

```bash
git add charts/release.sh
git commit -m "feat(charts): add semver bump logic and interactive next-version prompt"
```

---

### Task 4: Tag creation and push

**Files:**
- Modify: `charts/release.sh`

- [ ] **Step 1: Add tag functions**

Add after `resolve_next_version()`:

```bash
TAG=""

compute_tag() {
    TAG="${CHART}-v${CURRENT_VERSION}"
}

check_tag_not_exists() {
    # Check local tags
    if git -C "$SCRIPT_DIR" tag --list | grep -qx "$TAG"; then
        die "Tag '$TAG' already exists locally. Has this version already been released?"
    fi

    # Check remote tags
    if git -C "$SCRIPT_DIR" ls-remote --tags origin "refs/tags/${TAG}" | grep -q "$TAG"; then
        die "Tag '$TAG' already exists on remote. Has this version already been released?"
    fi
}

create_and_push_tag() {
    compute_tag
    check_tag_not_exists

    log_info "Creating tag:    $TAG"
    if [[ "$DRY_RUN" == true ]]; then
        log_dry "git tag -a \"$TAG\" -m \"Release ${CHART} ${CURRENT_VERSION}\""
        log_dry "git push origin \"$TAG\""
    else
        git -C "$SCRIPT_DIR" tag -a "$TAG" -m "Release ${CHART} ${CURRENT_VERSION}"
        git -C "$SCRIPT_DIR" push origin "$TAG"
        log_info "Pushed tag:      $TAG  → triggers GitHub Actions release"
    fi
}
```

Update `main()`:

```bash
main() {
    parse_args "$@"
    resolve_chart
    if [[ "$DRY_RUN" == false ]]; then
        check_git_clean
    fi
    read_current_version
    log_info "Chart:           $CHART"
    log_info "Chart.yaml:      $CHART_YAML"
    log_info "Current version: $CURRENT_VERSION"
    resolve_next_version
    create_and_push_tag
}
```

- [ ] **Step 2: Verify tag logic in dry-run**

```bash
./charts/release.sh ontoserver --minor --dry-run
```

Expected output includes:
```
[INFO]  Creating tag:    ontoserver-v0.3.0
[DRY RUN] git tag -a "ontoserver-v0.3.0" -m "Release ontoserver 0.3.0"
[DRY RUN] git push origin "ontoserver-v0.3.0"
```

- [ ] **Step 3: Commit**

```bash
git add charts/release.sh
git commit -m "feat(charts): add tag creation and push with duplicate-tag guard"
```

---

### Task 5: Update Chart.yaml, commit, and push branch

**Files:**
- Modify: `charts/release.sh`

- [ ] **Step 1: Add version update and push functions**

Add after `create_and_push_tag()`:

```bash
update_chart_version() {
    log_info "Updating Chart.yaml: $CURRENT_VERSION → $NEXT_VERSION"
    if [[ "$DRY_RUN" == true ]]; then
        log_dry "sed -i '' 's/^version: .*/version: ${NEXT_VERSION}/' \"$CHART_YAML\""
    else
        # macOS sed requires '' after -i; GNU sed on Linux does not
        if sed --version 2>/dev/null | grep -q GNU; then
            sed -i "s/^version: .*/version: ${NEXT_VERSION}/" "$CHART_YAML"
        else
            sed -i '' "s/^version: .*/version: ${NEXT_VERSION}/" "$CHART_YAML"
        fi
        # Verify the change landed
        local updated
        updated=$(grep -E '^version:' "$CHART_YAML" | sed 's/version:[[:space:]]*//')
        [[ "$updated" == "$NEXT_VERSION" ]] || die "Failed to update version in $CHART_YAML (got: $updated)"
    fi
}

commit_and_push() {
    local commit_msg="chore(chart): bump ${CHART} version to ${NEXT_VERSION}"
    log_info "Committing:      $commit_msg"
    if [[ "$DRY_RUN" == true ]]; then
        log_dry "git add \"$CHART_YAML\""
        log_dry "git commit -m \"$commit_msg\""
        log_dry "git push origin HEAD"
    else
        git -C "$SCRIPT_DIR" add "$CHART_YAML"
        git -C "$SCRIPT_DIR" commit -m "$commit_msg"
        git -C "$SCRIPT_DIR" push origin HEAD
        log_info "Pushed branch."
    fi
}
```

Update `main()` to call the new functions:

```bash
main() {
    parse_args "$@"
    resolve_chart
    if [[ "$DRY_RUN" == false ]]; then
        check_git_clean
    fi
    read_current_version
    log_info "Chart:           $CHART"
    log_info "Chart.yaml:      $CHART_YAML"
    log_info "Current version: $CURRENT_VERSION"
    resolve_next_version
    create_and_push_tag
    update_chart_version
    commit_and_push
    echo ""
    log_info "Done! Tagged ${CHART} ${CURRENT_VERSION} and bumped Chart.yaml to ${NEXT_VERSION}."
}
```

- [ ] **Step 2: Full dry-run end-to-end**

```bash
./charts/release.sh ontoserver --minor --dry-run
```

Expected full output (no actual git operations):
```
[INFO]  Chart:           ontoserver
[INFO]  Chart.yaml:      .../charts/ontoserver/Chart.yaml
[INFO]  Current version: 0.3.0
[INFO]  Next version:    0.4.0 (auto)
[INFO]  Creating tag:    ontoserver-v0.3.0
[DRY RUN] git tag -a "ontoserver-v0.3.0" -m "Release ontoserver 0.3.0"
[DRY RUN] git push origin "ontoserver-v0.3.0"
[INFO]  Updating Chart.yaml: 0.3.0 → 0.4.0
[DRY RUN] sed -i '' 's/^version: .*/version: 0.4.0/' ".../Chart.yaml"
[INFO]  Committing:      chore(chart): bump ontoserver version to 0.4.0
[DRY RUN] git add ".../Chart.yaml"
[DRY RUN] git commit -m "chore(chart): bump ontoserver version to 0.4.0"
[DRY RUN] git push origin HEAD
[INFO]  Done! Tagged ontoserver 0.3.0 and bumped Chart.yaml to 0.4.0.
```

```bash
# Also verify for other charts
./charts/release.sh ontoserver-extras --patch --dry-run
./charts/release.sh ontoserver-indexer --major --dry-run
```

- [ ] **Step 3: Commit**

```bash
git add charts/release.sh
git commit -m "feat(charts): add Chart.yaml version update, commit and push"
```

---

### Task 6: Final polish — summary header and README note

**Files:**
- Modify: `charts/release.sh`
- Modify: `charts/README.md`

- [ ] **Step 1: Add a summary header printed at the start of main()**

At the top of `main()`, right after `parse_args "$@"`, add:

```bash
    echo ""
    echo "=== Helm Chart Release ==="
    if [[ "$DRY_RUN" == true ]]; then
        echo "(dry run — no changes will be made)"
    fi
    echo ""
```

- [ ] **Step 2: Verify the header appears**

```bash
./charts/release.sh ontoserver --minor --dry-run
```

Expected first lines:
```

=== Helm Chart Release ===
(dry run — no changes will be made)
```

- [ ] **Step 3: Add a brief note to charts/README.md**

Read the current README first, then append a "Releasing" section. Find the end of the file and add:

```markdown

## Releasing a chart

Use `release.sh` to tag the current version and bump for the next cycle:

```bash
# Interactive (prompts for next version, default: minor bump)
./charts/release.sh ontoserver

# Automated minor bump, no prompt
./charts/release.sh ontoserver --auto-increment

# Preview without making changes
./charts/release.sh ontoserver --dry-run
```

Pushing the tag triggers the GitHub Actions release workflow, which publishes the chart to the GitHub Pages Helm repo and to GHCR (OCI).
```

- [ ] **Step 4: Commit**

```bash
git add charts/release.sh charts/README.md
git commit -m "docs(charts): add release script summary header and README releasing section"
```

---

## Self-Review

**Spec coverage:**
- ✅ Single script in `charts/`
- ✅ Reads version from `Chart.yaml`
- ✅ Tags with current version, pushes tag
- ✅ `--next-version` for explicit next version, no prompt
- ✅ `--auto-increment` / `--minor` / `--patch` / `--major` for automated bump, no prompt
- ✅ Interactive prompt showing auto-incremented default when no flag given
- ✅ Updates `Chart.yaml`, commits, pushes current branch
- ✅ `--dry-run` for safe previewing
- ✅ Safety: duplicate tag guard
- ✅ Safety: clean working tree check

**Placeholder scan:** None found — all steps include exact commands and expected output.

**Type consistency:** `CHART`, `CURRENT_VERSION`, `NEXT_VERSION`, `TAG`, `BUMP_MODE`, `AUTO`, `DRY_RUN` are all set once and used consistently across tasks. `bump_version`, `validate_semver`, `resolve_next_version`, `compute_tag`, `check_tag_not_exists`, `create_and_push_tag`, `update_chart_version`, `commit_and_push` are defined before first use.
