#!/usr/bin/env bash
# =============================================================================
# Pathology Permissions Demo - Atomio Variant Setup Script
# =============================================================================
#
# This script sets up the Atomio variant of the pathology permissions demo.
# In addition to the simple example setup, this:
#   - Starts Atomio (syndication/release candidate server)
#   - Creates initial feeds and aliases in Atomio
#   - Creates a release candidate from the authoring content
#   - Sets up UAT and production Ontoserver instances syncing from Atomio
#   - Demonstrates the CSV-to-Atomio pipeline for Pathology Gamma
#
# Usage:
#   cd atomio/
#   ./scripts/setup.sh
#
# After setup completes, access:
#   - Ontocloak admin:     https://localhost:9090/auth/admin  (admin/admin)
#   - Authoring Snapper:   https://localhost:9081/snapper
#   - Atomio API:          https://localhost:9083/swagger-ui/index.html
#   - UAT Snapper:         https://localhost:9084/snapper
#   - Production Snapper:  https://localhost:9082/snapper
#   - Demo users:          All use password "demo"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMMON_DIR="$(cd "${PROJECT_DIR}/../common" && pwd)"

ONTOCLOAK_URL="https://localhost:9090"
AUTHORING_URL="https://localhost:9081"
ATOMIO_URL="https://localhost:9083"
UAT_URL="https://localhost:9084"
PRODUCTION_URL="https://localhost:9082"
REALM="pathology-demo"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${BLUE}[SETUP]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

wait_for_service() {
    local url="$1" timeout="${2:-180}" name="${3:-service}"
    log "Waiting for ${name}..."
    local elapsed=0
    while [ "$elapsed" -lt "$timeout" ]; do
        if curl -sf -k -o /dev/null --max-time 5 "$url" 2>/dev/null; then
            success "${name} is ready (${elapsed}s)"
            return 0
        fi
        sleep 3
        elapsed=$((elapsed + 3))
        [ $((elapsed % 30)) -eq 0 ] && log "  ...still waiting for ${name} (${elapsed}s)"
    done
    error "${name} did not become ready within ${timeout}s"
}

get_admin_token() {
    curl -sf -k -X POST \
        "${ONTOCLOAK_URL}/auth/realms/master/protocol/openid-connect/token" \
        -d "grant_type=password&client_id=admin-cli&username=admin&password=admin" \
        | jq -r '.access_token'
}

get_user_token() {
    local username="$1"
    curl -sf -k -X POST \
        "${ONTOCLOAK_URL}/auth/realms/${REALM}/protocol/openid-connect/token" \
        -d "grant_type=password&client_id=demo-cli&username=${username}&password=demo" \
        | jq -r '.access_token'
}

get_group_id() {
    local group_path="$1"
    local token search_term
    token=$(get_admin_token)
    search_term=$(echo "$group_path" | awk -F'/' '{print $NF}' | sed 's/ /%20/g')
    curl -sf -k -H "Authorization: Bearer ${token}" \
        "${ONTOCLOAK_URL}/auth/admin/realms/${REALM}/groups?search=${search_term}" \
        | jq -r ".. | objects | select(.path==\"${group_path}\") | .id" | head -1
}

get_user_id() {
    local username="$1"
    local token
    token=$(get_admin_token)
    curl -sf -k -H "Authorization: Bearer ${token}" \
        "${ONTOCLOAK_URL}/auth/admin/realms/${REALM}/users?username=${username}&exact=true" \
        | jq -r '.[0].id'
}

add_user_to_group() {
    local username="$1" group_path="$2"
    local token user_id group_id
    token=$(get_admin_token)
    user_id=$(get_user_id "$username")
    group_id=$(get_group_id "$group_path")
    if [ -z "$user_id" ] || [ "$user_id" = "null" ] || [ -z "$group_id" ] || [ "$group_id" = "null" ]; then
        warn "  Skipping ${username} --> ${group_path} (not found)"
        return
    fi
    curl -sf -k -X PUT \
        "${ONTOCLOAK_URL}/auth/admin/realms/${REALM}/users/${user_id}/groups/${group_id}" \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: application/json" -d "{}" || true
    success "  ${username} --> ${group_path}"
}

create_community() {
    local name="$1" label="$2"
    local token
    # Communities API requires a realm-level token (not master admin)
    token=$(get_user_token "admin")
    log "Creating community: ${name} (label: ${label})..."
    local http_code
    http_code=$(curl -sf -k -o /dev/null -w "%{http_code}" -X POST \
        "${ONTOCLOAK_URL}/auth/realms/${REALM}/communities" \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: application/json" \
        -d "{\"communityName\": \"${name}\", \"securityLabel\": \"${label}\"}" 2>&1) || true
    if [ "$http_code" = "201" ] || [ "$http_code" = "200" ]; then
        success "Community '${name}' created"
    else
        warn "Community '${name}': HTTP ${http_code} (may already exist)"
    fi
}

load_resource() {
    local file="$1" token="$2"
    local rt ri
    rt=$(jq -r '.resourceType' "$file")
    ri=$(jq -r '.id' "$file")
    log "Loading ${rt}/${ri}..."
    local http_code
    http_code=$(curl -sf -k -o /dev/null -w "%{http_code}" -X PUT \
        "${AUTHORING_URL}/fhir/${rt}/${ri}" \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: application/fhir+json" \
        -d @"$file") || true
    if [ "$http_code" = "200" ] || [ "$http_code" = "201" ]; then
        success "  ${rt}/${ri} loaded"
    else
        warn "  ${rt}/${ri} returned HTTP ${http_code}"
    fi
}

# Assign a realm role to a service account by role name
assign_realm_role() {
    local user_id="$1" role_name="$2"
    local token
    token=$(get_admin_token)
    local role_json
    role_json=$(curl -sf -k -H "Authorization: Bearer ${token}" \
        "${ONTOCLOAK_URL}/auth/admin/realms/${REALM}/roles/${role_name}" 2>/dev/null) || true
    if [ -z "$role_json" ] || [ "$role_json" = "null" ]; then
        warn "  Role '${role_name}' not found"; return
    fi
    curl -sf -k -X POST \
        "${ONTOCLOAK_URL}/auth/admin/realms/${REALM}/users/${user_id}/role-mappings/realm" \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: application/json" \
        -d "[${role_json}]" || true
}

# Assign a client role to a service account
assign_client_role() {
    local user_id="$1" client_id_name="$2" role_name="$3"
    local token
    token=$(get_admin_token)
    local client_uuid
    client_uuid=$(curl -sf -k -H "Authorization: Bearer ${token}" \
        "${ONTOCLOAK_URL}/auth/admin/realms/${REALM}/clients?clientId=${client_id_name}" \
        | jq -r '.[0].id')
    if [ -z "$client_uuid" ] || [ "$client_uuid" = "null" ]; then
        warn "  Client '${client_id_name}' not found"; return
    fi
    local role_json
    role_json=$(curl -sf -k -H "Authorization: Bearer ${token}" \
        "${ONTOCLOAK_URL}/auth/admin/realms/${REALM}/clients/${client_uuid}/roles/${role_name}" 2>/dev/null) || true
    if [ -z "$role_json" ] || [ "$role_json" = "null" ]; then
        warn "  Client role '${role_name}' on '${client_id_name}' not found"; return
    fi
    curl -sf -k -X POST \
        "${ONTOCLOAK_URL}/auth/admin/realms/${REALM}/users/${user_id}/role-mappings/clients/${client_uuid}" \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: application/json" \
        -d "[${role_json}]" || true
}

# Configure the syndication-consumer service account with all-communities read access
configure_syndication_consumer() {
    log "Configuring syndication-consumer service account..."
    local token
    token=$(get_admin_token)
    local client_uuid
    client_uuid=$(curl -sf -k -H "Authorization: Bearer ${token}" \
        "${ONTOCLOAK_URL}/auth/admin/realms/${REALM}/clients?clientId=syndication-consumer" \
        | jq -r '.[0].id')
    if [ -z "$client_uuid" ] || [ "$client_uuid" = "null" ]; then
        warn "syndication-consumer client not found. Skipping."; return
    fi
    local sa_user_id
    sa_user_id=$(curl -sf -k -H "Authorization: Bearer ${token}" \
        "${ONTOCLOAK_URL}/auth/admin/realms/${REALM}/clients/${client_uuid}/service-account-user" \
        | jq -r '.id')
    if [ -z "$sa_user_id" ] || [ "$sa_user_id" = "null" ]; then
        warn "Service account user not found for syndication-consumer"; return
    fi
    assign_realm_role "$sa_user_id" "PERM_READ"
    success "  Assigned PERM_READ (all communities read)"
    assign_client_role "$sa_user_id" "authoring-server" "https://localhost:9081/fhirFHIR_READ"
    success "  Assigned https://localhost:9081/fhirFHIR_READ on authoring-server"

    # Note: https://localhost:9081/fhirSYND_READ is NOT assigned here because the authoring
    # server has readOnly.synd=true, making the syndication feed XML publicly
    # readable. If readOnly.synd were false (the default), you would also need
    # to assign https://localhost:9081/fhirSYND_READ to allow the consumer to access the
    # syndication feed metadata.
}

# Print manual configuration instructions for the Ontocloak admin UI
print_manual_instructions() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  Manual Ontocloak Configuration Instructions${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${BLUE}  Open the Ontocloak admin console:${NC}"
    echo "    URL:      ${ONTOCLOAK_URL}/auth/admin"
    echo "    Username: admin"
    echo "    Password: admin"
    echo "    Realm:    pathology-demo (select from top-left dropdown)"
    echo ""
    echo -e "${BLUE}  STEP A: Configure syndication-consumer service account${NC}"
    echo ""
    echo "    The syndication-consumer client is used by UAT and production"
    echo "    Ontoserver instances to fetch community-labeled resources via"
    echo "    syndication from the authoring server (through Atomio)."
    echo ""
    echo "    1. Go to Clients > syndication-consumer > Service Account Roles"
    echo "    2. In 'Realm Roles', assign: PERM_READ"
    echo "       (This grants all-communities read access for syndication)"
    echo "    3. In 'Client Roles', select 'authoring-server' and assign:"
    echo "       https://localhost:9081/fhirFHIR_READ"
    echo ""
    echo "    Note: https://localhost:9081/fhirSYND_READ is not needed here because"
    echo "    readOnly.synd=true is set on the authoring server, making the"
    echo "    syndication feed XML publicly readable. If readOnly.synd were"
    echo "    false, you would also need to assign https://localhost:9081/fhirSYND_READ."
    echo ""
    echo -e "${BLUE}  STEP B: Grant realm-admin to the pathology-demo admin user${NC}"
    echo ""
    echo "    The Communities page requires a realm-level session (not the"
    echo "    master admin session). We need to grant the pathology-demo"
    echo "    'admin' user (password: demo) realm management access, then"
    echo "    log in as that user."
    echo ""
    echo "    While logged in as the MASTER admin (admin/admin):"
    echo ""
    echo "    1. Select the 'pathology-demo' realm (top-left dropdown)"
    echo "    2. Go to Users (left sidebar)"
    echo "    3. Click on the 'admin' user (this is the pathology-demo"
    echo "       realm user, NOT the master admin you're logged in as)"
    echo "    4. Go to the 'Role mapping' tab"
    echo "    5. Click 'Assign role'"
    echo "    6. In the filter dropdown (top-left of the dialog), change"
    echo "       from 'Filter by realm roles' to 'Filter by clients'"
    echo "    7. Find 'realm-admin' under 'realm-management' and assign it"
    echo ""
    echo "    Now log out, then log back in as the pathology-demo admin:"
    echo "      URL:      ${ONTOCLOAK_URL}/auth/admin/${REALM}/console/"
    echo "      Username: admin"
    echo "      Password: demo  (not 'admin' — this is the realm user)"
    echo ""
    echo -e "${BLUE}  STEP C: Create communities${NC}"
    echo ""
    echo "    Now logged in as the realm admin, communities can be created"
    echo "    through the Ontocloak Communities page."
    echo ""
    echo "    1. Select the 'pathology-demo' realm (top-left dropdown)"
    echo "    2. Go to 'Communities' in the left sidebar"
    echo "    3. Click 'Create Community' and create each of the following:"
    echo ""
    echo "       Community Name          Security Label"
    echo "       ─────────────────────   ──────────────"
    echo "       National Pathology      NATIONAL"
    echo "       Pathology Alpha         ALPHA"
    echo "       Pathology Beta          BETA"
    echo "       Pathology Gamma         GAMMA"
    echo ""
    echo "    Make sure you click back to Communities each time you add a new one (works around a Keycloak quirk)"
    echo ""
    echo "    Each community auto-creates:"
    echo "      - Realm roles: PERM_<LABEL>_READ, PERM_<LABEL>_WRITE, PERM_<LABEL>_OWNER"
    echo "      - Groups: '<Name> consumers' (READ), '<Name> authors' (READ+WRITE),"
    echo "                '<Name> owners' (READ+WRITE+OWNER)"
    echo ""
    echo "    After creation, verify:"
    echo "      - Realm Roles (left sidebar): PERM_ALPHA_READ, PERM_ALPHA_WRITE, etc."
    echo "      - Groups > Communities: consumer/author/owner groups for each community"
    echo ""
    echo -e "${BLUE}  STEP D: Assign users to community groups${NC}"
    echo ""
    echo "    Go to Users, select each user, then click Groups > Join Group."
    echo ""
    echo "    Assign the following (community groups are under /Communities/):"
    echo ""
    echo "      national-admin  --> /Communities/National Pathology authors"
    echo "      admin           --> /Community owners/National Pathology owners"
    echo "      admin           --> /Communities/All communities authors"
    echo ""
    echo "      alpha-viewer    --> /Communities/Pathology Alpha consumers"
    echo "      alpha-author    --> /Communities/Pathology Alpha authors"
    echo "      alpha-approver  --> /Communities/Pathology Alpha authors"
    echo ""
    echo "      beta-viewer     --> /Communities/Pathology Beta consumers"
    echo "      beta-author     --> /Communities/Pathology Beta authors"
    echo "      beta-approver   --> /Communities/Pathology Beta authors"
    echo ""
    echo "    Note: Users are already in System groups (Authors/Consumers/Approvers)"
    echo "    from the realm import. These provide the API-level FHIR_READ/FHIR_WRITE"
    echo "    roles. The community groups add the PERM_*_READ/WRITE permissions."
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# =============================================================================
# MAIN
# =============================================================================
main() {
    echo ""
    echo "============================================================"
    echo "  Pathology Permissions Demo - Atomio Variant Setup"
    echo "============================================================"
    echo ""

    cd "$PROJECT_DIR"

    # Check prerequisites
    log "Checking prerequisites..."
    for cmd in docker curl jq python3; do
        command -v "$cmd" &>/dev/null || error "'$cmd' is required"
    done
    docker compose version &>/dev/null || error "'docker compose' required"
    success "Prerequisites met."

    # ------------------------------------------------------------------
    # Step 1: Start Ontocloak
    # ------------------------------------------------------------------
    echo ""
    log "STEP 1: Starting Ontocloak and Caddy (authorization + HTTPS proxy)..."
    docker compose up -d ontocloak-db ontocloak caddy
    wait_for_service "${ONTOCLOAK_URL}/auth/realms/master" 180 "Ontocloak"

    # ------------------------------------------------------------------
    # Step 2: Extract RSA public key
    # ------------------------------------------------------------------
    echo ""
    log "STEP 2: Extracting RSA public key..."
    local token rsa_pub
    token=$(get_admin_token)
    rsa_pub=$(curl -sf -k -H "Authorization: Bearer ${token}" \
        "${ONTOCLOAK_URL}/auth/admin/realms/${REALM}/keys" \
        | jq -r '.keys[] | select(.type=="RSA" and .algorithm=="RS256") | .publicKey')
    [ -z "$rsa_pub" ] || [ "$rsa_pub" = "null" ] && error "Failed to extract RSA key"

    # Ontoserver's ontoserver.security.token.secret property accepts both HMAC
    # secrets and PEM-formatted RSA public keys (auto-detected by PEM markers).
    # We pass it via SPRING_APPLICATION_JSON since env vars can't hold multi-line PEM.
    # JSON \n escapes are interpreted by Spring Boot's JSON parser as actual newlines.
    printf 'ONTOSERVER_SPRING_JSON={"ontoserver.security.token.secret":"-----BEGIN PUBLIC KEY-----\\n%s\\n-----END PUBLIC KEY-----"}\n' \
        "${rsa_pub}" > "${PROJECT_DIR}/.env"
    success "RSA public key written to .env (SPRING_APPLICATION_JSON format)"

    # ------------------------------------------------------------------
    # Step 3: Start authoring Ontoserver and Atomio
    # ------------------------------------------------------------------
    echo ""
    log "STEP 3: Starting Authoring Ontoserver and Atomio..."
    docker compose up -d authoring-db authoring-ontoserver atomio
    wait_for_service "${AUTHORING_URL}/fhir/metadata" 300 "Authoring Ontoserver"
    wait_for_service "${ATOMIO_URL}/actuator/health" 120 "Atomio"

    # ------------------------------------------------------------------
    # Step 3b: Enable authorization services on realm-management client
    # ------------------------------------------------------------------
    # The Ontocloak communities API requires the realm-management client
    # to have authorization services enabled. This is not set by default
    # on realm import, so we enable it via the admin API.
    echo ""
    log "Enabling authorization services on realm-management client..."
    local master_token
    master_token=$(get_admin_token)
    local rm_client_id
    rm_client_id=$(curl -sf -k "${ONTOCLOAK_URL}/auth/admin/realms/${REALM}/clients?clientId=realm-management" \
        -H "Authorization: Bearer ${master_token}" | jq -r '.[0].id')
    if [ -n "$rm_client_id" ] && [ "$rm_client_id" != "null" ]; then
        local rm_json
        rm_json=$(curl -sf -k "${ONTOCLOAK_URL}/auth/admin/realms/${REALM}/clients/${rm_client_id}" \
            -H "Authorization: Bearer ${master_token}")
        local rm_updated
        rm_updated=$(echo "$rm_json" | jq '.authorizationServicesEnabled = true | .serviceAccountsEnabled = true | .bearerOnly = false')
        local rm_status
        rm_status=$(curl -s -k -o /dev/null -w "%{http_code}" -X PUT \
            "${ONTOCLOAK_URL}/auth/admin/realms/${REALM}/clients/${rm_client_id}" \
            -H "Authorization: Bearer ${master_token}" \
            -H "Content-Type: application/json" \
            -d "$rm_updated")
        if [ "$rm_status" = "204" ] || [ "$rm_status" = "200" ]; then
            success "Authorization services enabled on realm-management"
        else
            warn "Could not enable authorization services (HTTP ${rm_status})"
        fi
    else
        warn "Could not find realm-management client"
    fi

    # ------------------------------------------------------------------
    # Steps 4-6: Ontocloak configuration
    # ------------------------------------------------------------------
    # The next steps configure the syndication-consumer service account,
    # create communities, and assign users to community groups.
    # Users can choose to do this manually via the Ontocloak admin UI
    # to better understand how the configuration works.
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  Ontocloak Configuration${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "  The next steps configure communities, user group assignments,"
    echo "  and the syndication-consumer service account."
    echo ""
    echo "  You can either:"
    echo "    [a] Run automatically (script does everything)"
    echo "    [m] Do it manually via the Ontocloak admin UI"
    echo "        (detailed instructions will be provided)"
    echo ""
    read -r -p "  Choose [a/m] (default: a): " config_choice
    config_choice="${config_choice:-a}"

    if [ "$config_choice" = "m" ] || [ "$config_choice" = "M" ]; then
        print_manual_instructions
        echo ""
        echo -e "${YELLOW}  When you have completed the manual configuration, press Enter to continue...${NC}"
        read -r
    else
        # -- Step 4: Configure syndication-consumer service account --
        echo ""
        log "STEP 4: Configuring syndication consumer..."
        configure_syndication_consumer

        # -- Step 5: Create communities --
        echo ""
        log "STEP 5: Creating communities..."
        create_community "National Pathology" "NATIONAL"
        create_community "Pathology Alpha"     "ALPHA"
        create_community "Pathology Beta"      "BETA"
        create_community "Pathology Gamma"     "GAMMA"

        # -- Step 6: Assign users to community groups --
        echo ""
        log "STEP 6: Assigning users to community groups..."
        add_user_to_group "national-admin"  "/Communities/National Pathology authors"
        add_user_to_group "admin"           "/Community owners/National Pathology owners"
        add_user_to_group "alpha-viewer"    "/Communities/Pathology Alpha consumers"
        add_user_to_group "alpha-author"    "/Communities/Pathology Alpha authors"
        add_user_to_group "alpha-approver"  "/Communities/Pathology Alpha authors"
        add_user_to_group "beta-viewer"     "/Communities/Pathology Beta consumers"
        add_user_to_group "beta-author"     "/Communities/Pathology Beta authors"
        add_user_to_group "beta-approver"   "/Communities/Pathology Beta authors"
        add_user_to_group "admin"           "/Communities/All communities authors"
    fi

    # ------------------------------------------------------------------
    # Step 7: Load sample resources
    # ------------------------------------------------------------------
    echo ""
    log "STEP 7: Loading sample resources..."
    local admin_token
    admin_token=$(get_user_token "admin")
    if [ -n "$admin_token" ] && [ "$admin_token" != "null" ]; then
        load_resource "${COMMON_DIR}/sample-resources/alpha-codesystem.json" "$admin_token"
        load_resource "${COMMON_DIR}/sample-resources/alpha-conceptmap.json" "$admin_token"
        load_resource "${COMMON_DIR}/sample-resources/beta-codesystem.json" "$admin_token"
        load_resource "${COMMON_DIR}/sample-resources/beta-conceptmap.json" "$admin_token"
    else
        warn "Could not get admin token. Load resources manually."
    fi

    # ------------------------------------------------------------------
    # Step 8: Generate and load Gamma resources from CSV
    # ------------------------------------------------------------------
    echo ""
    log "STEP 8: Generating Gamma resources from CSV..."
    local gamma_output="${PROJECT_DIR}/generated"
    mkdir -p "$gamma_output"
    python3 "${COMMON_DIR}/scripts/csv-transform.py" \
        --codes "${COMMON_DIR}/csv-data/gamma-codes.csv" \
        --mappings "${COMMON_DIR}/csv-data/gamma-mappings.csv" \
        --output-dir "$gamma_output" \
        --security-label "GAMMA" \
        --codesystem-url "http://pathology-gamma.example.com/CodeSystem/pathology-codes" \
        --conceptmap-url "http://pathology-gamma.example.com/ConceptMap/pathology-to-national" \
        --target-valueset "http://example.org/ValueSet/national-pathology-refset" \
        --publisher "Pathology Gamma"

    if [ -n "${admin_token:-}" ] && [ "$admin_token" != "null" ]; then
        load_resource "${gamma_output}/gamma-pathology-codes.json" "$admin_token"
        load_resource "${gamma_output}/gamma-pathology-to-national.json" "$admin_token"
    fi

    # ------------------------------------------------------------------
    # Step 9: Approve resources for syndication
    # ------------------------------------------------------------------
    # With atom.syndication.publish.fhir.enabled=selected, resources must
    # be explicitly approved (syndication status = true) before they appear
    # in the syndication feed. This simulates the initial approval of all
    # 1.0.0 resources so that Atomio can clone them and downstream servers
    # receive content.
    echo ""
    log "STEP 9: Approving resources for syndication..."
    if [ -n "${admin_token:-}" ] && [ "$admin_token" != "null" ]; then
        for rt_id in \
            "CodeSystem/alpha-pathology-codes" \
            "ConceptMap/alpha-pathology-to-national" \
            "CodeSystem/beta-pathology-codes" \
            "ConceptMap/beta-pathology-to-national" \
            "CodeSystem/gamma-pathology-codes" \
            "ConceptMap/gamma-pathology-to-national"; do
            local resourceType="${rt_id%%/*}"
            local id="${rt_id##*/}"
            local http_code
            http_code=$(curl -sf -k -o /dev/null -w "%{http_code}" -X POST \
                "${AUTHORING_URL}/synd/setSyndicationStatus?resourceType=${resourceType}&id=${id}&syndicate=true" \
                -H "Authorization: Bearer ${admin_token}") || true
            if [ "$http_code" = "200" ] || [ "$http_code" = "204" ]; then
                success "  ${rt_id} approved for syndication"
            else
                warn "  ${rt_id} syndication status returned HTTP ${http_code}"
            fi
        done
    else
        warn "No admin token available — syndication status not set"
    fi

    # ------------------------------------------------------------------
    # Step 10: Create Atomio feeds and release candidate
    # ------------------------------------------------------------------
    echo ""
    log "STEP 10: Setting up Atomio feeds and release candidate..."

    # Wait a moment for authoring syndication to be populated
    sleep 5

    # Get an admin token for Atomio API calls (Atomio security is enabled)
    local atomio_token
    atomio_token=$(get_user_token "admin")

    # Create initial release candidate feed by cloning authoring syndication.
    # Atomio feed names must match ^[A-Za-z0-9-_]+$ (no dots allowed).
    log "Creating release candidate 'release-1-0' from authoring feed..."
    local clone_code
    clone_code=$(curl -sf -k -o /dev/null -w "%{http_code}" -X POST \
        "${ATOMIO_URL}/feed/\$clone?name=release-1-0&url=http://authoring-ontoserver:8080/synd/syndication.xml" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${atomio_token}" 2>&1) || true

    if [ "$clone_code" = "201" ] || [ "$clone_code" = "200" ]; then
        success "Release candidate 'release-1-0' created"
    else
        warn "Clone returned HTTP ${clone_code}"
        # Try creating the feed manually if clone fails
        log "Attempting to create feed manually..."
        curl -sf -k -o /dev/null -X POST "${ATOMIO_URL}/feed" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer ${atomio_token}" \
            -d '{"name": "release-1-0", "title": "Release Candidate 1.0"}' || true
    fi

    # Create 'uat' alias pointing to release-1-0
    # Atomio alias API uses aliasName/feedName fields (not name/feed)
    log "Creating 'uat' alias..."
    curl -sf -k -o /dev/null -X POST "${ATOMIO_URL}/alias" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${atomio_token}" \
        -d '{"aliasName": "uat", "feedName": "release-1-0"}' 2>/dev/null || \
        warn "Failed to create 'uat' alias (may already exist)"
    success "Alias 'uat' -> 'release-1-0'"

    # Create 'production' alias pointing to release-1-0
    log "Creating 'production' alias..."
    curl -sf -k -o /dev/null -X POST "${ATOMIO_URL}/alias" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${atomio_token}" \
        -d '{"aliasName": "production", "feedName": "release-1-0"}' 2>/dev/null || \
        warn "Failed to create 'production' alias (may already exist)"
    success "Alias 'production' -> 'release-1-0'"

    # Create a dedicated feed for Gamma's CSV-sourced content
    log "Creating 'gamma-content' feed for CSV pipeline..."
    curl -sf -k -o /dev/null -X POST "${ATOMIO_URL}/feed" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${atomio_token}" \
        -d '{"name": "gamma-content", "title": "Pathology Gamma - CSV-Sourced Content"}' 2>/dev/null || \
        warn "Failed to create 'gamma-content' feed (may already exist)"
    success "Feed 'gamma-content' created"

    # ------------------------------------------------------------------
    # Step 11: Start UAT and Production Ontoserver
    # ------------------------------------------------------------------
    # UAT and Production syndicate from Atomio aliases using the
    # syndication-consumer service account for authenticated access
    # to community-labeled FHIR resources.
    echo ""
    log "STEP 11: Starting UAT and Production Ontoserver instances..."
    docker compose up -d uat-db uat-ontoserver production-db production-ontoserver
    wait_for_service "${UAT_URL}/fhir/metadata" 300 "UAT Ontoserver"
    wait_for_service "${PRODUCTION_URL}/fhir/metadata" 300 "Production Ontoserver"

    # ------------------------------------------------------------------
    # Done!
    # ------------------------------------------------------------------
    echo ""
    echo "============================================================"
    echo -e "  ${GREEN}Setup complete!${NC}"
    echo "============================================================"
    echo ""
    echo "  Services:"
    echo "    Ontocloak Admin:     ${ONTOCLOAK_URL}/auth/admin"
    echo "    Authoring Snapper:   ${AUTHORING_URL}/snapper"
    echo "    Atomio Swagger UI:   ${ATOMIO_URL}/swagger-ui/index.html"
    echo "    UAT Snapper:         ${UAT_URL}/snapper"
    echo "    Production Snapper:  ${PRODUCTION_URL}/snapper"
    echo ""
    echo "  Atomio Feeds:"
    echo "    release-1-0:  ${ATOMIO_URL}/feed/release-1-0"
    echo "    gamma-content: ${ATOMIO_URL}/feed/gamma-content"
    echo "    Aliases:      uat -> release-1-0, production -> release-1-0"
    echo ""
    echo "  Demo Users (all passwords: 'demo'):"
    echo "    admin, national-admin, alpha-{viewer,author,approver},"
    echo "    beta-{viewer,author,approver}"
    echo ""
    echo -e "  ${CYAN}What next? Choose a walkthrough:${NC}"
    echo ""
    echo "  1) Visual browser walkthrough (Playwright):"
    echo "       ./demo.sh walkthrough atomio"
    echo ""
    echo "  2) Manual walkthrough — follow the docs at your own pace:"
    echo "       docs/walkthrough-atomio.md"
    echo ""
    echo "     Web tools:"
    echo "       Shrimp (authoring):    https://ontoserver.csiro.au/shrimp?iss=${AUTHORING_URL}&clientId=shrimp"
    echo "       Shrimp (UAT):          https://ontoserver.csiro.au/shrimp?iss=${UAT_URL}&clientId=shrimp"
    echo "       Shrimp (production):   https://ontoserver.csiro.au/shrimp?iss=${PRODUCTION_URL}&clientId=shrimp"
    echo "       Snapper (authoring):   https://ontoserver.csiro.au/snapper?iss=${AUTHORING_URL}&clientId=snapper"
    echo "       OntoCommand:           https://ontoserver.csiro.au/ui?iss=${AUTHORING_URL}&clientId=onto-ui"
    echo "       Atomio UI:             ${ATOMIO_URL}"
    echo ""
    echo "  To tear down:  ./demo.sh teardown atomio"
    echo ""
}

main "$@"
