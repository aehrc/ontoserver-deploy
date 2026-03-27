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

    [[ $bump_count -gt 1 ]] && die "Specify at most one of --patch, --minor, --major, --auto-increment, --next-version"
}

main() {
    parse_args "$@"
    echo "Chart: $CHART, Bump: ${BUMP_MODE:-interactive}, NextVersion: ${NEXT_VERSION:-auto}, DryRun: $DRY_RUN"
}

main "$@"
