# ansible-pi-rack

Ansible playbook to bootstrap and configure a Raspberry Pi homelab cluster. Designed for Raspberry Pi OS Lite (Debian 12 64-bit), it handles system hardening, K3s prerequisites (cgroups), and a standalone Docker installation.

## Features
- **Secure by Design**: Secrets and network details are never committed. They are injected at runtime via 1Password CLI (`op`).
- **OS Hardening**: Disables password authentication, root login, and configures passwordless sudo for the `admin` user.
- **K3s Ready**: Automatically enables `cpuset` and `memory` cgroups.
- **Docker Engine**: Installs Docker CE with log rotation configured to prevent SD card wear.
- **CI Integrated**: GitHub Actions workflow for automated linting.

## Prerequisites
- [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html)
- [1Password CLI (`op`)](https://developer.1password.com/docs/cli/get-started/)
- [Make](https://www.gnu.org/software/make/)

## Setup

### 1. 1Password Vault Setup
Create an item in 1Password named **`System Credentials/PiRack`** with the following fields:

| Field | Description |
| :--- | :--- |
| `password` | The password for the `admin` user |
| `ssh-public-key` | Your public SSH key |
| `es pdc agent token` | Grafana PDC agent token |
| `es pdc cluster` | Grafana PDC cluster URL |
| `es pdc hosted grafana id` | Hosted Grafana ID for PDC |
| `tailscale authkey` | Tailscale authentication key |
| `rack subnet` | Network subnet for Tailscale routing (e.g., 192.168.1.0/24) |
| `gandi-livedns-token` | Gandi LiveDNS API token, for certbot DNS-01 challenges |
| `hostname-fqdn` | Fully-qualified domain name for the Let's Encrypt TLS certificate |
| `inventory` | (Text field) The contents of your `inventory.yml` |

### 2. Local Configuration
1. Copy the example inventory:
   ```bash
   cp inventory.yml.example inventory.yml
   ```
2. Edit `inventory.yml` with your Pi's hostname and IP address.

## Usage

### Setup and Maintenance
- `make deps`: Install required Ansible collections and Python dependencies.
- `make lint`: Run `ansible-lint` on the playbook.
- `make clean`: Remove generated `vault.yml` and cache files.

### Inventory Management (1Password Sync)
- `make inventory-pull`: Fetch the `inventory.yml` stored in 1Password.
- `make inventory-push`: Push your local `inventory.yml` to 1Password.
- `make inventory-diff`: Compare local inventory with the version in 1Password.

### Deployment
- **Initial Bootstrap**: Run once on fresh Pis using password authentication:
  ```bash
  make deploy-bootstrap
  ```
- **Standard Deploy**: Run for all subsequent updates (uses SSH keys):
  ```bash
  make deploy
  ```
- **Dry Run**: Preview changes without applying them:
  ```bash
  make check
  ```

## Repository Structure
- `group_vars/pis/vault.yml.tpl`: Template for secret injection from 1Password.
- `roles/common`: OS updates, hardening, cgroups, and user setup.
- `roles/docker`: Docker repository and package installation.
- `roles/elasticsearch`: Elasticsearch and Grafana PDC Agent deployment.
- `roles/tailscale`: Tailscale subnet router and exit node configuration.
- `roles/tls`: Let's Encrypt certificate issuance via Gandi DNS-01, with automatic renewal.
- `roles/homeassistant`: Home Assistant container deployment.
- `.github/workflows/lint.yml`: CI linting via `ansible-lint`.

## License
MIT
