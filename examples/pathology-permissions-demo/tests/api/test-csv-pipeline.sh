#!/usr/bin/env bash
# =============================================================================
# Test: CSV-to-FHIR Pipeline
# =============================================================================
# Verifies that the CSV transformation script correctly generates FHIR
# resources with proper security labels and that they can be loaded.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/helpers.sh"

COMMON_DIR="$(cd "${SCRIPT_DIR}/../../common" && pwd)"

suite "CSV-to-FHIR Pipeline"

ADMIN_TOKEN=$(get_token "admin")
ALPHA_AUTHOR_TOKEN=$(get_token "alpha-author")

# ---- CSV files exist and are valid ----

assert "gamma-codes.csv exists" "$(test -f "${COMMON_DIR}/csv-data/gamma-codes.csv"; echo $?)"
assert "gamma-mappings.csv exists" "$(test -f "${COMMON_DIR}/csv-data/gamma-mappings.csv"; echo $?)"

codes_lines=$(wc -l < "${COMMON_DIR}/csv-data/gamma-codes.csv" | tr -d ' ')
assert_gt "gamma-codes.csv has data rows" "$codes_lines" 1

mappings_lines=$(wc -l < "${COMMON_DIR}/csv-data/gamma-mappings.csv" | tr -d ' ')
assert_gt "gamma-mappings.csv has data rows" "$mappings_lines" 1

# ---- CSV transform produces valid FHIR resources ----

TEST_OUTPUT="/tmp/pathology-demo-csv-test-$$"
mkdir -p "$TEST_OUTPUT"
trap "rm -rf $TEST_OUTPUT" EXIT

transform_exit=0
python3 "${COMMON_DIR}/scripts/csv-transform.py" \
    --codes "${COMMON_DIR}/csv-data/gamma-codes.csv" \
    --mappings "${COMMON_DIR}/csv-data/gamma-mappings.csv" \
    --output-dir "$TEST_OUTPUT" \
    --security-label "TESTLABEL" \
    --codesystem-url "http://test.example.com/CodeSystem/test" \
    --codesystem-id "test-cs" \
    --conceptmap-url "http://test.example.com/ConceptMap/test" \
    --conceptmap-id "test-cm" \
    --target-valueset "http://example.org/ValueSet/national-pathology-refset" \
    --publisher "Test Publisher" \
    --version "9.9.9" > /dev/null 2>&1 || transform_exit=$?

assert "Transform script exits successfully" "$transform_exit"

# Verify CodeSystem
assert "CodeSystem JSON file generated" "$(test -f "${TEST_OUTPUT}/test-cs.json"; echo $?)"

if [ -f "${TEST_OUTPUT}/test-cs.json" ]; then
    cs_rt=$(jq -r '.resourceType' "${TEST_OUTPUT}/test-cs.json" 2>/dev/null)
    assert_eq "Generated CodeSystem has correct resourceType" "CodeSystem" "$cs_rt"

    cs_url=$(jq -r '.url' "${TEST_OUTPUT}/test-cs.json" 2>/dev/null)
    assert_eq "Generated CodeSystem has correct URL" "http://test.example.com/CodeSystem/test" "$cs_url"

    cs_version=$(jq -r '.version' "${TEST_OUTPUT}/test-cs.json" 2>/dev/null)
    assert_eq "Generated CodeSystem has correct version" "9.9.9" "$cs_version"

    cs_count=$(jq '.concept | length' "${TEST_OUTPUT}/test-cs.json" 2>/dev/null)
    assert_gt "Generated CodeSystem has concepts" "$cs_count" 10

    has_read_label=$(jq 'any(.meta.security[]; .code == "TESTLABEL.read")' "${TEST_OUTPUT}/test-cs.json" 2>/dev/null)
    assert_eq "Generated CodeSystem has TESTLABEL.read label" "true" "$has_read_label"

    has_write_label=$(jq 'any(.meta.security[]; .code == "TESTLABEL.write")' "${TEST_OUTPUT}/test-cs.json" 2>/dev/null)
    assert_eq "Generated CodeSystem has TESTLABEL.write label" "true" "$has_write_label"
fi

# Verify ConceptMap
assert "ConceptMap JSON file generated" "$(test -f "${TEST_OUTPUT}/test-cm.json"; echo $?)"

if [ -f "${TEST_OUTPUT}/test-cm.json" ]; then
    cm_rt=$(jq -r '.resourceType' "${TEST_OUTPUT}/test-cm.json" 2>/dev/null)
    assert_eq "Generated ConceptMap has correct resourceType" "ConceptMap" "$cm_rt"

    cm_url=$(jq -r '.url' "${TEST_OUTPUT}/test-cm.json" 2>/dev/null)
    assert_eq "Generated ConceptMap has correct URL" "http://test.example.com/ConceptMap/test" "$cm_url"

    element_count=$(jq '.group[0].element | length' "${TEST_OUTPUT}/test-cm.json" 2>/dev/null)
    assert_gt "Generated ConceptMap has mapping elements" "$element_count" 10

    target_vs=$(jq -r '.targetUri' "${TEST_OUTPUT}/test-cm.json" 2>/dev/null)
    assert_eq "Generated ConceptMap targets national valueset" "http://example.org/ValueSet/national-pathology-refset" "$target_vs"
fi

# ---- Gamma resources are loaded in authoring server ----

count=$(fhir_search_count "$AUTHORING_URL" "CodeSystem?url=http://pathology-gamma.example.com/CodeSystem/pathology-codes" "$ADMIN_TOKEN")
assert_eq "Gamma CodeSystem is loaded in authoring server" "1" "$count"

count=$(fhir_search_count "$AUTHORING_URL" "ConceptMap?url=http://pathology-gamma.example.com/ConceptMap/pathology-to-national" "$ADMIN_TOKEN")
assert_eq "Gamma ConceptMap is loaded in authoring server" "1" "$count"

# ---- Gamma resources have correct security labels ----

gamma_cs=$(fhir_get "$AUTHORING_URL" "CodeSystem?url=http://pathology-gamma.example.com/CodeSystem/pathology-codes" "$ADMIN_TOKEN")
if [ -n "$gamma_cs" ] && [ "$gamma_cs" != "null" ]; then
    has_gamma_read=$(echo "$gamma_cs" | jq 'any(.entry[0].resource.meta.security[]; .code == "GAMMA.read")' 2>/dev/null || echo "false")
    assert_eq "Gamma CodeSystem has GAMMA.read label" "true" "$has_gamma_read"

    has_gamma_write=$(echo "$gamma_cs" | jq 'any(.entry[0].resource.meta.security[]; .code == "GAMMA.write")' 2>/dev/null || echo "false")
    assert_eq "Gamma CodeSystem has GAMMA.write label" "true" "$has_gamma_write"
fi

# ---- Gamma resources are NOT visible to Alpha/Beta ----

count=$(fhir_search_count "$AUTHORING_URL" "CodeSystem?url=http://pathology-gamma.example.com/CodeSystem/pathology-codes" "$ALPHA_AUTHOR_TOKEN")
assert_eq "Alpha author CANNOT see Gamma CodeSystem" "0" "$count"

BETA_AUTHOR_TOKEN=$(get_token "beta-author")
count=$(fhir_search_count "$AUTHORING_URL" "CodeSystem?url=http://pathology-gamma.example.com/CodeSystem/pathology-codes" "$BETA_AUTHOR_TOKEN")
assert_eq "Beta author CANNOT see Gamma CodeSystem" "0" "$count"

count=$(fhir_search_count "$AUTHORING_URL" "ConceptMap?url=http://pathology-gamma.example.com/ConceptMap/pathology-to-national" "$ALPHA_AUTHOR_TOKEN")
assert_eq "Alpha author CANNOT see Gamma ConceptMap" "0" "$count"

count=$(fhir_search_count "$AUTHORING_URL" "ConceptMap?url=http://pathology-gamma.example.com/ConceptMap/pathology-to-national" "$BETA_AUTHOR_TOKEN")
assert_eq "Beta author CANNOT see Gamma ConceptMap" "0" "$count"

print_summary
