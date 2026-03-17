#!/usr/bin/env bash
# =============================================================================
# Test: National ValueSet Visibility and Write Protection
# =============================================================================
# Verifies that the national pathology valueset (labeled *.read + NATIONAL.write)
# is visible to all authenticated users but only writable by national admins.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/helpers.sh"

suite "National ValueSet Visibility and Write Protection"

ALPHA_VIEWER_TOKEN=$(get_token "alpha-viewer")
ALPHA_AUTHOR_TOKEN=$(get_token "alpha-author")
BETA_AUTHOR_TOKEN=$(get_token "beta-author")
NATIONAL_ADMIN_TOKEN=$(get_token "national-admin")
ADMIN_TOKEN=$(get_token "admin")

NATIONAL_VS_URL="http://example.org/ValueSet/national-pathology-refset"

# ---- Visibility: all authenticated users can see the national valueset ----

count=$(fhir_search_count "$AUTHORING_URL" "ValueSet?url=${NATIONAL_VS_URL}" "$ALPHA_VIEWER_TOKEN")
assert_eq "Alpha viewer can see national valueset" "1" "$count"

count=$(fhir_search_count "$AUTHORING_URL" "ValueSet?url=${NATIONAL_VS_URL}" "$ALPHA_AUTHOR_TOKEN")
assert_eq "Alpha author can see national valueset" "1" "$count"

count=$(fhir_search_count "$AUTHORING_URL" "ValueSet?url=${NATIONAL_VS_URL}" "$BETA_AUTHOR_TOKEN")
assert_eq "Beta author can see national valueset" "1" "$count"

count=$(fhir_search_count "$AUTHORING_URL" "ValueSet?url=${NATIONAL_VS_URL}" "$NATIONAL_ADMIN_TOKEN")
assert_eq "National admin can see national valueset" "1" "$count"

count=$(fhir_search_count "$AUTHORING_URL" "ValueSet?url=${NATIONAL_VS_URL}" "$ADMIN_TOKEN")
assert_eq "Admin can see national valueset" "1" "$count"

# ---- Content check: valueset has expected national concepts ----

vs_body=$(fhir_get "$AUTHORING_URL" "ValueSet/national-pathology-refset" "$ADMIN_TOKEN")
if [ -n "$vs_body" ] && [ "$vs_body" != "null" ]; then
    concept_count=$(echo "$vs_body" | jq '.compose.include[0].concept | length' 2>/dev/null || echo "0")
    assert_gt "National valueset has multiple national concepts" "$concept_count" 10

    has_fbc=$(echo "$vs_body" | jq 'any(.compose.include[0].concept[]; .code == "26604007")' 2>/dev/null || echo "false")
    assert_eq "National valueset includes FBC (26604007)" "true" "$has_fbc"
else
    skip "National valueset content check (could not read resource)"
fi

# ---- Security labels check ----

if [ -n "$vs_body" ] && [ "$vs_body" != "null" ]; then
    has_star_read=$(echo "$vs_body" | jq 'any(.meta.security[]; .code == "*.read")' 2>/dev/null || echo "false")
    assert_eq "National valueset has *.read security label" "true" "$has_star_read"

    has_national_write=$(echo "$vs_body" | jq 'any(.meta.security[]; .code == "NATIONAL.write")' 2>/dev/null || echo "false")
    assert_eq "National valueset has NATIONAL.write security label" "true" "$has_national_write"
fi

# ---- Write protection: regular authors cannot modify ----

MODIFY_BODY='{"resourceType":"ValueSet","id":"national-pathology-refset","url":"'"${NATIONAL_VS_URL}"'","status":"active","compose":{"include":[{"system":"http://example.org/CodeSystem/national-pathology-codes","concept":[{"code":"TEST","display":"Hacked"}]}]}}'

status=$(fhir_put_status "$AUTHORING_URL" "ValueSet/national-pathology-refset" "$ALPHA_AUTHOR_TOKEN" "$MODIFY_BODY")
if [ "$status" = "403" ] || [ "$status" = "401" ]; then
    assert "Alpha author CANNOT modify national valueset [HTTP $status]" 0
else
    assert "Alpha author CANNOT modify national valueset (expected 403, got $status)" 1
fi

status=$(fhir_put_status "$AUTHORING_URL" "ValueSet/national-pathology-refset" "$BETA_AUTHOR_TOKEN" "$MODIFY_BODY")
if [ "$status" = "403" ] || [ "$status" = "401" ]; then
    assert "Beta author CANNOT modify national valueset [HTTP $status]" 0
else
    assert "Beta author CANNOT modify national valueset (expected 403, got $status)" 1
fi

# ---- Write access: national admin and admin CAN modify (modify + revert) ----

ORIGINAL_VS=$(fhir_get "$AUTHORING_URL" "ValueSet/national-pathology-refset" "$ADMIN_TOKEN")
if [ -n "$ORIGINAL_VS" ] && [ "$ORIGINAL_VS" != "null" ]; then
    # National admin: modify the valueset title then revert
    MODIFIED_VS=$(echo "$ORIGINAL_VS" | jq '.title = "National Pathology Reference Set (test edit)"')
    status=$(fhir_put_status "$AUTHORING_URL" "ValueSet/national-pathology-refset" "$NATIONAL_ADMIN_TOKEN" "$MODIFIED_VS")
    if [ "$status" = "200" ] || [ "$status" = "201" ]; then
        assert "National admin CAN modify national valueset [HTTP $status]" 0
        # Revert
        fhir_put_status "$AUTHORING_URL" "ValueSet/national-pathology-refset" "$ADMIN_TOKEN" "$ORIGINAL_VS" > /dev/null 2>&1
    else
        assert "National admin CAN modify national valueset (expected 200, got $status)" 1
    fi

    # Admin: verify admin can also write
    MODIFIED_VS2=$(echo "$ORIGINAL_VS" | jq '.title = "National Pathology Reference Set (admin test)"')
    status=$(fhir_put_status "$AUTHORING_URL" "ValueSet/national-pathology-refset" "$ADMIN_TOKEN" "$MODIFIED_VS2")
    if [ "$status" = "200" ] || [ "$status" = "201" ]; then
        assert "Admin CAN modify national valueset [HTTP $status]" 0
        # Revert
        fhir_put_status "$AUTHORING_URL" "ValueSet/national-pathology-refset" "$ADMIN_TOKEN" "$ORIGINAL_VS" > /dev/null 2>&1
    else
        assert "Admin CAN modify national valueset (expected 200, got $status)" 1
    fi
else
    skip "National valueset write test (could not read original resource)"
fi

print_summary
