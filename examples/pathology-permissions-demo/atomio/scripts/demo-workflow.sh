#!/usr/bin/env bash
# =============================================================================
# Pathology Permissions Demo - Atomio Variant Interactive Walkthrough
# =============================================================================
#
# Demonstrates the release candidate workflow using Atomio to manage
# terminology content promotion through UAT and production environments.
#
# Prerequisites: Run setup.sh first.
#
# Usage:
#   cd atomio/
#   ./scripts/demo-workflow.sh

set -euo pipefail

ONTOCLOAK_URL="https://localhost:9090"
AUTHORING_URL="https://localhost:9081"
ATOMIO_URL="https://localhost:9083"
UAT_URL="https://localhost:9084"
PRODUCTION_URL="https://localhost:9085"
REALM="pathology-demo"

CYAN='\033[0;36m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

step_number=0

step() {
    step_number=$((step_number + 1))
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  Step ${step_number}: $*${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

explain() { echo -e "${BLUE}$*${NC}"; }
pause() { echo ""; echo -e "${YELLOW}Press Enter to continue...${NC}"; read -r; }
run_cmd() { echo -e "${GREEN}\$ $*${NC}"; eval "$@" 2>&1 || true; echo ""; }

get_token() {
    curl -sf -k -X POST \
        "${ONTOCLOAK_URL}/auth/realms/${REALM}/protocol/openid-connect/token" \
        -d "grant_type=password&client_id=demo-cli&username=${1}&password=demo" \
        | jq -r '.access_token'
}

# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo ""
echo "============================================================"
echo "  Pathology Permissions Demo - Atomio Release Workflow"
echo "============================================================"
echo ""
echo "This walkthrough demonstrates how Atomio manages the"
echo "promotion of terminology content through environments:"
echo ""
echo "  Authoring --> Atomio --> UAT --> Production"
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  You can explore the demo in two ways:"
echo ""
echo "    [a] Automated — this script runs curl commands for you"
echo "        and explains what's happening at each step"
echo ""
echo "    [m] Manual — follow the written walkthrough using"
echo "        Shrimp, Snapper, OntoCommand, and the Atomio UI"
echo "        See: docs/walkthrough-atomio.md"
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
read -r -p "  Choose [a/m] (default: a): " demo_choice
demo_choice="${demo_choice:-a}"

if [ "$demo_choice" = "m" ] || [ "$demo_choice" = "M" ]; then
    echo ""
    echo "  To follow the manual walkthrough, open:"
    echo ""
    echo "    docs/walkthrough-atomio.md"
    echo ""
    echo "  Web tools (add ?iss=https://localhost:<port>):"
    echo "    Shrimp:      https://ontoserver.csiro.au/shrimp"
    echo "    Snapper:     https://ontoserver.csiro.au/snapper"
    echo "    OntoCommand: https://ontoserver.csiro.au/ui"
    echo "    Atomio UI:   https://ontoserver.csiro.au/atomio/"
    echo ""
    echo "  Server ports:"
    echo "    9081  Authoring Ontoserver"
    echo "    9083  Atomio"
    echo "    9084  UAT Ontoserver"
    echo "    9085  Production Ontoserver"
    echo "    9090  Ontocloak"
    echo ""
    echo "  Demo users (all passwords: 'demo'):"
    echo "    admin, alpha-viewer, alpha-author, alpha-approver,"
    echo "    beta-viewer, beta-author, beta-approver, national-admin"
    echo ""
    exit 0
fi

echo ""

# =============================================================================
step "Review the current Atomio feeds and aliases"

explain "Atomio hosts terminology content in named feeds."
explain "Aliases provide stable URLs that point to specific feeds."
echo ""

explain "Current feeds:"
run_cmd "curl -sk '${ATOMIO_URL}/feed' | jq '.[] | {name: .name, title: .title}'"

explain "Current aliases:"
run_cmd "curl -sk '${ATOMIO_URL}/alias' | jq '.[] | {alias: .aliasName, feed: .feedName}'"

explain "The 'uat' and 'production' aliases both point to 'release-1-0'."
explain "UAT and Production Ontoserver instances sync from these aliases."

pause

# =============================================================================
step "Verify UAT and Production have the release content"

explain "Both environments sync from Atomio. Let's check what's available:"
echo ""

explain "UAT - National ValueSet:"
run_cmd "curl -sk '${UAT_URL}/fhir/ValueSet?url=http://example.org/ValueSet/national-pathology-refset' | jq '.total'"

explain "Production - National ValueSet:"
run_cmd "curl -sk '${PRODUCTION_URL}/fhir/ValueSet?url=http://example.org/ValueSet/national-pathology-refset' | jq '.total'"

explain ""
explain "Both environments have the national valueset from the release."

pause

# =============================================================================
step "Author creates a new version on the authoring server"

explain "A Pathology Alpha author creates a new version of their CodeSystem."
explain "The existing CodeSystem (version 1.0.0) was syndicated to this server,"
explain "so it cannot be overwritten in-place — the author lacks SYND_WRITE."
explain "Instead, the author creates version 1.1.0 as a new resource."
explain "This change is only on the authoring server - it has NOT been"
explain "released to UAT or production yet."
echo ""

ALPHA_TOKEN=$(get_token "alpha-author")

# Read current CodeSystem to use as a base
CURRENT_CS=$(curl -sk -H "Authorization: Bearer ${ALPHA_TOKEN}" \
    "${AUTHORING_URL}/fhir/CodeSystem/alpha-pathology-codes")

# Create a new version: new resource ID, bumped version, added concept
NEW_CS=$(echo "$CURRENT_CS" | jq '
    .id = "alpha-pathology-codes-v1-1-0"
    | .version = "1.1.0"
    | .concept += [{"code": "TROP", "display": "Troponin", "definition": "High-sensitivity troponin for cardiac markers"}]
    | .count = (.concept | length)
    | del(.meta.versionId, .meta.lastUpdated)
')

HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" -X PUT \
    "${AUTHORING_URL}/fhir/CodeSystem/alpha-pathology-codes-v1-1-0" \
    -H "Authorization: Bearer ${ALPHA_TOKEN}" \
    -H "Content-Type: application/fhir+json" \
    -d "$NEW_CS" 2>/dev/null)

echo -e "${GREEN}Create HTTP response: ${HTTP_CODE}${NC}"

explain ""
explain "Alpha CodeSystem version 1.1.0 is now on the authoring server"
explain "as a new resource (alpha-pathology-codes-v1-1-0) with the"
explain "'TROP' (Troponin) concept. The original 1.0.0 version is unchanged."

pause

# =============================================================================
step "Create a new release candidate"

explain "An approver creates a new release candidate by cloning the"
explain "authoring server's syndication feed into Atomio."
echo ""

explain "Cloning authoring feed into 'release-2-0':"
run_cmd "curl -sk -o /dev/null -w 'HTTP %{http_code}\n' -X POST '${ATOMIO_URL}/feed/\$clone?name=release-2-0&url=http://authoring-ontoserver:8080/synd/syndication.xml'"

explain "New feed contents:"
run_cmd "curl -sk '${ATOMIO_URL}/feed/release-2-0' | jq '{name: .name, entries: (.entries // [] | length)}'"

explain ""
explain "release-2-0 is now a snapshot of the current authoring content,"
explain "including Alpha's updated CodeSystem with the Troponin concept."

pause

# =============================================================================
step "Promote release candidate to UAT"

explain "The 'uat' alias is updated to point to the new release."
explain "The UAT Ontoserver will pick up the changes on its next sync."
echo ""

run_cmd "curl -sk -o /dev/null -w 'HTTP %{http_code}\n' -X PUT '${ATOMIO_URL}/alias/uat' -H 'Content-Type: application/json' -d '{\"aliasName\": \"uat\", \"feedName\": \"release-2-0\"}'"

explain "Current aliases:"
run_cmd "curl -sk '${ATOMIO_URL}/alias' | jq '.[] | {alias: .aliasName, feed: .feedName}'"

explain ""
explain "UAT now points to release-2-0 (with the new content)."
explain "Production still points to release-1-0 (unchanged)."
explain ""
explain "The UAT Ontoserver polls every 2 minutes, so the new content"
explain "will appear shortly. In a real deployment, you could trigger"
explain "a manual sync or wait for the scheduled poll."

pause

# =============================================================================
step "Production still has the old content"

explain "Production is still on release-1-0. Let's verify:"
echo ""

explain "Checking production Ontoserver for Alpha CodeSystem version:"
run_cmd "curl -sk '${PRODUCTION_URL}/fhir/CodeSystem?url=http://pathology-alpha.example.com/CodeSystem/pathology-codes' | jq '.entry[0].resource.version // \"not found\"'"

explain ""
explain "Production has the original version. The new Troponin concept"
explain "is only in UAT for testing."

pause

# =============================================================================
step "Promote to production after UAT testing"

explain "After UAT testing is complete, promote to production:"
echo ""

run_cmd "curl -sk -o /dev/null -w 'HTTP %{http_code}\n' -X PUT '${ATOMIO_URL}/alias/production' -H 'Content-Type: application/json' -d '{\"aliasName\": \"production\", \"feedName\": \"release-2-0\"}'"

explain "Updated aliases:"
run_cmd "curl -sk '${ATOMIO_URL}/alias' | jq '.[] | {alias: .aliasName, feed: .feedName}'"

explain ""
explain "Both UAT and Production now point to release-2-0."
explain "The production Ontoserver will pick up the changes on its next poll."

pause

# =============================================================================
step "The CSV-to-Atomio pipeline (Pathology Gamma)"

explain "Pathology Gamma's pathology codes are maintained in CSV files."
explain "In the Atomio variant, these can be uploaded directly to Atomio"
explain "as entries in the 'gamma-content' feed."
echo ""

explain "The 'gamma-content' feed can be included when creating release"
explain "candidates, or the authoring Ontoserver can sync from it."
echo ""

explain "Current Atomio feeds:"
run_cmd "curl -sk '${ATOMIO_URL}/feed' | jq '.[] | {name: .name, title: .title}'"

explain ""
explain "In a real deployment, a CI/CD pipeline would:"
explain "  1. Watch the Git repository for CSV changes"
explain "  2. Run csv-transform.py to generate FHIR resources"
explain "  3. Upload resources as entries to the 'gamma-content' feed"
explain "  4. Include gamma-content in the next release candidate"

pause

# =============================================================================
step "Rollback scenario"

explain "One advantage of Atomio is easy rollback. If release-2-0 has"
explain "issues in production, you can revert to release-1-0:"
echo ""

explain "Rollback production to release-1-0:"
run_cmd "curl -sk -o /dev/null -w 'HTTP %{http_code}\n' -X PUT '${ATOMIO_URL}/alias/production' -H 'Content-Type: application/json' -d '{\"aliasName\": \"production\", \"feedName\": \"release-1-0\"}'"

run_cmd "curl -sk '${ATOMIO_URL}/alias' | jq '.[] | {alias: .aliasName, feed: .feedName}'"

explain ""
explain "Production is back on release-1-0. UAT can continue testing"
explain "release-2-0 independently."
echo ""

explain "Restoring production to release-2-0 for the demo:"
curl -sf -k -o /dev/null -X PUT "${ATOMIO_URL}/alias/production" \
    -H "Content-Type: application/json" \
    -d '{"aliasName": "production", "feedName": "release-2-0"}' 2>/dev/null || true

pause

# =============================================================================
echo ""
echo "============================================================"
echo -e "  ${GREEN}Walkthrough Complete!${NC}"
echo "============================================================"
echo ""
echo "  Key Atomio concepts demonstrated:"
echo ""
echo "  1. FEED CLONING: Snapshot authoring content as a release"
echo "  2. ALIASES: Stable URLs for environments (uat, production)"
echo "  3. PROMOTION: Update aliases to promote releases"
echo "  4. ROLLBACK: Revert aliases to previous releases"
echo "  5. PIPELINE: CSV data can flow through Atomio feeds"
echo ""
echo "  Atomio API docs: ${ATOMIO_URL}/swagger-ui.html"
echo ""
echo "  Port reference:"
echo "    9090  Ontocloak"
echo "    9081  Authoring Ontoserver"
echo "    9083  Atomio"
echo "    9084  UAT Ontoserver"
echo "    9085  Production Ontoserver"
echo ""
