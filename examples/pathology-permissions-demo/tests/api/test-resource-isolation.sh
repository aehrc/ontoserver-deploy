#!/usr/bin/env bash
# =============================================================================
# Test: Resource Isolation Between Communities
# =============================================================================
# Verifies that resources labeled with community-specific security labels
# are only visible to members of that community.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/helpers.sh"

suite "Resource Isolation Between Communities"

# Get tokens for each user
ALPHA_AUTHOR_TOKEN=$(get_token "alpha-author")
BETA_AUTHOR_TOKEN=$(get_token "beta-author")
ADMIN_TOKEN=$(get_token "admin")

# ---- Alpha author visibility ----

count=$(fhir_search_count "$AUTHORING_URL" "CodeSystem?url=http://pathology-alpha.example.com/CodeSystem/pathology-codes" "$ALPHA_AUTHOR_TOKEN")
assert_eq "Alpha author can see Alpha CodeSystem" "1" "$count"

count=$(fhir_search_count "$AUTHORING_URL" "ConceptMap?url=http://pathology-alpha.example.com/ConceptMap/pathology-to-national" "$ALPHA_AUTHOR_TOKEN")
assert_eq "Alpha author can see Alpha ConceptMap" "1" "$count"

count=$(fhir_search_count "$AUTHORING_URL" "CodeSystem?url=http://pathology-beta.example.com/CodeSystem/pathology-codes" "$ALPHA_AUTHOR_TOKEN")
assert_eq "Alpha author CANNOT see Beta CodeSystem" "0" "$count"

count=$(fhir_search_count "$AUTHORING_URL" "ConceptMap?url=http://pathology-beta.example.com/ConceptMap/pathology-to-national" "$ALPHA_AUTHOR_TOKEN")
assert_eq "Alpha author CANNOT see Beta ConceptMap" "0" "$count"

count=$(fhir_search_count "$AUTHORING_URL" "CodeSystem?url=http://pathology-gamma.example.com/CodeSystem/pathology-codes" "$ALPHA_AUTHOR_TOKEN")
assert_eq "Alpha author CANNOT see Gamma CodeSystem" "0" "$count"

# ---- Beta author visibility ----

count=$(fhir_search_count "$AUTHORING_URL" "CodeSystem?url=http://pathology-beta.example.com/CodeSystem/pathology-codes" "$BETA_AUTHOR_TOKEN")
assert_eq "Beta author can see Beta CodeSystem" "1" "$count"

count=$(fhir_search_count "$AUTHORING_URL" "CodeSystem?url=http://pathology-alpha.example.com/CodeSystem/pathology-codes" "$BETA_AUTHOR_TOKEN")
assert_eq "Beta author CANNOT see Alpha CodeSystem" "0" "$count"

count=$(fhir_search_count "$AUTHORING_URL" "CodeSystem?url=http://pathology-gamma.example.com/CodeSystem/pathology-codes" "$BETA_AUTHOR_TOKEN")
assert_eq "Beta author CANNOT see Gamma CodeSystem" "0" "$count"

# ---- Admin visibility (wildcard community access) ----

count=$(fhir_search_count "$AUTHORING_URL" "CodeSystem?url=http://pathology-alpha.example.com/CodeSystem/pathology-codes" "$ADMIN_TOKEN")
assert_eq "Admin can see Alpha CodeSystem" "1" "$count"

count=$(fhir_search_count "$AUTHORING_URL" "CodeSystem?url=http://pathology-beta.example.com/CodeSystem/pathology-codes" "$ADMIN_TOKEN")
assert_eq "Admin can see Beta CodeSystem" "1" "$count"

count=$(fhir_search_count "$AUTHORING_URL" "CodeSystem?url=http://pathology-gamma.example.com/CodeSystem/pathology-codes" "$ADMIN_TOKEN")
assert_eq "Admin can see Gamma CodeSystem" "1" "$count"

# ---- Total CodeSystem counts ----

alpha_total=$(fhir_search_count "$AUTHORING_URL" "CodeSystem" "$ALPHA_AUTHOR_TOKEN")
assert_eq "Alpha author sees exactly 1 CodeSystem total" "1" "$alpha_total"

beta_total=$(fhir_search_count "$AUTHORING_URL" "CodeSystem" "$BETA_AUTHOR_TOKEN")
assert_eq "Beta author sees exactly 1 CodeSystem total" "1" "$beta_total"

admin_total=$(fhir_search_count "$AUTHORING_URL" "CodeSystem" "$ADMIN_TOKEN")
assert_gt "Admin sees 3+ CodeSystems total" "$admin_total" 2

print_summary
