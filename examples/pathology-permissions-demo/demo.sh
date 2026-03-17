#!/usr/bin/env bash
# =============================================================================
# Pathology Permissions Demo - Entry Point
# =============================================================================
#
# Single script to set up, run walkthroughs, and tear down either demo variant.
#
# Usage:
#   ./demo.sh <command> <variant>
#
# Commands:
#   setup        Start Docker services and configure the demo environment
#   walkthrough  Run the interactive visual walkthrough in a browser
#   teardown     Stop all services and remove data volumes
#   status       Show running services and their health
#
# Variants:
#   simple       Authoring + Production (direct syndication)
#   atomio       Authoring + Atomio + UAT + Production (release management)
#
# Examples:
#   ./demo.sh setup simple           # Set up the simple demo (~5 min)
#   ./demo.sh setup atomio           # Set up the atomio demo (~8 min)
#   ./demo.sh walkthrough simple     # Run the visual walkthrough
#   ./demo.sh walkthrough atomio     # Run the atomio walkthrough
#   ./demo.sh status simple          # Check service health
#   ./demo.sh teardown simple        # Tear down and remove all data
#
# Prerequisites:
#   - Docker and Docker Compose
#   - Access to quay.io/aehrc container registry
#   - curl, jq, python3 installed locally
#   - Node.js and npm (for walkthroughs only)
#
# =============================================================================

set -euo pipefail

DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="${DEMO_DIR}/tests/e2e"

# -- Colours (if terminal supports them) -------------------------------------

if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' BOLD='' NC=''
fi

# -- Helpers ------------------------------------------------------------------

usage() {
    cat <<'EOF'
Pathology Permissions Demo

Usage:
  ./demo.sh <command> <variant>

Commands:
  setup        Start Docker services and configure the demo environment
  walkthrough  Run the interactive visual walkthrough in a browser
  teardown     Stop all services and remove data volumes
  status       Show running services and their health

Variants:
  simple       Authoring + Production (direct syndication)
  atomio       Authoring + Atomio + UAT + Production (release management)

Examples:
  ./demo.sh setup simple           Set up the simple demo (~5 min)
  ./demo.sh setup atomio           Set up the atomio demo (~8 min)
  ./demo.sh walkthrough simple     Run the visual walkthrough
  ./demo.sh walkthrough atomio     Run the atomio visual walkthrough
  ./demo.sh walkthrough simple --auto   Run walkthrough without pausing
  ./demo.sh status simple          Check service health
  ./demo.sh teardown simple        Tear down and remove all data

After setup, open in a browser (accept the self-signed certificate warning):
  Ontocloak Admin    https://localhost:9090/auth/admin  (admin/admin)
  Shrimp (authoring) https://ontoserver.csiro.au/shrimp?iss=https://localhost:9081/fhir&clientId=shrimp
  Snapper (authoring) https://ontoserver.csiro.au/snapper?iss=https://localhost:9081/fhir&clientId=snapper
  OntoCommand        https://ontoserver.csiro.au/ui?iss=https://localhost:9081/fhir&clientId=onto-ui

  Simple only:
    Shrimp (production) https://ontoserver.csiro.au/shrimp?iss=https://localhost:9082/fhir&clientId=shrimp

  Atomio only:
    Atomio UI          https://localhost:9083
    Atomio Swagger     https://localhost:9083/swagger-ui/index.html
    Shrimp (UAT)       https://ontoserver.csiro.au/shrimp?iss=https://localhost:9084/fhir&clientId=shrimp
    Shrimp (production) https://ontoserver.csiro.au/shrimp?iss=https://localhost:9082/fhir&clientId=shrimp

Demo users (all passwords: demo):
  alpha-viewer, alpha-author, alpha-approver
  beta-viewer,  beta-author,  beta-approver
  national-admin, admin

Documentation:
  docs/architecture.md       System architecture and design decisions
  docs/concepts.md           Security labels, communities, syndication
  docs/walkthrough-simple.md Step-by-step simple variant guide
  docs/walkthrough-atomio.md Step-by-step atomio variant guide
EOF
}

die() {
    echo -e "${RED}Error: $1${NC}" >&2
    echo ""
    echo "Run './demo.sh' with no arguments for usage information."
    exit 1
}

info() {
    echo -e "${BLUE}==>${NC} ${BOLD}$1${NC}"
}

success() {
    echo -e "${GREEN}==>${NC} ${BOLD}$1${NC}"
}

warn() {
    echo -e "${YELLOW}==>${NC} ${BOLD}$1${NC}"
}

validate_variant() {
    local variant="$1"
    case "$variant" in
        simple|atomio) ;;
        *) die "Unknown variant '${variant}'. Must be 'simple' or 'atomio'." ;;
    esac

    if [[ ! -d "${DEMO_DIR}/${variant}" ]]; then
        die "Variant directory '${variant}/' not found. Are you in the right directory?"
    fi
}

check_prerequisites() {
    local missing=()

    command -v docker >/dev/null 2>&1 || missing+=("docker")
    command -v docker compose version >/dev/null 2>&1 || missing+=("docker compose")
    command -v curl >/dev/null 2>&1 || missing+=("curl")
    command -v jq >/dev/null 2>&1 || missing+=("jq")
    command -v python3 >/dev/null 2>&1 || missing+=("python3")

    if [[ ${#missing[@]} -gt 0 ]]; then
        die "Missing prerequisites: ${missing[*]}\nSee README.md for installation instructions."
    fi
}

check_walkthrough_prerequisites() {
    if [[ ! -d "${TESTS_DIR}/node_modules" ]]; then
        warn "Node dependencies not installed. Installing..."
        (cd "${TESTS_DIR}" && npm install)
    fi

    # Check if Playwright browsers are installed
    if ! npx --prefix "${TESTS_DIR}" playwright install --dry-run chromium >/dev/null 2>&1; then
        warn "Playwright browsers not installed. Installing chromium..."
        (cd "${TESTS_DIR}" && npx playwright install chromium)
    fi
}

# -- Commands -----------------------------------------------------------------

cmd_setup() {
    local variant="$1"
    check_prerequisites
    validate_variant "$variant"

    info "Setting up the ${variant} demo..."
    echo ""

    local variant_dir="${DEMO_DIR}/${variant}"
    chmod +x "${variant_dir}/scripts/"*.sh

    (cd "${variant_dir}" && ./scripts/setup.sh)
}

cmd_walkthrough() {
    local variant="$1"
    shift
    validate_variant "$variant"

    info "Running ${variant} visual walkthrough..."
    echo ""

    check_walkthrough_prerequisites

    local args=("--variant" "${variant}")
    # Pass through any additional flags (e.g., --auto)
    args+=("$@")

    (cd "${TESTS_DIR}" && npx tsx walkthrough/visual-walkthrough.ts "${args[@]}")
}

cmd_teardown() {
    local variant="$1"
    validate_variant "$variant"

    local variant_dir="${DEMO_DIR}/${variant}"

    warn "This will stop all ${variant} services and DELETE all data volumes."
    echo ""
    read -r -p "Continue? [y/N] " confirm
    case "$confirm" in
        [yY]|[yY][eE][sS]) ;;
        *) echo "Cancelled."; exit 0 ;;
    esac

    info "Tearing down ${variant} demo..."
    (cd "${variant_dir}" && docker compose down -v)

    # Clean up generated files
    if [[ -d "${variant_dir}/generated" ]]; then
        rm -rf "${variant_dir}/generated"
    fi
    if [[ -f "${variant_dir}/.env" ]]; then
        rm -f "${variant_dir}/.env"
    fi

    success "Teardown complete. All ${variant} services and data have been removed."
    echo ""
    echo "To run the demo again: ./demo.sh setup ${variant}"
}

cmd_status() {
    local variant="$1"
    validate_variant "$variant"

    local variant_dir="${DEMO_DIR}/${variant}"

    info "Service status for ${variant} demo:"
    echo ""
    (cd "${variant_dir}" && docker compose ps)

    echo ""
    info "Health checks:"

    # Ontocloak
    local ontocloak_status
    ontocloak_status=$(curl -sf -o /dev/null -w "%{http_code}" http://localhost:9090/auth/realms/master 2>/dev/null || echo "000")
    if [[ "$ontocloak_status" == "200" ]]; then
        echo -e "  Ontocloak (9090):          ${GREEN}healthy${NC}"
    else
        echo -e "  Ontocloak (9090):          ${RED}unreachable${NC}"
    fi

    # Authoring Ontoserver
    local authoring_status
    authoring_status=$(curl -sf -o /dev/null -w "%{http_code}" http://localhost:9081/fhir/metadata 2>/dev/null || echo "000")
    if [[ "$authoring_status" == "200" ]]; then
        echo -e "  Authoring Ontoserver (9081): ${GREEN}healthy${NC}"
    else
        echo -e "  Authoring Ontoserver (9081): ${RED}unreachable${NC}"
    fi

    if [[ "$variant" == "simple" ]]; then
        local prod_status
        prod_status=$(curl -sf -o /dev/null -w "%{http_code}" http://localhost:9082/fhir/metadata 2>/dev/null || echo "000")
        if [[ "$prod_status" == "200" ]]; then
            echo -e "  Production Ontoserver (9082): ${GREEN}healthy${NC}"
        else
            echo -e "  Production Ontoserver (9082): ${RED}unreachable${NC}"
        fi
    fi

    if [[ "$variant" == "atomio" ]]; then
        local atomio_status
        atomio_status=$(curl -sf -o /dev/null -w "%{http_code}" http://localhost:9083/feed 2>/dev/null || echo "000")
        if [[ "$atomio_status" == "200" ]]; then
            echo -e "  Atomio (9083):             ${GREEN}healthy${NC}"
        else
            echo -e "  Atomio (9083):             ${RED}unreachable${NC}"
        fi

        local uat_status
        uat_status=$(curl -sf -o /dev/null -w "%{http_code}" http://localhost:9084/fhir/metadata 2>/dev/null || echo "000")
        if [[ "$uat_status" == "200" ]]; then
            echo -e "  UAT Ontoserver (9084):     ${GREEN}healthy${NC}"
        else
            echo -e "  UAT Ontoserver (9084):     ${RED}unreachable${NC}"
        fi

        local prod_status
        prod_status=$(curl -sf -o /dev/null -w "%{http_code}" http://localhost:9082/fhir/metadata 2>/dev/null || echo "000")
        if [[ "$prod_status" == "200" ]]; then
            echo -e "  Production Ontoserver (9082): ${GREEN}healthy${NC}"
        else
            echo -e "  Production Ontoserver (9082): ${RED}unreachable${NC}"
        fi
    fi
}

# -- Main ---------------------------------------------------------------------

if [[ $# -lt 1 ]]; then
    usage
    exit 0
fi

COMMAND="$1"
shift

case "$COMMAND" in
    setup|walkthrough|teardown|status)
        if [[ $# -lt 1 ]]; then
            die "'${COMMAND}' requires a variant argument: simple or atomio"
        fi
        VARIANT="$1"
        shift
        "cmd_${COMMAND}" "$VARIANT" "$@"
        ;;
    help|--help|-h)
        usage
        exit 0
        ;;
    *)
        die "Unknown command '${COMMAND}'. Valid commands: setup, walkthrough, teardown, status"
        ;;
esac
