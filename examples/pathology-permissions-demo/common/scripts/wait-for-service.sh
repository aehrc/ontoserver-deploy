#!/usr/bin/env bash
# Wait for an HTTP service to become ready.
#
# Usage: wait-for-service.sh <url> [timeout_seconds] [service_name]
#
# Examples:
#   wait-for-service.sh http://localhost:9090/auth/health/ready 120 "Ontocloak"
#   wait-for-service.sh http://localhost:9081/fhir/metadata 180 "Authoring Ontoserver"

set -euo pipefail

URL="${1:?Usage: wait-for-service.sh <url> [timeout] [name]}"
TIMEOUT="${2:-120}"
NAME="${3:-service}"

echo "Waiting for ${NAME} at ${URL} (timeout: ${TIMEOUT}s)..."

elapsed=0
interval=3

while [ "$elapsed" -lt "$TIMEOUT" ]; do
    if curl -sf -o /dev/null --max-time 5 "$URL" 2>/dev/null; then
        echo "${NAME} is ready! (took ${elapsed}s)"
        exit 0
    fi
    sleep "$interval"
    elapsed=$((elapsed + interval))
    # Print a dot every 15 seconds to show progress
    if [ $((elapsed % 15)) -eq 0 ]; then
        echo "  ...still waiting (${elapsed}s elapsed)"
    fi
done

echo "ERROR: ${NAME} did not become ready within ${TIMEOUT}s"
exit 1
