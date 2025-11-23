#!/usr/bin/env bash

#
# Interlinx Controller & Agent Bootstrap Installer
#
# Downloads and extracts the Interlinx Controller standalone release
# and optionally the Interlinx Agent from private GitHub repositories.
#
# Usage:
#   ./install.sh [options]
#
# Options:
#   --token <pat>              GitHub Personal Access Token for authentication
#   --controller-version <ver> Specific controller version to install (default: latest)
#   --agent-version <ver>      Specific agent version to install (default: latest)
#   --help                     Display this help message
#

set -e
set -o pipefail

# Configuration
CONTROLLER_REPO="interlinx-io/interlinx-controller"
AGENT_REPO="interlinx-io/downloads"
INSTALL_DIR="/opt"
ARCH="linux-x64"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Variables
GITHUB_TOKEN=""
CONTROLLER_VERSION=""
AGENT_VERSION=""
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
Interlinx Controller & Agent Bootstrap Installer

Downloads the Interlinx Controller and Agent from private GitHub repositories.

USAGE:
    ./install.sh [OPTIONS]

OPTIONS:
    --token <token>              GitHub Personal Access Token (PAT) for authentication
                                 If not provided, will prompt interactively

    --controller-version <ver>   Specific controller version to install (e.g., v1.4.0)
                                 Default: latest release

    --agent-version <ver>        Specific agent version to install (e.g., v1.0.0)
                                 Default: latest release

    --help                       Display this help message and exit

EXAMPLES:
    # Interactive mode (prompts for PAT)
    sudo ./install.sh

    # Non-interactive with token
    sudo ./install.sh --token ghp_xxxxxxxxxxxx

    # Specific versions
    sudo ./install.sh --controller-version v1.4.0 --agent-version v1.0.0 --token ghp_xxxxxxxxxxxx

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

    The agent will be downloaded to the current directory as:
        agent-vX.X.X-linux.run

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

    for cmd in curl tar sha256sum jq; do
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

        # Read from /dev/tty to support piped script execution
        if [[ -t 0 ]]; then
            # stdin is a terminal
            read -s -p "Enter your GitHub PAT: " GITHUB_TOKEN
        else
            # stdin is redirected (piped script), read from terminal directly
            read -s -p "Enter your GitHub PAT: " GITHUB_TOKEN < /dev/tty
        fi
        echo ""

        if [[ -z "$GITHUB_TOKEN" ]]; then
            error "GitHub token is required"
        fi
    fi
}

get_latest_version() {
    local repo=$1
    local version_var_name=$2

    info "Fetching latest release version for $repo..."

    local response
    response=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
        "https://api.github.com/repos/${repo}/releases/latest" 2>&1)

    local http_code=$(echo "$response" | grep -o '"message":' | wc -l)

    if echo "$response" | grep -q '"message": "Bad credentials"'; then
        error "Invalid GitHub token. Please check your Personal Access Token."
    elif echo "$response" | grep -q '"message": "Not Found"'; then
        error "Repository not found or token lacks access. Ensure your PAT has 'repo' scope."
    elif echo "$response" | grep -q '"tag_name"'; then
        local version=$(echo "$response" | grep '"tag_name":' | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')
        info "Latest version: $version"

        # Set the version variable dynamically
        if [[ "$version_var_name" == "CONTROLLER_VERSION" ]]; then
            CONTROLLER_VERSION="$version"
        elif [[ "$version_var_name" == "AGENT_VERSION" ]]; then
            AGENT_VERSION="$version"
        fi
    else
        error "Failed to fetch latest release. Response: $response"
    fi
}

verify_version_exists() {
    local repo=$1
    local version=$2

    info "Verifying version $version exists in $repo..."

    local url="https://api.github.com/repos/${repo}/releases/tags/${version}"
    local response
    response=$(curl -s -H "Authorization: token $GITHUB_TOKEN" "$url" 2>&1)

    if echo "$response" | grep -q '"message": "Not Found"'; then
        error "Version $version not found in repository $repo"
    fi
}

get_asset_id() {
    local repo=$1
    local version=$2
    local asset_name=$3

    local url="https://api.github.com/repos/${repo}/releases/tags/${version}"
    local response
    response=$(curl -s -H "Authorization: token $GITHUB_TOKEN" "$url" 2>&1)

    if echo "$response" | grep -q '"message": "Not Found"'; then
        error "Version $version not found in repository $repo"
    fi

    # Extract asset ID for the given filename using jq
    local asset_id
    if command -v jq &> /dev/null; then
        asset_id=$(echo "$response" | jq -r ".assets[] | select(.name == \"$asset_name\") | .id")
    else
        # Fallback to grep/sed if jq not available
        asset_id=$(echo "$response" | grep -B 2 "\"name\": \"$asset_name\"" | grep '"id":' | head -1 | sed -E 's/.*"id": *([0-9]+).*/\1/')
    fi

    if [[ -z "$asset_id" ]] || [[ "$asset_id" == "null" ]]; then
        error "Asset '$asset_name' not found in release $version"
    fi

    echo "$asset_id"
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

download_agent() {
    info "Checking for Interlinx Agent..."

    # Determine version
    if [[ -z "$AGENT_VERSION" ]]; then
        get_latest_version "$AGENT_REPO" "AGENT_VERSION"
    else
        verify_version_exists "$AGENT_REPO" "$AGENT_VERSION"
    fi

    # Download to current directory with versioned filename
    local agent_output="agent-${AGENT_VERSION}-linux.run"

    # Check if agent already exists
    if [[ -f "$agent_output" ]]; then
        info "Agent already exists: $agent_output (skipping download)"
        # Ensure it's executable
        chmod +x "$agent_output"
        return 0
    fi

    info "Downloading Interlinx Agent..."

    # The agent asset is named "agent--linux.run" (no version in filename)
    local agent_asset_name="agent--linux.run"

    # Get asset ID
    local agent_asset_id
    agent_asset_id=$(get_asset_id "$AGENT_REPO" "$AGENT_VERSION" "$agent_asset_name")

    # Construct download URL
    local agent_url="https://api.github.com/repos/${AGENT_REPO}/releases/assets/${agent_asset_id}"

    download_file "$agent_url" "$agent_output" "Interlinx Agent"

    # Make executable
    chmod +x "$agent_output"
    info "Agent downloaded to: $agent_output (executable)"
}

show_next_steps() {
    local installed_dir=$1
    local agent_file=$2

    cat << EOF

============================================
Interlinx Controller & Agent downloaded successfully!
============================================

Controller Location: ${installed_dir}
Agent Location: ${agent_file}

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
            --controller-version)
                CONTROLLER_VERSION="$2"
                shift 2
                ;;
            --agent-version)
                AGENT_VERSION="$2"
                shift 2
                ;;
            --version)
                # Support legacy --version flag for controller
                warn "The --version flag is deprecated. Use --controller-version instead."
                CONTROLLER_VERSION="$2"
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

    # Determine controller version
    if [[ -z "$CONTROLLER_VERSION" ]]; then
        get_latest_version "$CONTROLLER_REPO" "CONTROLLER_VERSION"
    else
        verify_version_exists "$CONTROLLER_REPO" "$CONTROLLER_VERSION"
    fi

    # Determine installed directory
    local installed_dir="${INSTALL_DIR}/interlinx-controller-${CONTROLLER_VERSION}"

    # Check if controller is already installed
    if [[ -d "$installed_dir" ]]; then
        info "Controller already installed at: $installed_dir (skipping download)"
    else
        info "Installing Interlinx Controller..."

        # Construct filenames
        local filename="interlinx-controller-${CONTROLLER_VERSION}-${ARCH}.tar.gz"
        local checksum_filename="${filename}.sha256"

        # Get asset IDs from GitHub API
        info "Fetching controller release assets..."
        local tarball_asset_id
        local checksum_asset_id
        tarball_asset_id=$(get_asset_id "$CONTROLLER_REPO" "$CONTROLLER_VERSION" "$filename")
        checksum_asset_id=$(get_asset_id "$CONTROLLER_REPO" "$CONTROLLER_VERSION" "$checksum_filename")

        # Construct API URLs for private repo asset downloads
        local tarball_url="https://api.github.com/repos/${CONTROLLER_REPO}/releases/assets/${tarball_asset_id}"
        local checksum_url="https://api.github.com/repos/${CONTROLLER_REPO}/releases/assets/${checksum_asset_id}"

        # Create temporary directory
        TEMP_DIR=$(mktemp -d)
        local tarball_path="${TEMP_DIR}/${filename}"
        local checksum_path="${TEMP_DIR}/${checksum_filename}"

        # Download files
        download_file "$tarball_url" "$tarball_path" "controller tarball"
        download_file "$checksum_url" "$checksum_path" "checksum file"

        # Verify integrity
        verify_checksum "$tarball_path" "$checksum_path"

        # Extract
        extract_tarball "$tarball_path"

        if [[ ! -d "$installed_dir" ]]; then
            error "Installation directory not found after extraction: $installed_dir"
        fi
    fi

    # Download agent
    local agent_file="agent-${AGENT_VERSION:-latest}-linux.run"
    download_agent

    # Update agent_file with actual version after download
    if [[ -n "$AGENT_VERSION" ]]; then
        agent_file="agent-${AGENT_VERSION}-linux.run"
    fi

    # Show next steps
    show_next_steps "$installed_dir" "$agent_file"

    info "Bootstrap installation complete!"
}

# Run main function
main "$@"
