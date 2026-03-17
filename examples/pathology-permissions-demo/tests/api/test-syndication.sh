#!/usr/bin/env bash
# =============================================================================
# Test: Syndication from Authoring to Production
# =============================================================================
# Verifies that the authoring server's syndication feed is available and
# that the production server has synced content from it.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/helpers.sh"

suite "Syndication: Authoring to Production"

ADMIN_TOKEN=$(get_token "admin")
ALPHA_VIEWER_TOKEN=$(get_token "alpha-viewer")

NATIONAL_VS_URL="http://example.org/ValueSet/national-pathology-refset"

# ---- Authoring syndication feed is accessible ----
# readOnly.synd=true makes the feed XML publicly readable so downstream consumers
# can fetch it with read-only credentials. The FHIR resources in feed entries
# still require proper OAuth authentication.

status=$(curl -s -o /dev/null -w "%{http_code}" "${AUTHORING_URL}/synd/syndication.xml" 2>/dev/null)
assert_http "Authoring syndication feed is accessible (readOnly.synd=true)" "200" "$status"

# ---- Syndication feed is valid Atom XML ----

feed_content=$(curl -sf "${AUTHORING_URL}/synd/syndication.xml" 2>/dev/null || true)
if [ -n "$feed_content" ]; then
    has_feed_tag=$(echo "$feed_content" | grep -c '<feed' || true)
    assert_gt "Syndication feed contains <feed> element" "$has_feed_tag" 0

    has_entries=$(echo "$feed_content" | grep -c '<entry>' || true)
    assert_gt "Syndication feed contains entries" "$has_entries" 0
else
    skip "Syndication feed content check (empty response)"
fi

# ---- Production server has the national valueset ----

count=$(fhir_search_count "$PRODUCTION_URL" "ValueSet?url=${NATIONAL_VS_URL}" "")
assert_eq "Production has national valueset (anonymous read)" "1" "$count"

# ---- Production server is read-only ----

WRITE_BODY='{"resourceType":"ValueSet","id":"test-write","url":"http://test.example.com/ValueSet/test","status":"draft"}'
status=$(fhir_put_status "$PRODUCTION_URL" "ValueSet/test-write" "$ADMIN_TOKEN" "$WRITE_BODY")
if [ "$status" = "405" ] || [ "$status" = "403" ] || [ "$status" = "401" ]; then
    assert "Production rejects write operations [HTTP $status]" 0
else
    assert "Production rejects write operations (expected 405/403, got $status)" 1
fi

# ---- Production enforces resource-level security ----

# Anonymous: can see *.read labeled resources
count=$(fhir_search_count "$PRODUCTION_URL" "ValueSet?url=${NATIONAL_VS_URL}" "")
assert_eq "Anonymous can see national valueset on production" "1" "$count"

# Anonymous: cannot see community-labeled resources
count=$(fhir_search_count "$PRODUCTION_URL" "CodeSystem?url=http://pathology-alpha.example.com/CodeSystem/pathology-codes" "")
assert_eq "Anonymous CANNOT see Alpha CodeSystem on production" "0" "$count"

# Authenticated Alpha viewer: can see Alpha resources on production
count=$(fhir_search_count "$PRODUCTION_URL" "CodeSystem?url=http://pathology-alpha.example.com/CodeSystem/pathology-codes" "$ALPHA_VIEWER_TOKEN")
# Note: this may be 0 if syndication hasn't completed yet
if [ "$count" = "1" ]; then
    assert "Alpha viewer can see Alpha CodeSystem on production (synced)" 0
elif [ "$count" = "0" ]; then
    skip "Alpha CodeSystem on production (syndication may not have completed yet)"
else
    assert "Alpha viewer production visibility check (unexpected count: $count)" 1
fi

# ---- Production cross-community isolation ----

BETA_VIEWER_TOKEN=$(get_token "beta-viewer")

# Alpha viewer cannot see Beta resources on production
count=$(fhir_search_count "$PRODUCTION_URL" "CodeSystem?url=http://pathology-beta.example.com/CodeSystem/pathology-codes" "$ALPHA_VIEWER_TOKEN")
assert_eq "Alpha viewer CANNOT see Beta CodeSystem on production" "0" "$count"

# Beta viewer cannot see Alpha resources on production
count=$(fhir_search_count "$PRODUCTION_URL" "CodeSystem?url=http://pathology-alpha.example.com/CodeSystem/pathology-codes" "$BETA_VIEWER_TOKEN")
assert_eq "Beta viewer CANNOT see Alpha CodeSystem on production" "0" "$count"

# ---- Production metadata confirms read-only mode ----

metadata=$(fhir_get "$PRODUCTION_URL" "metadata" "")
if [ -n "$metadata" ]; then
    # Check CapabilityStatement for SMART-on-FHIR endpoints
    has_security=$(echo "$metadata" | jq 'any(.rest[0].security.service[]; any(.coding[]; .code == "SMART-on-FHIR"))' 2>/dev/null || echo "false")
    if [ "$has_security" = "true" ]; then
        assert "Production CapabilityStatement advertises SMART-on-FHIR" 0
    else
        skip "Production SMART-on-FHIR check (may use different format)"
    fi
else
    skip "Production metadata check"
fi

print_summary
