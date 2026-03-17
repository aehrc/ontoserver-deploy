#!/usr/bin/env bash
# =============================================================================
# API Test Runner
# =============================================================================
# Runs all API-level tests for the pathology permissions demo.
#
# Usage:
#   ./tests/api/run-api-tests.sh [simple|atomio]
#
# The variant argument determines which tests to run:
#   simple  - Tests for the simple variant (default)
#   atomio  - Tests for the Atomio variant (includes Atomio-specific tests)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VARIANT="${1:-simple}"

echo ""
echo "============================================================"
echo "  Pathology Permissions Demo - API Tests (${VARIANT})"
echo "============================================================"
echo ""

# Configure URLs based on variant
if [ "$VARIANT" = "atomio" ]; then
    export PRODUCTION_URL="${PRODUCTION_URL:-https://localhost:9082}"
    export ATOMIO_URL="${ATOMIO_URL:-https://localhost:9083}"
    export UAT_URL="${UAT_URL:-https://localhost:9084}"
fi

# Check prerequisites
source "${SCRIPT_DIR}/helpers.sh"

echo "Checking service availability..."
check_service "${ONTOCLOAK_URL}/auth/realms/master" "Ontocloak" || exit 1
check_service "${AUTHORING_URL}/fhir/metadata" "Authoring Ontoserver" || exit 1
check_service "${PRODUCTION_URL}/fhir/metadata" "Production Ontoserver" || exit 1
if [ "$VARIANT" = "atomio" ]; then
    check_service "${ATOMIO_URL}/actuator/health" "Atomio" || exit 1
fi
echo ""

# Track overall results
TOTAL_PASSED=0
TOTAL_FAILED=0
TOTAL_SKIPPED=0
EXIT_CODE=0

run_test() {
    local test_file="$1"
    local test_name
    test_name=$(basename "$test_file" .sh)

    echo ""
    local result=0
    bash "$test_file" || result=$?

    if [ $result -ne 0 ]; then
        EXIT_CODE=1
    fi
}

# Run common tests
run_test "${SCRIPT_DIR}/test-resource-isolation.sh"
run_test "${SCRIPT_DIR}/test-role-access.sh"
run_test "${SCRIPT_DIR}/test-national-valueset.sh"
run_test "${SCRIPT_DIR}/test-syndication.sh"
run_test "${SCRIPT_DIR}/test-csv-pipeline.sh"

# Run variant-specific tests
if [ "$VARIANT" = "atomio" ]; then
    run_test "${SCRIPT_DIR}/test-atomio-workflow.sh"
    run_test "${SCRIPT_DIR}/test-atomio-flow.sh"
else
    run_test "${SCRIPT_DIR}/test-simple-flow.sh"
fi

echo ""
echo "============================================================"
echo "  API Tests Complete"
echo "============================================================"
echo ""

exit $EXIT_CODE
