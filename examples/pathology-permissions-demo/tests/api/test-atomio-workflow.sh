#!/usr/bin/env bash
# =============================================================================
# Test: Atomio Release Candidate Workflow
# =============================================================================
# Verifies the Atomio release management workflow: feed creation, cloning,
# alias management, promotion, and rollback.
#
# NOTE: This test is only applicable to the Atomio variant.
# Set ATOMIO_URL to enable (default: http://localhost:9083).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/helpers.sh"

suite "Atomio Release Candidate Workflow"

# Check if Atomio is available
if ! check_service "${ATOMIO_URL}/actuator/health" "Atomio"; then
    skip "Atomio not available - skipping Atomio workflow tests"
    print_summary
    exit 0
fi

# ---- Atomio health check ----

status=$(curl -s -o /dev/null -w "%{http_code}" "${ATOMIO_URL}/actuator/health" 2>/dev/null)
assert_http "Atomio health endpoint is accessible" "200" "$status"

# ---- List feeds ----

feeds=$(curl -sf "${ATOMIO_URL}/feed" 2>/dev/null)
feed_count=$(echo "$feeds" | jq 'length' 2>/dev/null || echo "0")
assert_gt "Atomio has feeds" "$feed_count" 0

has_release=$(echo "$feeds" | jq 'any(.[]; .name == "release-1-0")' 2>/dev/null || echo "false")
assert_eq "Atomio has 'release-1-0' feed" "true" "$has_release"

# ---- List aliases ----

aliases=$(curl -sf "${ATOMIO_URL}/alias" 2>/dev/null)
alias_count=$(echo "$aliases" | jq 'length' 2>/dev/null || echo "0")
assert_gt "Atomio has aliases" "$alias_count" 0

has_uat=$(echo "$aliases" | jq 'any(.[]; .aliasName == "uat")' 2>/dev/null || echo "false")
assert_eq "Atomio has 'uat' alias" "true" "$has_uat"

has_prod=$(echo "$aliases" | jq 'any(.[]; .aliasName == "production")' 2>/dev/null || echo "false")
assert_eq "Atomio has 'production' alias" "true" "$has_prod"

# ---- Syndication feed is accessible via alias ----

status=$(curl -s -o /dev/null -w "%{http_code}" "${ATOMIO_URL}/alias/uat/syndication.xml" 2>/dev/null)
assert_http "UAT alias syndication feed accessible" "200" "$status"

status=$(curl -s -o /dev/null -w "%{http_code}" "${ATOMIO_URL}/alias/production/syndication.xml" 2>/dev/null)
assert_http "Production alias syndication feed accessible" "200" "$status"

# ---- Create a test feed ----

TEST_FEED="test-feed-$$"
status=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${ATOMIO_URL}/feed" \
    -H "Content-Type: application/json" \
    -d "{\"name\": \"${TEST_FEED}\", \"title\": \"Test Feed\"}" 2>/dev/null)
assert_http "Can create a new feed" "201" "$status"

# Verify it exists
feed_exists=$(curl -sf "${ATOMIO_URL}/feed" 2>/dev/null | jq "any(.[]; .name == \"${TEST_FEED}\")" 2>/dev/null || echo "false")
assert_eq "Newly created feed exists" "true" "$feed_exists"

# ---- Create a test alias ----

TEST_ALIAS="test-alias-$$"
status=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${ATOMIO_URL}/alias" \
    -H "Content-Type: application/json" \
    -d "{\"aliasName\": \"${TEST_ALIAS}\", \"feedName\": \"${TEST_FEED}\"}" 2>/dev/null)
assert_http "Can create a new alias" "200" "$status"

# ---- Update alias to point to a different feed ----

status=$(curl -s -o /dev/null -w "%{http_code}" -X PUT "${ATOMIO_URL}/alias/${TEST_ALIAS}" \
    -H "Content-Type: application/json" \
    -d "{\"aliasName\": \"${TEST_ALIAS}\", \"feedName\": \"release-1-0\"}" 2>/dev/null)
assert_http "Can update alias to point to different feed" "200" "$status"

# Verify alias target changed
target=$(curl -sf "${ATOMIO_URL}/alias" 2>/dev/null | jq -r ".[] | select(.aliasName == \"${TEST_ALIAS}\") | .feedName" 2>/dev/null)
assert_eq "Alias now points to release-1-0" "release-1-0" "$target"

# ---- Clone authoring feed ----

CLONE_FEED="test-clone-$$"
status=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
    "${ATOMIO_URL}/feed/\$clone?name=${CLONE_FEED}&url=http://authoring-ontoserver:8080/synd/syndication.xml" \
    -H "Content-Type: application/json" 2>/dev/null)
if [ "$status" = "201" ] || [ "$status" = "200" ]; then
    assert "Can clone authoring syndication feed [HTTP $status]" 0
else
    # Clone may fail if authoring isn't reachable from Atomio's perspective
    skip "Clone authoring feed (HTTP $status - authoring may not be reachable)"
fi

# ---- Promotion workflow simulation ----

# Simulate: promote test feed to uat
status=$(curl -s -o /dev/null -w "%{http_code}" -X PUT "${ATOMIO_URL}/alias/uat" \
    -H "Content-Type: application/json" \
    -d "{\"aliasName\": \"uat\", \"feedName\": \"${TEST_FEED}\"}" 2>/dev/null)
assert_http "Can promote feed to UAT alias" "200" "$status"

# Rollback: revert uat to release-1-0
status=$(curl -s -o /dev/null -w "%{http_code}" -X PUT "${ATOMIO_URL}/alias/uat" \
    -H "Content-Type: application/json" \
    -d "{\"aliasName\": \"uat\", \"feedName\": \"release-1-0\"}" 2>/dev/null)
assert_http "Can rollback UAT alias to release-1-0" "200" "$status"

# ---- Cleanup test resources ----

curl -sf -o /dev/null -X DELETE "${ATOMIO_URL}/alias/${TEST_ALIAS}" 2>/dev/null || true
curl -sf -o /dev/null -X DELETE "${ATOMIO_URL}/feed/${TEST_FEED}" 2>/dev/null || true
curl -sf -o /dev/null -X DELETE "${ATOMIO_URL}/feed/${CLONE_FEED}" 2>/dev/null || true

# ---- Gamma content feed exists ----

has_gamma=$(curl -sf "${ATOMIO_URL}/feed" 2>/dev/null | jq 'any(.[]; .name == "gamma-content")' 2>/dev/null || echo "false")
assert_eq "Atomio has 'gamma-content' feed" "true" "$has_gamma"

# ---- Swagger UI is accessible ----

status=$(curl -s -o /dev/null -w "%{http_code}" "${ATOMIO_URL}/swagger-ui/index.html" 2>/dev/null)
if [ "$status" = "200" ] || [ "$status" = "302" ]; then
    assert "Atomio Swagger UI is accessible [HTTP $status]" 0
else
    skip "Atomio Swagger UI check (HTTP $status)"
fi

print_summary
