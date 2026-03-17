#!/usr/bin/env bash
# =============================================================================
# Pathology Permissions Demo - Interactive Walkthrough Script
# =============================================================================
#
# This script walks through the key concepts of the pathology permissions demo
# using curl commands against the running services. Each step includes
# explanations and pauses for the user to observe the results.
#
# Prerequisites: Run setup.sh first to initialize the environment.
#
# Usage:
#   cd simple/
#   ./scripts/demo-workflow.sh

set -euo pipefail

ONTOCLOAK_URL="https://localhost:9090"
AUTHORING_URL="https://localhost:9081"
PRODUCTION_URL="https://localhost:9082"
REALM="pathology-demo"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

explain() {
    echo -e "${BLUE}$*${NC}"
}

pause() {
    echo ""
    echo -e "${YELLOW}Press Enter to continue...${NC}"
    read -r
}

get_token() {
    local username="$1"
    curl -sf -k -X POST \
        "${ONTOCLOAK_URL}/auth/realms/${REALM}/protocol/openid-connect/token" \
        -d "grant_type=password" \
        -d "client_id=demo-cli" \
        -d "username=${username}" \
        -d "password=demo" | jq -r '.access_token'
}

run_cmd() {
    echo -e "${GREEN}\$ $*${NC}"
    eval "$@" 2>&1 || true
    echo ""
}

# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo ""
echo "============================================================"
echo "  Pathology Permissions Demo - Interactive Walkthrough"
echo "============================================================"
echo ""
echo "This walkthrough demonstrates resource-level permissions"
echo "in Ontoserver using Ontocloak communities."
echo ""
echo "We'll show how different pathology providers can:"
echo "  - See a shared national standard reference set"
echo "  - Create their own local code systems and maps"
echo "  - NOT see each other's local resources"
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  You can explore the demo in two ways:"
echo ""
echo "    [a] Automated — this script runs curl commands for you"
echo "        and explains what's happening at each step"
echo ""
echo "    [m] Manual — follow the written walkthrough using"
echo "        Shrimp, Snapper, and OntoCommand web tools"
echo "        See: docs/walkthrough-simple.md"
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
read -r -p "  Choose [a/m] (default: a): " demo_choice
demo_choice="${demo_choice:-a}"

if [ "$demo_choice" = "m" ] || [ "$demo_choice" = "M" ]; then
    echo ""
    echo "  To follow the manual walkthrough, open:"
    echo ""
    echo "    docs/walkthrough-simple.md"
    echo ""
    echo "  Web tools (add ?iss=https://localhost:<port>):"
    echo "    Shrimp:      https://ontoserver.csiro.au/shrimp"
    echo "    Snapper:     https://ontoserver.csiro.au/snapper"
    echo "    OntoCommand: https://ontoserver.csiro.au/ui"
    echo ""
    echo "  Server ports:"
    echo "    9081  Authoring Ontoserver"
    echo "    9082  Production Ontoserver"
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
step "Anonymous access to the production server"

explain "The production server has anonymous FHIR read access enabled."
explain "Anyone can see resources labeled with '*.read' (the national valueset)."
explain "Let's search for ValueSets without authenticating:"
echo ""

run_cmd "curl -sk '${PRODUCTION_URL}/fhir/ValueSet?url=http://example.org/ValueSet/national-pathology-refset' | jq '.total, .entry[0].resource.title'"

explain ""
explain "The national pathology valueset is visible to everyone."
explain "But community-specific resources are NOT visible anonymously:"
echo ""

run_cmd "curl -sk '${PRODUCTION_URL}/fhir/CodeSystem?url=http://pathology-alpha.example.com/CodeSystem/pathology-codes' | jq '.total'"

explain ""
explain "Without authentication, the Alpha CodeSystem is not visible (total: 0)."
explain "The security label 'ALPHA.read' requires PERM_ALPHA_READ in the token."

pause

# =============================================================================
step "Pathology Alpha author sees their own resources"

explain "Let's authenticate as alpha-author and search for CodeSystems."
explain "Alpha-author has PERM_ALPHA_READ and PERM_ALPHA_WRITE via the"
explain "'Pathology Alpha authors' community group."
echo ""

ALPHA_TOKEN=$(get_token "alpha-author")
explain "Token obtained for alpha-author. Searching for CodeSystems..."
echo ""

run_cmd "curl -sk -H 'Authorization: Bearer ${ALPHA_TOKEN}' '${AUTHORING_URL}/fhir/CodeSystem' | jq '[.entry[].resource | {url: .url, title: .title}]'"

explain ""
explain "Alpha-author can see ONLY the Pathology Alpha CodeSystem."
explain "Beta and Gamma CodeSystems are not visible."

pause

# =============================================================================
step "Pathology Alpha author CANNOT see Beta's resources"

explain "Let's specifically search for Beta's CodeSystem as alpha-author:"
echo ""

run_cmd "curl -sk -H 'Authorization: Bearer ${ALPHA_TOKEN}' '${AUTHORING_URL}/fhir/CodeSystem?url=http://pathology-beta.example.com/CodeSystem/pathology-codes' | jq '.total'"

explain ""
explain "Result: 0 - Alpha-author cannot see Beta's resources."
explain "This is because Beta's CodeSystem has 'BETA.read' security label,"
explain "and alpha-author's token only contains PERM_ALPHA_READ."

pause

# =============================================================================
step "Pathology Alpha author CAN see the national valueset"

explain "The national valueset has '*.read' label, which only requires"
explain "API-level FHIR_READ access. Since alpha-author has FHIR_READ"
explain "(via the Author composite role), they can see it."
echo ""

run_cmd "curl -sk -H 'Authorization: Bearer ${ALPHA_TOKEN}' '${AUTHORING_URL}/fhir/ValueSet?url=http://example.org/ValueSet/national-pathology-refset' | jq '.total, .entry[0].resource.title'"

explain ""
explain "Alpha-author can see the national valueset but cannot modify it"
explain "(it requires PERM_NATIONAL_WRITE, which they don't have)."

pause

# =============================================================================
step "Pathology Beta author sees different resources"

explain "Now let's authenticate as beta-author and compare."
echo ""

BETA_TOKEN=$(get_token "beta-author")
explain "Token obtained for beta-author. Searching for CodeSystems..."
echo ""

run_cmd "curl -sk -H 'Authorization: Bearer ${BETA_TOKEN}' '${AUTHORING_URL}/fhir/CodeSystem' | jq '[.entry[].resource | {url: .url, title: .title}]'"

explain ""
explain "Beta-author sees ONLY the Pathology Beta CodeSystem."
explain "Alpha and Gamma CodeSystems are invisible to them."

pause

# =============================================================================
step "Admin sees ALL resources"

explain "The admin user has PERM_READ and PERM_WRITE (wildcard community access)"
explain "via the 'All communities authors' group. They see everything."
echo ""

ADMIN_TOKEN=$(get_token "admin")
run_cmd "curl -sk -H 'Authorization: Bearer ${ADMIN_TOKEN}' '${AUTHORING_URL}/fhir/CodeSystem' | jq '[.entry[].resource | {url: .url, title: .title}]'"

explain ""
explain "Admin can see all three CodeSystems (Alpha, Beta, Gamma)."

pause

# =============================================================================
step "Alpha viewer has read-only access"

explain "alpha-viewer is in the 'Pathology Alpha consumers' community group."
explain "They have PERM_ALPHA_READ but NOT PERM_ALPHA_WRITE."
explain "They can see Alpha resources but cannot modify them."
echo ""

VIEWER_TOKEN=$(get_token "alpha-viewer")

explain "Let's verify they can read the Alpha CodeSystem:"
run_cmd "curl -sk -H 'Authorization: Bearer ${VIEWER_TOKEN}' '${AUTHORING_URL}/fhir/CodeSystem?url=http://pathology-alpha.example.com/CodeSystem/pathology-codes' | jq '.total'"

explain ""
explain "Now let's try to UPDATE the Alpha CodeSystem as a viewer:"
echo ""

HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" -X PUT \
    "${AUTHORING_URL}/fhir/CodeSystem/alpha-pathology-codes" \
    -H "Authorization: Bearer ${VIEWER_TOKEN}" \
    -H "Content-Type: application/fhir+json" \
    -d '{"resourceType":"CodeSystem","id":"alpha-pathology-codes","url":"http://pathology-alpha.example.com/CodeSystem/pathology-codes","status":"active","content":"complete","concept":[{"code":"TEST","display":"Test"}]}' 2>/dev/null) || true

echo -e "${GREEN}HTTP response: ${HTTP_CODE}${NC}"
explain ""
explain "The update is rejected because alpha-viewer lacks PERM_ALPHA_WRITE."

pause

# =============================================================================
step "Alpha author creates a new version of their CodeSystem"

explain "alpha-author has PERM_ALPHA_WRITE and can create new resources in the"
explain "Alpha community. The existing CodeSystem (version 1.0.0) was syndicated"
explain "to this server, so it cannot be overwritten in-place — the author lacks"
explain "SYND_WRITE. Instead, the author creates a NEW version (1.1.0) as a"
explain "separate resource with a new ID."
echo ""

ALPHA_TOKEN=$(get_token "alpha-author")

# Read current CodeSystem to use as a base
CURRENT_CS=$(curl -sk -H "Authorization: Bearer ${ALPHA_TOKEN}" \
    "${AUTHORING_URL}/fhir/CodeSystem/alpha-pathology-codes")

# Create a new version: new resource ID, bumped version, added concept
NEW_CS=$(echo "$CURRENT_CS" | jq '
    .id = "alpha-pathology-codes-v1-1-0"
    | .version = "1.1.0"
    | .concept += [{"code": "D-DIM", "display": "D-Dimer", "definition": "D-dimer test for thrombosis"}]
    | .count = (.concept | length)
    | del(.meta.versionId, .meta.lastUpdated)
')

HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" -X PUT \
    "${AUTHORING_URL}/fhir/CodeSystem/alpha-pathology-codes-v1-1-0" \
    -H "Authorization: Bearer ${ALPHA_TOKEN}" \
    -H "Content-Type: application/fhir+json" \
    -d "$NEW_CS" 2>/dev/null)

echo -e "${GREEN}HTTP response: ${HTTP_CODE}${NC}"
explain ""
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
    explain "Successfully created Alpha CodeSystem version 1.1.0 with a new D-Dimer concept."
    explain "The original 1.0.0 version remains unchanged."
else
    explain "Create returned HTTP ${HTTP_CODE}."
fi

pause

# =============================================================================
step "Viewing the ConceptMap for Alpha's pathology codes"

explain "Each provider maintains a ConceptMap that maps their local codes"
explain "to the national standard reference set. Let's view Alpha's map:"
echo ""

run_cmd "curl -sk -H 'Authorization: Bearer ${ALPHA_TOKEN}' '${AUTHORING_URL}/fhir/ConceptMap/alpha-pathology-to-national' | jq '{title: .title, source: .sourceUri, target: .targetUri, mappings: [.group[0].element[:3][] | {local_code: .code, national_code: .target[0].code, national_display: .target[0].display, equivalence: .target[0].equivalence}]}'"

explain ""
explain "This shows how Alpha's local codes (FBC, BGL, HBA1C) map to the national standard."

pause

# =============================================================================
step "Syndication: Content flows to production"

explain "The authoring server publishes its content via syndication."
explain "The production server syndicates from authoring using the"
explain "syndication-consumer service account (OAuth2 client credentials)."
explain "This account has PERM_READ (all communities read) so it can access"
explain "all community-labeled resources from authoring."
explain ""
explain "Let's check if the national valueset has synced to production:"
echo ""

run_cmd "curl -sk '${PRODUCTION_URL}/fhir/ValueSet?url=http://example.org/ValueSet/national-pathology-refset' | jq '.total, .entry[0].resource.title'"

explain ""
explain "The national valueset is available on production."
explain "Community resources will also sync once they're picked up by the"
explain "production server's scheduled poll."
echo ""
explain "You can check the authoring syndication feed directly:"
run_cmd "curl -sk '${AUTHORING_URL}/synd/syndication.xml' | head -30"

pause

# =============================================================================
step "Using the CSV-to-FHIR pipeline (Pathology Gamma)"

explain "Pathology Gamma maintains their pathology codes in CSV format"
explain "in a Git repository. The csv-transform.py script converts them"
explain "to FHIR resources with appropriate security labels."
echo ""
explain "The generated resources are in the 'generated/' directory:"
echo ""

if [ -d "${PROJECT_DIR}/generated" ]; then
    run_cmd "ls -la ${PROJECT_DIR}/generated/"
    echo ""
    explain "Let's peek at the generated CodeSystem:"
    run_cmd "jq '{url: .url, title: .title, count: .count, security: [.meta.security[].code]}' ${PROJECT_DIR}/generated/gamma-pathology-codes.json"
else
    explain "(Generated files not found - run setup.sh first)"
fi

explain ""
explain "The security labels GAMMA.read and GAMMA.write ensure only"
explain "Gamma community members can see these resources."

pause

# =============================================================================
echo ""
echo "============================================================"
echo -e "  ${GREEN}Walkthrough Complete!${NC}"
echo "============================================================"
echo ""
echo "Key takeaways:"
echo ""
echo "  1. RESOURCE ISOLATION: Each provider's resources are only"
echo "     visible to their community members (ALPHA.read, BETA.read)"
echo ""
echo "  2. SHARED RESOURCES: The national valueset (*.read) is"
echo "     visible to everyone but writable by only national admins"
echo ""
echo "  3. ROLE-BASED ACCESS: Viewers can read, authors can write,"
echo "     approvers can manage syndication"
echo ""
echo "  4. SYNDICATION: Content flows from authoring to production"
echo "     via Atom feeds, preserving security labels"
echo ""
echo "  5. CSV PIPELINE: External code systems can be maintained"
echo "     in version-controlled CSV and transformed to FHIR"
echo ""
echo "  Next steps:"
echo "    - Open Snapper at https://localhost:9081/snapper"
echo "      and log in as different users to see the UI experience"
echo "    - Try the Atomio variant for release candidate management"
echo "      (see docs/walkthrough-atomio.md)"
echo ""
