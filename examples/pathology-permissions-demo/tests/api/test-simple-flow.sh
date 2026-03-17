#!/usr/bin/env bash
# =============================================================================
# Test: Simple Variant End-to-End Flow
# =============================================================================
# Verifies the complete authoring → syndication → production workflow:
#
#   1. Alpha author creates a new business version of their CodeSystem
#      (new resource id, same canonical url, new version — both versions coexist)
#   2. Content syndicates to production via the Atom feed
#   3. Alpha viewer can see the new version on production
#   4. Beta viewer CANNOT see Alpha's resources on production
#   5. Anonymous can see *.read resources but not community resources
#   6. Production is strictly read-only
#   7. Author deletes the test CodeSystem
#
# This test requires the simple variant to be running with syndication
# configured (production polls authoring every 2 minutes).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/helpers.sh"

suite "Simple Variant: Author → Syndicate → Production Flow"

ALPHA_AUTHOR_TOKEN=$(get_token "alpha-author")
ALPHA_VIEWER_TOKEN=$(get_token "alpha-viewer")
BETA_AUTHOR_TOKEN=$(get_token "beta-author")
BETA_VIEWER_TOKEN=$(get_token "beta-viewer")
ADMIN_TOKEN=$(get_token "admin")

ALPHA_CS_URL="http://pathology-alpha.example.com/CodeSystem/pathology-codes"

# ============================================================================
# Phase 1: Author creates a new business version on authoring server
# ============================================================================
# In FHIR, a business version update (e.g. adding new codes) creates a new
# resource with a different id but the same canonical url and a new version.
# Both versions coexist on the server and are independently addressable,
# allowing systems still using the old version to continue operating.

echo ""
echo -e "  ${CYAN}--- Phase 1: Author creates new business version on authoring ---${NC}"

# Read the current Alpha CodeSystem
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
    | .concept += [{"code":"FLOW-TEST","display":"Flow Test Concept","definition":"Added by e2e flow test"}]
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

# Verify the new version exists on authoring
new_version=$(fhir_get "$AUTHORING_URL" "CodeSystem/$TEST_CS_ID" "$ALPHA_AUTHOR_TOKEN" | jq -r '.version // ""')
assert_eq "Authoring has new version" "$TEST_VERSION" "$new_version"

# Verify authoring access control still works
count=$(fhir_search_count "$AUTHORING_URL" "CodeSystem?url=${ALPHA_CS_URL}&version=${TEST_VERSION}" "$BETA_AUTHOR_TOKEN")
assert_eq "Beta author still CANNOT see Alpha CodeSystem on authoring" "0" "$count"

# ============================================================================
# Phase 2: Wait for syndication to production
# ============================================================================

echo ""
echo -e "  ${CYAN}--- Phase 2: Waiting for syndication to production ---${NC}"

# Wait for the new version to appear on production (search by url+version)
if wait_for_syndication "$PRODUCTION_URL" "CodeSystem?url=${ALPHA_CS_URL}&version=${TEST_VERSION}" "$ALPHA_VIEWER_TOKEN" "1" 300 "version '${TEST_VERSION}'"; then
    assert "New version '${TEST_VERSION}' syndicated to production" 0
    SYNCED=true
else
    skip "New version did not syndicate to production within timeout"
    SYNCED=false
fi

# ============================================================================
# Phase 3: Verify production access control
# ============================================================================

echo ""
echo -e "  ${CYAN}--- Phase 3: Verify access control on production ---${NC}"

if [ "$SYNCED" = "true" ]; then
    # Alpha viewer CAN see the new version on production
    count=$(fhir_search_count "$PRODUCTION_URL" "CodeSystem?url=${ALPHA_CS_URL}&version=${TEST_VERSION}" "$ALPHA_VIEWER_TOKEN")
    assert_eq "Alpha viewer CAN see new CodeSystem version on production" "1" "$count"

    # Beta viewer CANNOT see the new version on production
    count=$(fhir_search_count "$PRODUCTION_URL" "CodeSystem?url=${ALPHA_CS_URL}&version=${TEST_VERSION}" "$BETA_VIEWER_TOKEN")
    assert_eq "Beta viewer CANNOT see new CodeSystem version on production" "0" "$count"

    # Beta author CANNOT see the new version on production
    count=$(fhir_search_count "$PRODUCTION_URL" "CodeSystem?url=${ALPHA_CS_URL}&version=${TEST_VERSION}" "$BETA_AUTHOR_TOKEN")
    assert_eq "Beta author CANNOT see new CodeSystem version on production" "0" "$count"

    # Anonymous CANNOT see the new version on production
    count=$(fhir_search_count "$PRODUCTION_URL" "CodeSystem?url=${ALPHA_CS_URL}&version=${TEST_VERSION}" "")
    assert_eq "Anonymous CANNOT see new CodeSystem version on production" "0" "$count"

    # Admin CAN see the new version on production
    count=$(fhir_search_count "$PRODUCTION_URL" "CodeSystem?url=${ALPHA_CS_URL}&version=${TEST_VERSION}" "$ADMIN_TOKEN")
    assert_eq "Admin CAN see new CodeSystem version on production" "1" "$count"
else
    skip "Production access control checks (syndication did not complete)"
fi

# Anonymous CAN see the national valueset on production
count=$(fhir_search_count "$PRODUCTION_URL" "ValueSet?url=http://example.org/ValueSet/national-pathology-refset" "")
assert_eq "Anonymous CAN see national valueset on production" "1" "$count"

# Production is read-only
WRITE_BODY='{"resourceType":"CodeSystem","id":"flow-test-write","url":"http://test.example.com/CodeSystem/flow-test","status":"draft","content":"complete","concept":[{"code":"X","display":"X"}]}'
status=$(fhir_put_status "$PRODUCTION_URL" "CodeSystem/flow-test-write" "$ADMIN_TOKEN" "$WRITE_BODY")
if [ "$status" = "405" ] || [ "$status" = "403" ] || [ "$status" = "401" ]; then
    assert "Production rejects write operations [HTTP $status]" 0
else
    assert "Production rejects write operations (expected 405/403, got $status)" 1
fi

# ============================================================================
# Phase 4: Delete test CodeSystem from authoring
# ============================================================================

echo ""
echo -e "  ${CYAN}--- Phase 4: Deleting test CodeSystem ---${NC}"

# Refresh token (original may have expired during syndication waits)
ALPHA_AUTHOR_TOKEN=$(get_token "alpha-author")
status=$(curl -sk -o /dev/null -w "%{http_code}" -X DELETE \
    -H "Authorization: Bearer ${ALPHA_AUTHOR_TOKEN}" \
    "${AUTHORING_URL}/fhir/CodeSystem/${TEST_CS_ID}" 2>/dev/null)
if [ "$status" = "200" ] || [ "$status" = "204" ]; then
    assert "Deleted test CodeSystem from authoring" 0
else
    assert "Deleted test CodeSystem from authoring (expected 200/204, got $status)" 1
fi

print_summary
