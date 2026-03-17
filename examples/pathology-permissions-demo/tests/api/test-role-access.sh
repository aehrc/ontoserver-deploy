#!/usr/bin/env bash
# =============================================================================
# Test: Role-Based Access Control
# =============================================================================
# Verifies that viewers can read but not write, authors can read and write
# their community's resources, and approvers have syndication access.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/helpers.sh"

suite "Role-Based Access Control"

ALPHA_VIEWER_TOKEN=$(get_token "alpha-viewer")
ALPHA_AUTHOR_TOKEN=$(get_token "alpha-author")
ALPHA_APPROVER_TOKEN=$(get_token "alpha-approver")
ADMIN_TOKEN=$(get_token "admin")

ALPHA_CS_URL="http://pathology-alpha.example.com/CodeSystem/pathology-codes"
BETA_CS_URL="http://pathology-beta.example.com/CodeSystem/pathology-codes"

# ---- Viewer: read access ----

count=$(fhir_search_count "$AUTHORING_URL" "CodeSystem?url=${ALPHA_CS_URL}" "$ALPHA_VIEWER_TOKEN")
assert_eq "Alpha viewer can READ Alpha CodeSystem" "1" "$count"

# ---- Viewer: no write access ----

# Try to update Alpha's CodeSystem as a viewer
UPDATE_BODY='{"resourceType":"CodeSystem","id":"alpha-pathology-codes","url":"'"${ALPHA_CS_URL}"'","status":"active","content":"complete","concept":[{"code":"TEST","display":"Test"}]}'
status=$(fhir_put_status "$AUTHORING_URL" "CodeSystem/alpha-pathology-codes" "$ALPHA_VIEWER_TOKEN" "$UPDATE_BODY")
assert_http "Alpha viewer CANNOT write Alpha CodeSystem" "403" "$status"

# ---- Author: read + write access to own community ----

# The existing CodeSystems are syndicated (secureSyndicated=true), so regular
# authors cannot modify them without SYND_WRITE. Test write access by creating
# a new (non-syndicated) resource instead.
TEST_WRITE_ID="alpha-role-test-$$"
WRITE_BODY='{"resourceType":"CodeSystem","id":"'"${TEST_WRITE_ID}"'","url":"http://pathology-alpha.example.com/CodeSystem/role-test","status":"draft","content":"complete","concept":[{"code":"ROLE-TEST","display":"Role Test Concept"}],"meta":{"security":[{"code":"ALPHA.read"},{"code":"ALPHA.write"}]}}'
status=$(fhir_put_status "$AUTHORING_URL" "CodeSystem/${TEST_WRITE_ID}" "$ALPHA_AUTHOR_TOKEN" "$WRITE_BODY")
if [ "$status" = "200" ] || [ "$status" = "201" ]; then
    assert "Alpha author CAN create new CodeSystem in own community [HTTP $status]" 0
    # Clean up
    curl -sfk -o /dev/null -X DELETE \
        -H "Authorization: Bearer ${ALPHA_AUTHOR_TOKEN}" \
        "${AUTHORING_URL}/fhir/CodeSystem/${TEST_WRITE_ID}" 2>/dev/null || true
else
    assert "Alpha author CAN create new CodeSystem (expected 200/201, got $status)" 1
fi

# Syndicated resources require SYND_WRITE (which authors don't have)
CURRENT_CS=$(fhir_get "$AUTHORING_URL" "CodeSystem/alpha-pathology-codes" "$ALPHA_AUTHOR_TOKEN")
if [ -n "$CURRENT_CS" ] && [ "$CURRENT_CS" != "null" ]; then
    MODIFIED=$(echo "$CURRENT_CS" | jq '.concept += [{"code":"TEST_ROLE","display":"Role Test Concept"}]')
    status=$(fhir_put_status "$AUTHORING_URL" "CodeSystem/alpha-pathology-codes" "$ALPHA_AUTHOR_TOKEN" "$MODIFIED")
    assert_http "Alpha author CANNOT modify syndicated CodeSystem (secureSyndicated)" "403" "$status"
else
    skip "Alpha author syndicated write test (could not read current resource)"
fi

# ---- Author: no write access to other community ----

BETA_UPDATE_BODY='{"resourceType":"CodeSystem","id":"beta-pathology-codes","url":"'"${BETA_CS_URL}"'","status":"active","content":"complete","concept":[{"code":"TEST","display":"Test"}]}'
status=$(fhir_put_status "$AUTHORING_URL" "CodeSystem/beta-pathology-codes" "$ALPHA_AUTHOR_TOKEN" "$BETA_UPDATE_BODY")
# Either 403 (forbidden) or 404 (not found because filtered) is acceptable
if [ "$status" = "403" ] || [ "$status" = "404" ] || [ "$status" = "401" ]; then
    assert "Alpha author CANNOT write Beta CodeSystem [HTTP $status]" 0
else
    assert "Alpha author CANNOT write Beta CodeSystem (expected 403/404, got $status)" 1
fi

# ---- Approver: has syndication access ----

status=$(curl -sk -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer ${ALPHA_APPROVER_TOKEN}" \
    "${AUTHORING_URL}/synd/syndication.xml" 2>/dev/null)
assert_http "Alpha approver can read syndication feed" "200" "$status"

# ---- Viewer: no syndication write access ----

# readOnly.synd=true makes the syndication feed XML publicly readable, so
# all authenticated users (including viewers) can read it. The FHIR resources
# referenced in the feed still require proper community permissions.
status=$(curl -sk -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer ${ALPHA_VIEWER_TOKEN}" \
    "${AUTHORING_URL}/synd/syndication.xml" 2>/dev/null)
assert_http "Alpha viewer can read syndication feed (readOnly.synd=true)" "200" "$status"

# ---- Anonymous: no access to authoring FHIR ----

anon_status=$(curl -sk -o /dev/null -w "%{http_code}" "${AUTHORING_URL}/fhir/CodeSystem" 2>/dev/null)
if [ "$anon_status" = "401" ] || [ "$anon_status" = "403" ]; then
    assert "Anonymous FHIR access denied on authoring [HTTP $anon_status]" 0
else
    # If readOnly.fhir=true, anonymous sees 0 community resources (only *.read)
    count=$(fhir_search_count "$AUTHORING_URL" "CodeSystem" "")
    assert_eq "Anonymous cannot see community CodeSystems on authoring" "0" "${count:-0}"
fi

# ---- Token contents validation ----

# Decode token and verify authorities
if command -v base64 &>/dev/null; then
    # JWT base64url needs padding; handle both GNU (-d) and macOS (-D) base64
    JWT_PART=$(echo "$ALPHA_AUTHOR_TOKEN" | cut -d. -f2 | tr '_-' '/+')
    # Add padding if needed
    case $((${#JWT_PART} % 4)) in
        2) JWT_PART="${JWT_PART}==" ;;
        3) JWT_PART="${JWT_PART}=" ;;
    esac
    PAYLOAD=$(echo "$JWT_PART" | base64 --decode 2>/dev/null || echo "$JWT_PART" | base64 -D 2>/dev/null || true)
    if [ -n "$PAYLOAD" ]; then
        has_fhir_read=$(echo "$PAYLOAD" | jq 'any(.authorities[]; . == "https://localhost:9081/fhirFHIR_READ")' 2>/dev/null || echo "false")
        assert_eq "Alpha author token contains https://localhost:9081/fhirFHIR_READ" "true" "$has_fhir_read"

        has_fhir_write=$(echo "$PAYLOAD" | jq 'any(.authorities[]; . == "https://localhost:9081/fhirFHIR_WRITE")' 2>/dev/null || echo "false")
        assert_eq "Alpha author token contains https://localhost:9081/fhirFHIR_WRITE" "true" "$has_fhir_write"

        has_perm_alpha_read=$(echo "$PAYLOAD" | jq 'any(.authorities[]; . == "PERM_ALPHA_READ")' 2>/dev/null || echo "false")
        assert_eq "Alpha author token contains PERM_ALPHA_READ" "true" "$has_perm_alpha_read"

        has_perm_alpha_write=$(echo "$PAYLOAD" | jq 'any(.authorities[]; . == "PERM_ALPHA_WRITE")' 2>/dev/null || echo "false")
        assert_eq "Alpha author token contains PERM_ALPHA_WRITE" "true" "$has_perm_alpha_write"

        has_perm_beta=$(echo "$PAYLOAD" | jq 'any(.authorities[]; . == "PERM_BETA_READ")' 2>/dev/null || echo "false")
        assert_eq "Alpha author token does NOT contain PERM_BETA_READ" "false" "$has_perm_beta"
    else
        skip "Token payload decode (base64 decode failed)"
    fi
else
    skip "Token contents validation (base64 not available)"
fi

print_summary
