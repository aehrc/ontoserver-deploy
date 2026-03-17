#!/usr/bin/env bash
# =============================================================================
# Create a Release Candidate in Atomio
# =============================================================================
#
# Clones the authoring Ontoserver's syndication feed into a new Atomio feed,
# creating a snapshot of the current authoring content as a release candidate.
#
# Usage:
#   ./scripts/create-release-candidate.sh <release-name> [--promote-to uat|production]
#
# Examples:
#   ./scripts/create-release-candidate.sh release-2-0
#   ./scripts/create-release-candidate.sh release-2-0 --promote-to uat
#   ./scripts/create-release-candidate.sh release-2-0 --promote-to production

set -euo pipefail

ATOMIO_URL="http://localhost:9083"
AUTHORING_SYND_URL="http://authoring-ontoserver:8080/synd/syndication.xml"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[RC]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# Parse arguments
RELEASE_NAME="${1:?Usage: create-release-candidate.sh <release-name> [--promote-to uat|production]}"
PROMOTE_TO=""

shift
while [[ $# -gt 0 ]]; do
    case "$1" in
        --promote-to)
            PROMOTE_TO="${2:?--promote-to requires a value (uat or production)}"
            shift 2
            ;;
        *)
            error "Unknown argument: $1"
            ;;
    esac
done

# Create the release candidate by cloning the authoring feed
log "Cloning authoring syndication feed into '${RELEASE_NAME}'..."

RESPONSE=$(curl -sf -w "\n%{http_code}" -X POST \
    "${ATOMIO_URL}/feed/\$clone?name=${RELEASE_NAME}&url=${AUTHORING_SYND_URL}" \
    -H "Content-Type: application/json" 2>&1) || true

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)

if [ "$HTTP_CODE" = "201" ] || [ "$HTTP_CODE" = "200" ]; then
    success "Release candidate '${RELEASE_NAME}' created"
elif [ "$HTTP_CODE" = "409" ]; then
    error "Feed '${RELEASE_NAME}' already exists. Choose a different name."
else
    error "Clone failed with HTTP ${HTTP_CODE}"
fi

# Show the feed contents
log "Release candidate feed:"
echo ""
curl -sf "${ATOMIO_URL}/feed/${RELEASE_NAME}" | jq '{name: .name, title: .title, entries: (.entries // [] | length)}' 2>/dev/null || true
echo ""

# Show feed syndication URL
log "Syndication URL: ${ATOMIO_URL}/feed/${RELEASE_NAME}/syndication.xml"

# Optionally promote to an environment
if [ -n "$PROMOTE_TO" ]; then
    log "Promoting '${RELEASE_NAME}' to ${PROMOTE_TO}..."

    # Check if alias exists
    EXISTING=$(curl -sf "${ATOMIO_URL}/alias" | jq -r ".[] | select(.name==\"${PROMOTE_TO}\") | .name" 2>/dev/null) || true

    if [ -n "$EXISTING" ]; then
        # Update existing alias
        HTTP_CODE=$(curl -sf -o /dev/null -w "%{http_code}" -X PUT \
            "${ATOMIO_URL}/alias/${PROMOTE_TO}" \
            -H "Content-Type: application/json" \
            -d "{\"name\": \"${PROMOTE_TO}\", \"feedName\": \"${RELEASE_NAME}\"}" 2>&1) || true
    else
        # Create new alias
        HTTP_CODE=$(curl -sf -o /dev/null -w "%{http_code}" -X POST \
            "${ATOMIO_URL}/alias" \
            -H "Content-Type: application/json" \
            -d "{\"name\": \"${PROMOTE_TO}\", \"feedName\": \"${RELEASE_NAME}\"}" 2>&1) || true
    fi

    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
        success "Alias '${PROMOTE_TO}' now points to '${RELEASE_NAME}'"
        echo ""
        log "The ${PROMOTE_TO} Ontoserver will pick up changes on its next poll cycle."
        log "Syndication URL: ${ATOMIO_URL}/alias/${PROMOTE_TO}/syndication.xml"
    else
        error "Failed to update alias (HTTP ${HTTP_CODE})"
    fi
fi

echo ""
log "Current aliases:"
curl -sf "${ATOMIO_URL}/alias" | jq '.[] | {alias: .name, feed: .feedName}' 2>/dev/null || echo "  (could not fetch aliases)"
echo ""
