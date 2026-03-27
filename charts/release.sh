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

main "$@"
