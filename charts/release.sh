#!/usr/bin/env bash
# release.sh - Tag the current chart version and bump for next development cycle
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

# Chart state variables
CHART_DIR=""
CHART_YAML=""
CURRENT_VERSION=""
TAG=""

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
  # Interactive - tags current version, prompts for next
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
            --auto-increment|--minor) BUMP_MODE="minor"; AUTO=true; bump_count=$((bump_count + 1)); shift ;;
            --patch)                  BUMP_MODE="patch";  AUTO=true; bump_count=$((bump_count + 1)); shift ;;
            --major)                  BUMP_MODE="major";  AUTO=true; bump_count=$((bump_count + 1)); shift ;;
            --next-version)
                [[ -z "${2:-}" ]] && die "--next-version requires a value"
                [[ "${2:-}" == --* ]] && die "--next-version requires a version value, not a flag: $2"
                [[ "$2" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Invalid semver: '$2'. Expected X.Y.Z"
                NEXT_VERSION="$2"; AUTO=true; bump_count=$((bump_count + 1)); shift 2 ;;
            --dry-run) DRY_RUN=true; shift ;;
            -h|--help) usage; exit 0 ;;
            *) die "Unknown option: $1. Use --help for usage." ;;
        esac
    done

    if [[ $bump_count -gt 1 ]]; then
        die "Specify at most one of --patch, --minor, --major, --auto-increment, --next-version"
    fi
}

resolve_chart() {
    CHART_DIR="${SCRIPT_DIR}/${CHART}"
    CHART_YAML="${CHART_DIR}/Chart.yaml"

    [[ -d "$CHART_DIR" ]] || die "Chart directory not found: $CHART_DIR"
    [[ -f "$CHART_YAML" ]] || die "Chart.yaml not found: $CHART_YAML"
}

# Note: checks the entire repo for cleanliness, not just the chart being released.
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
    CURRENT_VERSION=$(grep -E '^version:' "$CHART_YAML" | head -1 | sed 's/version:[[:space:]]*//; s/[[:space:]]*$//')
    [[ -n "$CURRENT_VERSION" ]] || die "Could not read version from $CHART_YAML"

    # Validate it looks like semver X.Y.Z
    if ! [[ "$CURRENT_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        die "version '$CURRENT_VERSION' in Chart.yaml is not valid semver (X.Y.Z)"
    fi
}

bump_version() {
    local version="$1"
    local mode="$2"   # patch | minor | major
    [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "bump_version: invalid version: '$version'"
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

compute_tag() {
    TAG="${CHART}-v${CURRENT_VERSION}"
}

check_tag_not_exists() {
    # Check local tags
    local local_tags
    local_tags=$(git -C "$SCRIPT_DIR" tag --list)
    if echo "$local_tags" | grep -qx "$TAG"; then
        die "Tag '$TAG' already exists locally. Has this version already been released?"
    fi

    # Check remote tags
    local remote_tag
    remote_tag=$(git -C "$SCRIPT_DIR" ls-remote --tags origin "refs/tags/${TAG}")
    if [[ -n "$remote_tag" ]]; then
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
        updated=$(grep -E '^version:' "$CHART_YAML" | sed 's/version:[[:space:]]*//; s/[[:space:]]*$//')
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

main "$@"
