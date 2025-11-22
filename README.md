# Interlinx Controller - Bootstrap Installer

A minimal bootstrap installer script for downloading and extracting the Interlinx Controller standalone release.

## Prerequisites

- Root or sudo access
- Internet connectivity
- GitHub Personal Access Token with `repo` scope
- Required commands: `curl`, `tar`, `sha256sum`, `jq`

## Installation

### Quick Start

```bash
curl -fsSL https://raw.githubusercontent.com/interlinx-io/interlinx-quickstart/main/install.sh | sudo bash
```

You will be prompted to enter your GitHub Personal Access Token.

### Alternative: Download First

```bash
wget https://raw.githubusercontent.com/interlinx-io/interlinx-quickstart/main/install.sh
chmod +x install.sh
sudo ./install.sh
```

### Non-Interactive (Automation)

```bash
sudo ./install.sh --token ghp_your_token_here
```

### Install Specific Version

```bash
sudo ./install.sh --version v1.4.0 --token ghp_your_token_here
```

## Options

| Option | Description |
|--------|-------------|
| `--token <token>` | GitHub Personal Access Token for authentication |
| `--version <ver>` | Specific version to install (default: latest) |
| `--help` | Display help message |

## GitHub Personal Access Token

Create a token at: https://github.com/settings/tokens

Required scope: `repo` or `repo:private_repo`

## What It Does

1. Validates prerequisites
2. Authenticates with GitHub using your PAT
3. Downloads the latest release (or specified version)
4. Verifies SHA256 checksum
5. Extracts the controller
6. Displays next steps

## Support

For issues with this bootstrap script, open an issue in this repository.

---

**Note**: This is a bootstrap installer only. Follow the on-screen instructions after installation to complete setup.
