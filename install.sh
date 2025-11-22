#!/usr/bin/env bash

#
# Interlinx Controller Bootstrap Installer
#
# Downloads and extracts the Interlinx Controller standalone release
# from the private GitHub repository.
#
# Usage:
#   ./install.sh [options]
#
# Options:
#   --token <pat>      GitHub Personal Access Token for authentication
#   --version <ver>    Specific version to install (default: latest)
#   --help             Display this help message
#

set -e
set -o pipefail

# Configuration
GITHUB_REPO="interlinx-io/interlinx-controller"
INSTALL_DIR="/opt"
ARCH="linux-x64"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Variables
GITHUB_TOKEN=""
VERSION=""
QUIET=false

# Functions
error() {
    echo -e "${RED}Error: $1${NC}" >&2
    exit 1
}

warn() {
    echo -e "${YELLOW}Warning: $1${NC}" >&2
}

info() {
    echo -e "${GREEN}$1${NC}"
}

usage() {
    cat << EOF
Interlinx Controller Bootstrap Installer

Downloads and extracts the Interlinx Controller from the private GitHub repository.

USAGE:
    ./install.sh [OPTIONS]

OPTIONS:
    --token <token>     GitHub Personal Access Token (PAT) for authentication
                        If not provided, will prompt interactively

    --version <ver>     Specific version to install (e.g., v1.4.0)
                        Default: latest release

    --help              Display this help message and exit

EXAMPLES:
    # Interactive mode (prompts for PAT)
    sudo ./install.sh

    # Non-interactive with token
    sudo ./install.sh --token ghp_xxxxxxxxxxxx

    # Specific version
    sudo ./install.sh --version v1.4.0 --token ghp_xxxxxxxxxxxx

    # Download and run in one command
    curl -fsSL https://raw.githubusercontent.com/interlinx-io/interlinx-quickstart/main/install.sh | sudo bash

PREREQUISITES:
    - Root or sudo access
    - Internet connectivity
    - GitHub Personal Access Token with 'repo' scope

GITHUB PAT REQUIREMENTS:
    Your GitHub PAT must have access to private repositories:
    - Scope: 'repo' (Full control of private repositories)
    - Or minimum: 'repo:private_repo'

    Create a PAT at: https://github.com/settings/tokens

INSTALLATION:
    The controller will be extracted to:
        ${INSTALL_DIR}/interlinx-controller-vX.X.X/

    After extraction, follow the displayed next steps to complete installation.

EOF
    exit 0
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root or with sudo"
    fi
}

check_dependencies() {
    local missing_deps=()

    for cmd in curl tar sha256sum; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        error "Missing required dependencies: ${missing_deps[*]}"
    fi
}

prompt_for_token() {
    if [[ -z "$GITHUB_TOKEN" ]]; then
        echo ""
        echo "GitHub Personal Access Token (PAT) required to download from private repository."
        echo "Your PAT must have 'repo' or 'repo:private_repo' scope."
        echo ""
        echo "Create a PAT at: https://github.com/settings/tokens"
        echo ""
        read -s -p "Enter your GitHub PAT: " GITHUB_TOKEN
        echo ""

        if [[ -z "$GITHUB_TOKEN" ]]; then
            error "GitHub token is required"
        fi
    fi
}

get_latest_version() {
    info "Fetching latest release version..."

    local response
    response=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
        "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" 2>&1)

    local http_code=$(echo "$response" | grep -o '"message":' | wc -l)

    if echo "$response" | grep -q '"message": "Bad credentials"'; then
        error "Invalid GitHub token. Please check your Personal Access Token."
    elif echo "$response" | grep -q '"message": "Not Found"'; then
        error "Repository not found or token lacks access. Ensure your PAT has 'repo' scope."
    elif echo "$response" | grep -q '"tag_name"'; then
        VERSION=$(echo "$response" | grep '"tag_name":' | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')
        info "Latest version: $VERSION"
    else
        error "Failed to fetch latest release. Response: $response"
    fi
}

verify_version_exists() {
    info "Verifying version $VERSION exists..."

    local url="https://api.github.com/repos/${GITHUB_REPO}/releases/tags/${VERSION}"
    local response
    response=$(curl -s -H "Authorization: token $GITHUB_TOKEN" "$url" 2>&1)

    if echo "$response" | grep -q '"message": "Not Found"'; then
        error "Version $VERSION not found in repository"
    fi
}

download_file() {
    local url=$1
    local output=$2
    local description=$3

    info "Downloading $description..."

    local http_code
    http_code=$(curl -L -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/octet-stream" \
        -w "%{http_code}" \
        -o "$output" \
        "$url" 2>&1 | tail -n1)

    if [[ "$http_code" != "200" ]]; then
        if [[ "$http_code" == "401" || "$http_code" == "403" ]]; then
            error "Authentication failed (HTTP $http_code). Please check your GitHub token."
        elif [[ "$http_code" == "404" ]]; then
            error "File not found (HTTP $http_code). URL: $url"
        else
            error "Download failed with HTTP code $http_code"
        fi
    fi

    if [[ ! -f "$output" ]] || [[ ! -s "$output" ]]; then
        error "Downloaded file is missing or empty: $output"
    fi
}

verify_checksum() {
    local tarball=$1
    local checksum_file=$2

    info "Verifying SHA256 checksum..."

    if [[ ! -f "$checksum_file" ]]; then
        error "Checksum file not found: $checksum_file"
    fi

    # Read expected checksum
    local expected_checksum
    expected_checksum=$(cat "$checksum_file" | awk '{print $1}')

    if [[ -z "$expected_checksum" ]]; then
        error "Could not read checksum from file"
    fi

    # Calculate actual checksum
    local actual_checksum
    actual_checksum=$(sha256sum "$tarball" | awk '{print $1}')

    if [[ "$expected_checksum" != "$actual_checksum" ]]; then
        error "Checksum verification failed!\nExpected: $expected_checksum\nActual:   $actual_checksum"
    fi

    info "Checksum verified successfully"
}

extract_tarball() {
    local tarball=$1

    info "Extracting to ${INSTALL_DIR}..."

    if ! tar -xzf "$tarball" -C "$INSTALL_DIR"; then
        error "Failed to extract tarball"
    fi

    info "Extraction complete"
}

show_next_steps() {
    local installed_dir=$1

    cat << EOF

============================================
Interlinx Controller downloaded successfully!
============================================

Location: ${installed_dir}

Next Steps:
1. Navigate to the installation directory:
   cd ${installed_dir}

2. Test Kubernetes access (recommended):
   sudo ./install.sh --test-access

3. Install as systemd service:
   sudo ./install.sh

4. (Optional) Deploy bundled packages:
   cd bundled/process-exporter && sudo ./install.sh
   cd bundled/teleport && sudo ./install.sh --device <name>

For detailed documentation, see:
  ${installed_dir}/README.md

============================================

EOF
}

cleanup() {
    if [[ -n "$TEMP_DIR" ]] && [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi

    # Unset token from environment
    unset GITHUB_TOKEN
}

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --token)
                GITHUB_TOKEN="$2"
                shift 2
                ;;
            --version)
                VERSION="$2"
                shift 2
                ;;
            --help)
                usage
                ;;
            *)
                error "Unknown option: $1\nUse --help for usage information"
                ;;
        esac
    done

    # Setup cleanup trap
    trap cleanup EXIT

    # Pre-flight checks
    check_root
    check_dependencies

    # Get authentication token
    prompt_for_token

    # Determine version
    if [[ -z "$VERSION" ]]; then
        get_latest_version
    else
        verify_version_exists
    fi

    # Construct URLs
    local filename="interlinx-controller-${VERSION}-${ARCH}.tar.gz"
    local base_url="https://github.com/${GITHUB_REPO}/releases/download/${VERSION}"
    local tarball_url="${base_url}/${filename}"
    local checksum_url="${tarball_url}.sha256"

    # Create temporary directory
    TEMP_DIR=$(mktemp -d)
    local tarball_path="${TEMP_DIR}/${filename}"
    local checksum_path="${tarball_path}.sha256"

    # Download files
    download_file "$tarball_url" "$tarball_path" "controller tarball"
    download_file "$checksum_url" "$checksum_path" "checksum file"

    # Verify integrity
    verify_checksum "$tarball_path" "$checksum_path"

    # Extract
    extract_tarball "$tarball_path"

    # Determine installed directory
    local installed_dir="${INSTALL_DIR}/interlinx-controller-${VERSION}"

    if [[ ! -d "$installed_dir" ]]; then
        error "Installation directory not found after extraction: $installed_dir"
    fi

    # Show next steps
    show_next_steps "$installed_dir"

    info "Bootstrap installation complete!"
}

# Run main function
main "$@"
