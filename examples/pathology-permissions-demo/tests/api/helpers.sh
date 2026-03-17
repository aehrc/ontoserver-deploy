#!/usr/bin/env bash
# =============================================================================
# Shared test helpers for API tests
# =============================================================================

set -euo pipefail

ONTOCLOAK_URL="${ONTOCLOAK_URL:-http://localhost:9090}"
AUTHORING_URL="${AUTHORING_URL:-http://localhost:9081}"
PRODUCTION_URL="${PRODUCTION_URL:-http://localhost:9082}"
ATOMIO_URL="${ATOMIO_URL:-http://localhost:9083}"
UAT_URL="${UAT_URL:-http://localhost:9084}"
PRODUCTION_ATOMIO_URL="${PRODUCTION_ATOMIO_URL:-http://localhost:9085}"
REALM="${REALM:-pathology-demo}"

# Colours
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0
CURRENT_SUITE=""

# Start a test suite
suite() {
    CURRENT_SUITE="$1"
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  Suite: ${CURRENT_SUITE}${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Assert a condition; pass description + exit code
assert() {
    local description="$1"
    local result="$2"

    if [ "$result" -eq 0 ]; then
        echo -e "  ${GREEN}PASS${NC}  ${description}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "  ${RED}FAIL${NC}  ${description}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

skip() {
    local description="$1"
    echo -e "  ${YELLOW}SKIP${NC}  ${description}"
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
}

# Assert equality
assert_eq() {
    local description="$1"
    local expected="$2"
    local actual="$3"

    if [ "$expected" = "$actual" ]; then
        assert "$description" 0
    else
        assert "$description (expected='$expected', got='$actual')" 1
    fi
}

# Assert numeric greater than
assert_gt() {
    local description="$1"
    local value="$2"
    local threshold="$3"

    if [ "$value" -gt "$threshold" ] 2>/dev/null; then
        assert "$description" 0
    else
        assert "$description (expected >$threshold, got '$value')" 1
    fi
}

# Assert HTTP status code
assert_http() {
    local description="$1"
    local expected_code="$2"
    local actual_code="$3"

    assert_eq "$description [HTTP $expected_code]" "$expected_code" "$actual_code"
}

# Get an access token for a user via the demo-cli client
get_token() {
    local username="$1"
    local password="${2:-demo}"
    curl -sf -X POST \
        "${ONTOCLOAK_URL}/auth/realms/${REALM}/protocol/openid-connect/token" \
        -d "grant_type=password" \
        -d "client_id=demo-cli" \
        -d "username=${username}" \
        -d "password=${password}" 2>/dev/null | jq -r '.access_token'
}

# Get an admin token for the Keycloak master realm
get_admin_token() {
    curl -sf -X POST \
        "${ONTOCLOAK_URL}/auth/realms/master/protocol/openid-connect/token" \
        -d "grant_type=password" \
        -d "client_id=admin-cli" \
        -d "username=admin" \
        -d "password=admin" 2>/dev/null | jq -r '.access_token'
}

# Make a FHIR GET request and return the response body
fhir_get() {
    local server_url="$1"
    local path="$2"
    local token="${3:-}"

    if [ -n "$token" ]; then
        curl -sf -H "Authorization: Bearer ${token}" "${server_url}/fhir/${path}" 2>/dev/null
    else
        curl -sf "${server_url}/fhir/${path}" 2>/dev/null
    fi
}

# Make a FHIR GET request and return the HTTP status code
fhir_get_status() {
    local server_url="$1"
    local path="$2"
    local token="${3:-}"

    if [ -n "$token" ]; then
        curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer ${token}" "${server_url}/fhir/${path}" 2>/dev/null || echo "000"
    else
        curl -s -o /dev/null -w "%{http_code}" "${server_url}/fhir/${path}" 2>/dev/null || echo "000"
    fi
}

# Make a FHIR PUT request and return the HTTP status code
fhir_put_status() {
    local server_url="$1"
    local path="$2"
    local token="$3"
    local body="$4"

    curl -s -o /dev/null -w "%{http_code}" -X PUT \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: application/fhir+json" \
        -d "$body" \
        "${server_url}/fhir/${path}" 2>/dev/null || echo "000"
}

# Count the number of entries in a FHIR Bundle search result
fhir_search_count() {
    local server_url="$1"
    local path="$2"
    local token="${3:-}"

    local result
    result=$(fhir_get "$server_url" "$path" "$token")
    echo "$result" | jq -r '.total // 0' 2>/dev/null || echo "0"
}

# Print test summary
print_summary() {
    local total=$((TESTS_PASSED + TESTS_FAILED + TESTS_SKIPPED))
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  Results: ${GREEN}${TESTS_PASSED} passed${NC}, ${RED}${TESTS_FAILED} failed${NC}, ${YELLOW}${TESTS_SKIPPED} skipped${NC} (${total} total)"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    if [ "$TESTS_FAILED" -gt 0 ]; then
        return 1
    fi
    return 0
}

# Wait for a resource to appear on a downstream server (syndication polling).
# Polls fhir_search_count until it returns the expected count or timeout.
wait_for_syndication() {
    local server_url="$1"
    local search_path="$2"
    local token="${3:-}"
    local expected_count="${4:-1}"
    local timeout="${5:-180}"
    local description="${6:-resource}"

    local elapsed=0
    local interval=10
    echo -e "  ${YELLOW}WAIT${NC}  Waiting for ${description} to syndicate (timeout: ${timeout}s)..."
    while [ "$elapsed" -lt "$timeout" ]; do
        local count
        count=$(fhir_search_count "$server_url" "$search_path" "$token")
        if [ "$count" = "$expected_count" ]; then
            echo -e "  ${GREEN}SYNC${NC}  ${description} appeared after ${elapsed}s"
            return 0
        fi
        sleep "$interval"
        elapsed=$((elapsed + interval))
    done
    echo -e "  ${YELLOW}TIMEOUT${NC}  ${description} did not appear within ${timeout}s"
    return 1
}

# Wait for a specific resource version to appear on a downstream server.
wait_for_version() {
    local server_url="$1"
    local resource_path="$2"
    local token="${3:-}"
    local expected_version="$4"
    local timeout="${5:-180}"

    local elapsed=0
    local interval=10
    echo -e "  ${YELLOW}WAIT${NC}  Waiting for version '${expected_version}' on ${resource_path} (timeout: ${timeout}s)..."
    while [ "$elapsed" -lt "$timeout" ]; do
        local body
        body=$(fhir_get "$server_url" "$resource_path" "$token")
        local version
        version=$(echo "$body" | jq -r '.version // ""' 2>/dev/null)
        if [ "$version" = "$expected_version" ]; then
            echo -e "  ${GREEN}SYNC${NC}  Version '${expected_version}' arrived after ${elapsed}s"
            return 0
        fi
        sleep "$interval"
        elapsed=$((elapsed + interval))
    done
    echo -e "  ${YELLOW}TIMEOUT${NC}  Version '${expected_version}' did not arrive within ${timeout}s"
    return 1
}

# Check that a service is reachable
check_service() {
    local url="$1"
    local name="$2"
    if curl -sf -o /dev/null --max-time 5 "$url" 2>/dev/null; then
        return 0
    else
        echo -e "${RED}ERROR: ${name} is not reachable at ${url}${NC}"
        echo "  Run the setup script first: ./scripts/setup.sh"
        return 1
    fi
}
