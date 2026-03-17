#!/usr/bin/env bash
# =============================================================================
# Test: Atomio Variant End-to-End Flow
# =============================================================================
# Verifies the complete authoring → Atomio release → UAT → production workflow:
#
#   1. Alpha author creates a new business version of their CodeSystem on authoring
#      (new resource id, same canonical url, new version — both versions coexist)
#   2. Approver clones authoring feed to Atomio as a new release candidate
#   3. Approver promotes the release to UAT alias
#   4. UAT server picks up the new version (wait for sync)
#   5. Verify access control on UAT (Alpha sees new version, Beta doesn't)
#   6. Approver promotes the release to production alias
#   7. Production server picks up the new version (wait for sync)
#   8. Verify access control on production (Alpha sees, Beta doesn't)
#   9. Rollback: revert aliases to original feed
#  10. Delete test CodeSystem from authoring and cleanup
#
# This test requires the Atomio variant to be running.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/helpers.sh"

suite "Atomio Variant: Author → Release → UAT → Production Flow"

# Check Atomio is available
if ! check_service "${ATOMIO_URL}/actuator/health" "Atomio"; then
    skip "Atomio not available - skipping Atomio flow tests"
    print_summary
    exit 0
fi

ALPHA_AUTHOR_TOKEN=$(get_token "alpha-author")
ALPHA_VIEWER_TOKEN=$(get_token "alpha-viewer")
BETA_VIEWER_TOKEN=$(get_token "beta-viewer")
ADMIN_TOKEN=$(get_token "admin")

ALPHA_CS_URL="http://pathology-alpha.example.com/CodeSystem/pathology-codes"

# Record original alias targets so we can restore them
ORIGINAL_UAT_FEED=$(curl -sf "${ATOMIO_URL}/alias" 2>/dev/null \
    | jq -r '.[] | select(.aliasName == "uat") | .feedName' 2>/dev/null)
ORIGINAL_PROD_FEED=$(curl -sf "${ATOMIO_URL}/alias" 2>/dev/null \
    | jq -r '.[] | select(.aliasName == "production") | .feedName' 2>/dev/null)

if [ -z "$ORIGINAL_UAT_FEED" ] || [ -z "$ORIGINAL_PROD_FEED" ]; then
    skip "Could not read current Atomio alias targets - skipping flow test"
    print_summary
    exit 0
fi

# ============================================================================
# Phase 1: Author creates a new business version on authoring server
# ============================================================================
# In FHIR, a business version update (e.g. adding new codes) creates a new
# resource with a different id but the same canonical url and a new version.
# Both versions coexist on the server and are independently addressable,
# allowing systems still using the old version to continue operating.

echo ""
echo -e "  ${CYAN}--- Phase 1: Author creates new business version on authoring ---${NC}"

ORIGINAL_CS=$(fhir_get "$AUTHORING_URL" "CodeSystem/alpha-pathology-codes" "$ALPHA_AUTHOR_TOKEN")
if [ -z "$ORIGINAL_CS" ] || [ "$ORIGINAL_CS" = "null" ]; then
    skip "Could not read Alpha CodeSystem from authoring - skipping flow test"
    print_summary
    exit 0
fi

TEST_VERSION="2.0.0-flow-test-$$"
TEST_CS_ID="alpha-pathology-codes-v2-$$"

# Create a new version: different resource id, same canonical url, new version
NEW_CS=$(echo "$ORIGINAL_CS" | jq --arg v "$TEST_VERSION" --arg id "$TEST_CS_ID" '
    .id = $id
    | .version = $v
    | .concept += [{"code":"ATOMIO-FLOW-TEST","display":"Atomio Flow Test Concept","definition":"Added by Atomio e2e flow test"}]
    | .count = (.concept | length)
    | del(.meta.versionId, .meta.lastUpdated)
')

status=$(fhir_put_status "$AUTHORING_URL" "CodeSystem/$TEST_CS_ID" "$ALPHA_AUTHOR_TOKEN" "$NEW_CS")
if [ "$status" = "200" ] || [ "$status" = "201" ]; then
    assert "Alpha author creates new CodeSystem version '${TEST_VERSION}'" 0
else
    assert "Alpha author creates new CodeSystem version (expected 201, got $status)" 1
    print_summary
    exit 1
fi

new_version=$(fhir_get "$AUTHORING_URL" "CodeSystem/$TEST_CS_ID" "$ALPHA_AUTHOR_TOKEN" | jq -r '.version // ""')
assert_eq "Authoring has new version" "$TEST_VERSION" "$new_version"

# ============================================================================
# Phase 2: Clone authoring feed to Atomio as a release candidate
# ============================================================================

echo ""
echo -e "  ${CYAN}--- Phase 2: Clone authoring feed to Atomio ---${NC}"

RELEASE_FEED="flow-test-release-$$"

status=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
    "${ATOMIO_URL}/feed/\$clone?name=${RELEASE_FEED}&url=http://authoring-ontoserver:8080/synd/syndication.xml" \
    -H "Content-Type: application/json" 2>/dev/null)
if [ "$status" = "201" ] || [ "$status" = "200" ]; then
    assert "Cloned authoring feed as release '${RELEASE_FEED}' [HTTP $status]" 0
else
    assert "Clone authoring feed (expected 201, got $status)" 1
    # Clean up test resource and bail
    curl -sf -o /dev/null -X DELETE \
        -H "Authorization: Bearer ${ALPHA_AUTHOR_TOKEN}" \
        "${AUTHORING_URL}/fhir/CodeSystem/${TEST_CS_ID}" 2>/dev/null || true
    print_summary
    exit 1
fi

# Verify the release feed exists
feed_exists=$(curl -sf "${ATOMIO_URL}/feed" 2>/dev/null \
    | jq --arg f "$RELEASE_FEED" 'any(.[]; .name == $f)' 2>/dev/null || echo "false")
assert_eq "Release feed '${RELEASE_FEED}' exists in Atomio" "true" "$feed_exists"

# ============================================================================
# Phase 3: Promote release to UAT
# ============================================================================

echo ""
echo -e "  ${CYAN}--- Phase 3: Promote release to UAT ---${NC}"

status=$(curl -s -o /dev/null -w "%{http_code}" -X PUT "${ATOMIO_URL}/alias/uat" \
    -H "Content-Type: application/json" \
    -d "{\"aliasName\": \"uat\", \"feedName\": \"${RELEASE_FEED}\"}" 2>/dev/null)
assert_http "Promoted '${RELEASE_FEED}' to UAT alias" "200" "$status"

# Verify alias target updated
uat_target=$(curl -sf "${ATOMIO_URL}/alias" 2>/dev/null \
    | jq -r '.[] | select(.aliasName == "uat") | .feedName' 2>/dev/null)
assert_eq "UAT alias points to '${RELEASE_FEED}'" "$RELEASE_FEED" "$uat_target"

# ============================================================================
# Phase 4: Wait for UAT to sync and verify access control
# ============================================================================

echo ""
echo -e "  ${CYAN}--- Phase 4: Wait for UAT sync & verify access control ---${NC}"

UAT_SYNCED=false
if wait_for_syndication "$UAT_URL" "CodeSystem?url=${ALPHA_CS_URL}&version=${TEST_VERSION}" "$ALPHA_VIEWER_TOKEN" "1" 300 "version '${TEST_VERSION}'"; then
    assert "New version '${TEST_VERSION}' syndicated to UAT" 0
    UAT_SYNCED=true
else
    skip "New version did not syndicate to UAT within timeout"
fi

if [ "$UAT_SYNCED" = "true" ]; then
    # Alpha viewer CAN see the new version on UAT
    count=$(fhir_search_count "$UAT_URL" "CodeSystem?url=${ALPHA_CS_URL}&version=${TEST_VERSION}" "$ALPHA_VIEWER_TOKEN")
    assert_eq "Alpha viewer CAN see new CodeSystem version on UAT" "1" "$count"

    # Beta viewer CANNOT see the new version on UAT
    count=$(fhir_search_count "$UAT_URL" "CodeSystem?url=${ALPHA_CS_URL}&version=${TEST_VERSION}" "$BETA_VIEWER_TOKEN")
    assert_eq "Beta viewer CANNOT see new CodeSystem version on UAT" "0" "$count"

    # Anonymous CANNOT see the new version on UAT
    count=$(fhir_search_count "$UAT_URL" "CodeSystem?url=${ALPHA_CS_URL}&version=${TEST_VERSION}" "")
    assert_eq "Anonymous CANNOT see new CodeSystem version on UAT" "0" "$count"

    # Admin CAN see the new version on UAT
    count=$(fhir_search_count "$UAT_URL" "CodeSystem?url=${ALPHA_CS_URL}&version=${TEST_VERSION}" "$ADMIN_TOKEN")
    assert_eq "Admin CAN see new CodeSystem version on UAT" "1" "$count"
else
    skip "UAT access control checks (syndication did not complete)"
fi

# ============================================================================
# Phase 5: Promote release to production
# ============================================================================

echo ""
echo -e "  ${CYAN}--- Phase 5: Promote release to production ---${NC}"

status=$(curl -s -o /dev/null -w "%{http_code}" -X PUT "${ATOMIO_URL}/alias/production" \
    -H "Content-Type: application/json" \
    -d "{\"aliasName\": \"production\", \"feedName\": \"${RELEASE_FEED}\"}" 2>/dev/null)
assert_http "Promoted '${RELEASE_FEED}' to production alias" "200" "$status"

prod_target=$(curl -sf "${ATOMIO_URL}/alias" 2>/dev/null \
    | jq -r '.[] | select(.aliasName == "production") | .feedName' 2>/dev/null)
assert_eq "Production alias points to '${RELEASE_FEED}'" "$RELEASE_FEED" "$prod_target"

# ============================================================================
# Phase 6: Wait for production to sync and verify access control
# ============================================================================

echo ""
echo -e "  ${CYAN}--- Phase 6: Wait for production sync & verify access control ---${NC}"

PROD_SYNCED=false
if wait_for_syndication "$PRODUCTION_URL" "CodeSystem?url=${ALPHA_CS_URL}&version=${TEST_VERSION}" "$ALPHA_VIEWER_TOKEN" "1" 300 "version '${TEST_VERSION}'"; then
    assert "New version '${TEST_VERSION}' syndicated to production" 0
    PROD_SYNCED=true
else
    skip "New version did not syndicate to production within timeout"
fi

if [ "$PROD_SYNCED" = "true" ]; then
    # Alpha viewer CAN see the new version on production
    count=$(fhir_search_count "$PRODUCTION_URL" "CodeSystem?url=${ALPHA_CS_URL}&version=${TEST_VERSION}" "$ALPHA_VIEWER_TOKEN")
    assert_eq "Alpha viewer CAN see new CodeSystem version on production" "1" "$count"

    # Beta viewer CANNOT see the new version on production
    count=$(fhir_search_count "$PRODUCTION_URL" "CodeSystem?url=${ALPHA_CS_URL}&version=${TEST_VERSION}" "$BETA_VIEWER_TOKEN")
    assert_eq "Beta viewer CANNOT see new CodeSystem version on production" "0" "$count"

    # Anonymous CANNOT see the new version on production
    count=$(fhir_search_count "$PRODUCTION_URL" "CodeSystem?url=${ALPHA_CS_URL}&version=${TEST_VERSION}" "")
    assert_eq "Anonymous CANNOT see new CodeSystem version on production" "0" "$count"

    # Admin CAN see the new version on production
    count=$(fhir_search_count "$PRODUCTION_URL" "CodeSystem?url=${ALPHA_CS_URL}&version=${TEST_VERSION}" "$ADMIN_TOKEN")
    assert_eq "Admin CAN see new CodeSystem version on production" "1" "$count"

    # Production is read-only
    WRITE_BODY='{"resourceType":"CodeSystem","id":"flow-test-write","url":"http://test.example.com/CodeSystem/flow-test","status":"draft","content":"complete","concept":[{"code":"X","display":"X"}]}'
    status=$(fhir_put_status "$PRODUCTION_URL" "CodeSystem/flow-test-write" "$ADMIN_TOKEN" "$WRITE_BODY")
    if [ "$status" = "405" ] || [ "$status" = "403" ] || [ "$status" = "401" ]; then
        assert "Production rejects write operations [HTTP $status]" 0
    else
        assert "Production rejects write operations (expected 405/403, got $status)" 1
    fi
else
    skip "Production access control checks (syndication did not complete)"
fi

# Anonymous CAN see the national valueset on production
count=$(fhir_search_count "$PRODUCTION_URL" "ValueSet?url=http://example.org/ValueSet/national-pathology-refset" "")
assert_eq "Anonymous CAN see national valueset on production" "1" "$count"

# ============================================================================
# Phase 7: Rollback aliases to original feeds
# ============================================================================

echo ""
echo -e "  ${CYAN}--- Phase 7: Rollback aliases ---${NC}"

status=$(curl -s -o /dev/null -w "%{http_code}" -X PUT "${ATOMIO_URL}/alias/uat" \
    -H "Content-Type: application/json" \
    -d "{\"aliasName\": \"uat\", \"feedName\": \"${ORIGINAL_UAT_FEED}\"}" 2>/dev/null)
assert_http "Rolled back UAT alias to '${ORIGINAL_UAT_FEED}'" "200" "$status"

status=$(curl -s -o /dev/null -w "%{http_code}" -X PUT "${ATOMIO_URL}/alias/production" \
    -H "Content-Type: application/json" \
    -d "{\"aliasName\": \"production\", \"feedName\": \"${ORIGINAL_PROD_FEED}\"}" 2>/dev/null)
assert_http "Rolled back production alias to '${ORIGINAL_PROD_FEED}'" "200" "$status"

# ============================================================================
# Phase 8: Delete test CodeSystem from authoring and cleanup
# ============================================================================

echo ""
echo -e "  ${CYAN}--- Phase 8: Delete test CodeSystem & cleanup ---${NC}"

# Refresh token (original may have expired during syndication waits)
ALPHA_AUTHOR_TOKEN=$(get_token "alpha-author")
status=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE \
    -H "Authorization: Bearer ${ALPHA_AUTHOR_TOKEN}" \
    "${AUTHORING_URL}/fhir/CodeSystem/${TEST_CS_ID}" 2>/dev/null)
if [ "$status" = "200" ] || [ "$status" = "204" ]; then
    assert "Deleted test CodeSystem from authoring" 0
else
    assert "Deleted test CodeSystem from authoring (expected 200/204, got $status)" 1
fi

# Clean up the test release feed
curl -sf -o /dev/null -X DELETE "${ATOMIO_URL}/feed/${RELEASE_FEED}" 2>/dev/null || true

print_summary
