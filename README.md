# Interlinx Controller & Agent - Bootstrap Installer

A minimal bootstrap installer script for downloading and extracting the Interlinx Controller standalone release and the Interlinx Agent.

## Prerequisites

- Root or sudo access
- Internet connectivity
- Required commands: `curl`, `tar`, `sha256sum`, `jq`

## Installation

### Quick Start

```bash
curl -fsSL https://raw.githubusercontent.com/interlinx-io/interlinx-quickstart/main/install.sh | sudo bash
```

You will be prompted for authentication when accessing private repositories.

### Alternative: Download First

```bash
wget https://raw.githubusercontent.com/interlinx-io/interlinx-quickstart/main/install.sh
chmod +x install.sh
sudo ./install.sh
```

### Non-Interactive (Automation)

```bash
sudo ./install.sh --token <your-token>
```

### Install Specific Versions

```bash
# Specify controller version only
sudo ./install.sh --controller-version v1.4.0 --token <your-token>

# Specify both controller and agent versions
sudo ./install.sh --controller-version v1.4.0 --agent-version v1.0.0 --token <your-token>

# Specify agent version only (controller will use latest)
sudo ./install.sh --agent-version v1.0.0 --token <your-token>
```

## Options

| Option | Description |
|--------|-------------|
| `--token <token>` | Authentication token for private repositories |
| `--controller-version <ver>` | Specific controller version to install (default: latest) |
| `--agent-version <ver>` | Specific agent version to install (default: latest) |
| `--help` | Display help message |

## What It Does

1. Validates prerequisites
2. Authenticates for private repository access
3. Downloads the controller release (or specified version)
4. Verifies SHA256 checksum for the controller
5. Extracts the controller to `/opt/interlinx-controller-<version>/`
6. Downloads the agent release (or specified version)
7. Saves the agent as `agent-<version>-linux.run` (executable) in the current directory
8. Displays next steps

## Support

For issues with this bootstrap script, open an issue in this repository.

---

**Note**: This is a bootstrap installer only. Follow the on-screen instructions after installation to complete setup.
