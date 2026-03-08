#!/usr/bin/env bash
#
# helm_acr_release.sh - Package and push Helm charts to Azure Container Registry
#
# This script builds Helm chart dependencies, authenticates with Azure and ACR,
# then packages and pushes the chart to the specified registry.
#

set -euo pipefail

# Enable debug mode (set to false to disable, or use --debug flag)
DEBUG="${DEBUG:-true}"

log_debug() {
    if [[ "$DEBUG" == true ]]; then
        echo -e "\033[0;36m[DEBUG]\033[0m $(date '+%H:%M:%S') $*" >&2
    fi
}

log_debug "=== Script started ==="
log_debug "Script path: $0"
log_debug "Arguments: $*"
log_debug "Working directory: $(pwd)"
log_debug "User: $(whoami)"
log_debug "Shell: $SHELL"

# Default values
SCRIPT_NAME="$(basename "$0")"
ACR_NAME=""
# Capture environment variables before they get overwritten
ACR_USERNAME="${ACR_USERNAME:-}"
ACR_PASSWORD="${ACR_PASSWORD:-}"
CHART_PATH=""
SKIP_AZ_LOGIN=false
REGISTRY_PATH="helm"
NO_PUSH=false

log_debug "=== Initial environment variables ==="
log_debug "ACR_USERNAME set: $([[ -n \"$ACR_USERNAME\" ]] && echo 'yes' || echo 'no')"
log_debug "ACR_PASSWORD set: $([[ -n \"$ACR_PASSWORD\" ]] && echo 'yes' || echo 'no')"

# Colors for output (disabled if not a terminal)
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    NC=''
fi

usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [OPTIONS] --acr-name <name> --chart <path>

Package and push a Helm chart to Azure Container Registry.

Required:
    -a, --acr-name <name>       Azure Container Registry name (without .azurecr.io)
    -c, --chart <path>          Path to the Helm chart directory

Authentication (one of the following):
    -u, --username <username>   ACR username (requires --password)
    -p, --password <password>   ACR password or token

    If username/password are not provided, the script will attempt to use
    Azure CLI authentication (az acr login).

Optional:
    -r, --registry-path <path>  Registry path prefix (default: helm)
    -s, --skip-az-login         Skip Azure CLI login (use if already authenticated)
    --no-push                   Build and package only, skip pushing to registry
    -d, --debug                 Enable debug output (default: enabled)
    --no-debug                  Disable debug output
    -h, --help                  Show this help message and exit

Environment Variables:
    ACR_USERNAME                ACR username (alternative to --username)
    ACR_PASSWORD                ACR password (alternative to --password)
    DEBUG                       Set to 'true' to enable debug output (default: true)

Examples:
    # Using token authentication
    ${SCRIPT_NAME} --acr-name myregistry --chart ./mychart --username user --password \$TOKEN

    # Using Azure CLI authentication
    ${SCRIPT_NAME} --acr-name myregistry --chart ./mychart --skip-az-login

    # Using environment variables
    export ACR_USERNAME=user
    export ACR_PASSWORD=\$TOKEN
    ${SCRIPT_NAME} --acr-name myregistry --chart ./mychart

Notes:
    To create an ACR token for Helm pushes:
    az acr token create -n <token-name> \\
        -r <acr-name> \\
        --scope-map _repositories_admin \\
        --only-show-errors \\
        --query "credentials.passwords[0].value" -o tsv
EOF
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

die() {
    log_debug "!!! FATAL ERROR !!!"
    log_debug "Error message: $*"
    log_debug "Call stack:"
    local frame=0
    while caller $frame >&2; do
        ((frame++))
    done
    log_error "$*"
    exit 1
}

# Parse command line arguments
parse_args() {
    log_debug "=== Parsing arguments ==="
    log_debug "Number of arguments: $#"
    while [[ $# -gt 0 ]]; do
        log_debug "Processing argument: $1"
        case "$1" in
            -a|--acr-name)
                [[ -z "${2:-}" ]] && die "Option $1 requires an argument"
                ACR_NAME="$2"
                log_debug "  Set ACR_NAME=$ACR_NAME"
                shift 2
                ;;
            -c|--chart)
                [[ -z "${2:-}" ]] && die "Option $1 requires an argument"
                CHART_PATH="$2"
                log_debug "  Set CHART_PATH=$CHART_PATH"
                shift 2
                ;;
            -u|--username)
                [[ -z "${2:-}" ]] && die "Option $1 requires an argument"
                ACR_USERNAME="$2"
                log_debug "  Set ACR_USERNAME=$ACR_USERNAME"
                shift 2
                ;;
            -p|--password)
                [[ -z "${2:-}" ]] && die "Option $1 requires an argument"
                ACR_PASSWORD="$2"
                log_debug "  Set ACR_PASSWORD=[REDACTED, length=${#ACR_PASSWORD}]"
                shift 2
                ;;
            -r|--registry-path)
                [[ -z "${2:-}" ]] && die "Option $1 requires an argument"
                REGISTRY_PATH="$2"
                log_debug "  Set REGISTRY_PATH=$REGISTRY_PATH"
                shift 2
                ;;
            -s|--skip-az-login)
                SKIP_AZ_LOGIN=true
                log_debug "  Set SKIP_AZ_LOGIN=true"
                shift
                ;;
            --no-push)
                NO_PUSH=true
                log_debug "  Set NO_PUSH=true"
                shift
                ;;
            -d|--debug)
                DEBUG=true
                log_debug "  Debug mode enabled via flag"
                shift
                ;;
            --no-debug)
                DEBUG=false
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -*)
                die "Unknown option: $1. Use --help for usage information."
                ;;
            *)
                # Positional argument - treat as chart path if not set
                if [[ -z "$CHART_PATH" ]]; then
                    log_debug "Setting CHART_PATH from positional argument: $1"
                    CHART_PATH="$1"
                else
                    die "Unexpected argument: $1. Use --help for usage information."
                fi
                shift
                ;;
        esac
    done
    log_debug "=== Parsed values ==="
    log_debug "ACR_NAME: $ACR_NAME"
    log_debug "CHART_PATH: $CHART_PATH"
    log_debug "REGISTRY_PATH: $REGISTRY_PATH"
    log_debug "SKIP_AZ_LOGIN: $SKIP_AZ_LOGIN"
    log_debug "NO_PUSH: $NO_PUSH"
    log_debug "ACR_USERNAME set: $([[ -n \"$ACR_USERNAME\" ]] && echo 'yes' || echo 'no')"
    log_debug "ACR_PASSWORD set: $([[ -n \"$ACR_PASSWORD\" ]] && echo 'yes' || echo 'no')"
}

validate_args() {
    log_debug "=== Validating arguments ==="

    # Check required arguments
    log_debug "Checking if ACR_NAME is set..."
    [[ -z "$ACR_NAME" ]] && die "ACR name is required. Use --acr-name or -a."
    log_debug "ACR_NAME is set: $ACR_NAME"

    log_debug "Checking if CHART_PATH is set..."
    [[ -z "$CHART_PATH" ]] && die "Chart path is required. Use --chart or -c."
    log_debug "CHART_PATH is set: $CHART_PATH"

    # Validate chart path exists
    log_debug "Checking if chart directory exists: $CHART_PATH"
    [[ ! -d "$CHART_PATH" ]] && die "Chart directory not found: $CHART_PATH"
    log_debug "Chart directory exists"

    log_debug "Checking for Chart.yaml: $CHART_PATH/Chart.yaml"
    [[ ! -f "$CHART_PATH/Chart.yaml" ]] && die "Not a valid Helm chart: $CHART_PATH/Chart.yaml not found"
    log_debug "Chart.yaml found"

    log_debug "=== Arguments validated successfully ==="
}

check_dependencies() {
    log_debug "=== Checking dependencies ==="
    local missing=()

    log_debug "Checking for helm..."
    if command -v helm &>/dev/null; then
        log_debug "helm found: $(command -v helm)"
        log_debug "helm version: $(helm version --short 2>/dev/null || echo 'unable to get version')"
    else
        log_debug "helm NOT found"
        missing+=("helm")
    fi

    log_debug "Checking for az (Azure CLI)..."
    if command -v az &>/dev/null; then
        log_debug "az found: $(command -v az)"
        log_debug "az version: $(az version --query '\"azure-cli\"' -o tsv 2>/dev/null || echo 'unable to get version')"
    else
        log_debug "az NOT found"
        missing+=("az (Azure CLI)")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        die "Missing required dependencies: ${missing[*]}"
    fi

    log_debug "=== All dependencies found ==="
}

azure_login() {
    log_debug "=== Azure login stage ==="
    # Skip Azure login if --no-push specified
    if [[ "$NO_PUSH" == true ]]; then
        log_debug "NO_PUSH is true, skipping Azure login"
        log_info "Skipping Azure CLI login (--no-push specified)"
        return 0
    fi

    # Skip Azure login if using token authentication
    log_debug "Checking if token authentication is configured..."
    if [[ -n "$ACR_USERNAME" && -n "$ACR_PASSWORD" ]]; then
      log_debug "Token authentication detected (ACR_USERNAME and ACR_PASSWORD are set)"
      log_info "Using token authentication, skipping Azure CLI login"
      return 0
    fi
    log_debug "Token authentication not configured"

    log_debug "Checking SKIP_AZ_LOGIN flag: $SKIP_AZ_LOGIN"
    if [[ "$SKIP_AZ_LOGIN" == true ]]; then
        log_debug "SKIP_AZ_LOGIN is true, skipping Azure login"
        log_info "Skipping Azure CLI login (--skip-az-login specified)"
        return 0
    fi

    log_debug "Attempting Azure CLI login..."
    log_info "Logging into Azure..."
    log_debug "Running: az login --scope https://management.core.windows.net//.default"
    if ! az login --scope https://management.core.windows.net//.default; then
        log_debug "Azure login command failed with exit code: $?"
        die "Azure login failed"
    fi
    log_debug "Azure login successful"
}

acr_login() {
    log_debug "=== ACR login stage ==="
    # Skip ACR login if --no-push specified
    if [[ "$NO_PUSH" == true ]]; then
        log_debug "NO_PUSH is true, skipping ACR login"
        log_info "Skipping ACR login (--no-push specified)"
        return 0
    fi

    local registry="${ACR_NAME}.azurecr.io"
    log_debug "Registry URL: $registry"

    if [[ -n "$ACR_USERNAME" && -n "$ACR_PASSWORD" ]]; then
        log_debug "Using token authentication for ACR"
        log_debug "ACR_USERNAME: $ACR_USERNAME"
        log_debug "ACR_PASSWORD length: ${#ACR_PASSWORD} characters"
        log_info "Logging into ACR using token authentication..."
        log_debug "Running: helm registry login $registry --username $ACR_USERNAME --password [REDACTED]"
        if ! helm registry login "$registry" \
            --username "$ACR_USERNAME" \
            --password "$ACR_PASSWORD"; then
            log_debug "helm registry login failed with exit code: $?"
            die "ACR registry login failed"
        fi
        log_debug "helm registry login successful"
    else
        log_debug "Using Azure CLI authentication for ACR"
        log_info "Logging into ACR using Azure CLI authentication..."
        log_debug "Running: az acr login --name $ACR_NAME"
        if ! az acr login --name "$ACR_NAME"; then
            log_debug "az acr login failed with exit code: $?"
            die "ACR login via Azure CLI failed. Provide --username and --password for token auth."
        fi
        log_debug "az acr login successful"
    fi
    log_debug "=== ACR login completed ==="
}

build_and_push() {
    log_debug "=== Build and push stage ==="
    local registry="${ACR_NAME}.azurecr.io"
    local oci_url="oci://${registry}/${REGISTRY_PATH}"
    log_debug "Registry: $registry"
    log_debug "OCI URL: $oci_url"
    log_debug "Chart path: $CHART_PATH"

    # Build dependencies
    log_debug "--- Building dependencies ---"
    log_info "Building Helm chart dependencies..."
    log_debug "Checking for Chart.lock or requirements.lock..."
    if [[ -f "$CHART_PATH/Chart.lock" ]]; then
        log_debug "Chart.lock found"
    else
        log_debug "Chart.lock not found"
    fi
    if [[ -d "$CHART_PATH/charts" ]]; then
        log_debug "charts/ directory exists"
    else
        log_debug "charts/ directory does not exist"
    fi
    log_debug "Running: helm dependency update $CHART_PATH"
    if ! helm dependency update "$CHART_PATH"; then
        log_debug "helm dependency update failed with exit code: $?"
        die "Failed to update Helm dependencies"
    fi
    log_debug "helm dependency update successful"

    # Package chart
    log_debug "--- Packaging chart ---"
    log_info "Packaging Helm chart..."
    log_debug "Running: helm package $CHART_PATH"
    local package_output
    if ! package_output=$(helm package "$CHART_PATH" 2>&1); then
        log_debug "helm package failed with exit code: $?"
        log_debug "helm package output: $package_output"
        die "Failed to package Helm chart"
    fi
    log_debug "helm package output: $package_output"

    # Extract package filename from output
    local chart_package
    chart_package=$(echo "$package_output" | sed 's|.*saved it to: ||' | tr -d '[:space:]')
    log_debug "Extracted package filename: $chart_package"

    log_debug "Checking if package file exists..."
    if [[ ! -f "$chart_package" ]]; then
        log_debug "Package file NOT found at: $chart_package"
        log_debug "Current directory contents:"
        ls -la "$(pwd)" >&2 || true
        die "Package file not found: $chart_package"
    fi
    log_debug "Package file exists: $chart_package"
    log_debug "Package file size: $(stat -f%z "$chart_package" 2>/dev/null || stat -c%s "$chart_package" 2>/dev/null || echo 'unknown') bytes"

    # Push to registry (unless --no-push specified)
    if [[ "$NO_PUSH" == true ]]; then
        log_debug "--- Skipping push (--no-push specified) ---"
        log_info "Skipping push to registry (--no-push specified)"
        log_info "Package created: ${chart_package}"
    else
        log_debug "--- Pushing to registry ---"
        log_info "Pushing ${chart_package} to ${oci_url}"
        log_debug "Running: helm push $chart_package $oci_url"
        if ! helm push "$chart_package" "$oci_url"; then
            log_debug "helm push failed with exit code: $?"
            die "Failed to push Helm chart to registry"
        fi
        log_debug "helm push successful"

        log_info "Successfully pushed chart to ${oci_url}"

        # Cleanup packaged chart
        log_debug "Cleaning up package file: $chart_package"
        rm -f "$chart_package"
    fi
    log_debug "=== Build and push completed ==="
}

main() {
    log_debug "=== Main function started ==="

    log_debug ">>> Stage 1: Parsing arguments"
    parse_args "$@"

    log_debug ">>> Stage 2: Validating arguments"
    validate_args

    log_debug ">>> Stage 3: Checking dependencies"
    check_dependencies

    log_debug ">>> Stage 4: Azure login"
    azure_login

    log_debug ">>> Stage 5: ACR login"
    acr_login

    log_debug ">>> Stage 6: Build and push"
    build_and_push

    log_debug "=== All stages completed successfully ==="
    log_info "Done!"
}

log_debug "Calling main function..."
main "$@"
log_debug "Script finished"
