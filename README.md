# ansible-pi-rack

Ansible playbook to bootstrap and configure a Raspberry Pi homelab cluster. Designed for Raspberry Pi OS Lite (Debian 12 64-bit), it handles system hardening, K3s prerequisites (cgroups), and a standalone Docker installation.

## Features
- **Secure by Design**: Secrets and network details are never committed. They are injected at runtime via 1Password CLI (`op`).
- **OS Hardening**: Disables password authentication, root login, and configures passwordless sudo for the `admin` user. Onboard Bluetooth and Wi-Fi are disabled at boot (see [Onboard Radios](#onboard-radios-bluetooth--wi-fi)).
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
| `letsencrypt-email` | Contact email for Let's Encrypt certificate expiry/registration notices |
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

### Container Versions
Every container image is pinned to an explicit tag in `group_vars/pis/vars.yml` (`*_image_tag`) — never `:latest`. Compose only pulls an image when it is missing, so `:latest` silently freezes at whatever was first pulled.

[Renovate](https://docs.renovatebot.com/) watches those pins via the `# renovate:` comment above each one and opens a PR when a newer image is published. Its **Dependency Dashboard** issue lists every image and any pending updates. To upgrade:

1. Review and merge the Renovate PR (check the linked release notes for breaking changes).
2. `make deploy` — changing the tag makes Compose pull the new image and recreate the container.
3. `make versions` — confirm each Pi is running the pinned image.

Dependabot still handles GitHub Actions, Ansible collections and pip; Renovate only handles container images (`enabledManagers` in `renovate.json`).

#### Home Assistant pre-upgrade backups
When `make deploy` finds that the running Home Assistant image differs from `ha_image_tag`, it first pulls the new image, then stops HA and archives `config/` to `services/homeassistant/pre-upgrade-backups/pre-upgrade-<old-tag>-<timestamp>.tar.gz`, and only then starts the new version. Unlike HA's own backups, the archive includes the history database (`home-assistant_v2.db`) and the Zigbee database (`zigbee.db`), and it is consistent because HA is stopped while it is taken. HA's `backups/` and `.cache/` are left out. The newest 5 archives are kept (`homeassistant_backup_keep`). They are owned by root with mode `0600` because they contain `secrets.yaml` and HA's auth store. If the backup fails, HA is restarted on the old image and the play stops without upgrading.

To roll back an upgrade that broke something:

1. Revert the Renovate PR on GitHub, then `git pull`.
2. On the Pi, stop HA and restore the archive taken before the upgrade:
   ```bash
   cd ~/services/homeassistant
   sudo docker compose stop homeassistant
   sudo mv config config.broken
   sudo mkdir config
   sudo tar --extract --gzip --file pre-upgrade-backups/pre-upgrade-<old-tag>-<timestamp>.tar.gz --directory config
   sudo mv config.broken/backups config/   # keep HA's own backups
   ```
3. `make deploy` — this starts HA on the old image. The stopped container still names the newer image, so the deploy also takes one more archive, of the config you just restored. That's harmless.
4. Once HA is working, delete `config.broken`.

To test the failure path (backup fails → HA restarts on its current image and the play stops), pretend an upgrade is due and point the archive at a directory that doesn't exist:

```bash
make deploy ARGS="--limit homeassistant_nodes -e ha_image_tag=<newer-tag> -e homeassistant_backup_file=/nonexistent/test.tar.gz"
```

Both `-e` overrides exist only for that run, and nothing in git changes. `ha_image_tag` triggers the backup, and `-e` takes priority over the block's own `homeassistant_backup_file`, so `tar` fails just after HA is stopped. Expect the play to fail with "Pre-upgrade backup failed…", then check that `make versions` shows HA on its **old** tag with a fresh "Up" time. Use a tag you will upgrade to anyway, because the image is pulled before the backup step and stays on disk. HA is down for about 10–20 seconds.

### Onboard Radios (Bluetooth / Wi-Fi)
The rack is wired, so onboard Bluetooth and Wi-Fi are disabled on every Pi by default (`group_vars/pis/vars.yml`):

```yaml
bluetooth_enabled: false
wifi_enabled: false
```

When disabled, the `common` role adds `dtoverlay=disable-bt` / `dtoverlay=disable-wifi` to a managed block in `config.txt` (so the firmware never brings the radio up), stops and disables the `hciuart` and `bluetooth` services, and the Home Assistant container is deployed without the host D-Bus mount.

To re-enable a radio on a single Pi, set the variable on that host in `inventory.yml`, then push the inventory and deploy:

```yaml
pis:
  hosts:
    pi02:
      ansible_host: 192.168.1.51
      ansible_user: admin
      bluetooth_enabled: true
```

```bash
make inventory-push
make check    # expect the config.txt block, services and HA compose to change
make deploy   # the Pi reboots to apply the config.txt change
```

To re-enable on every Pi instead, change the default in `group_vars/pis/vars.yml`.

After re-enabling Bluetooth, re-add the Bluetooth integration in Home Assistant (Settings → Devices & services). It may then ask for extra permissions (`cap_add: [NET_ADMIN, NET_RAW]`) for full adapter control. Note that this grants the container control over the host's network configuration, because it uses host networking.

> **Safety check:** the playbook refuses to disable Wi-Fi on a host whose default route is over a `wl*` interface, so a Wi-Fi-connected Pi can't be stranded. Set `wifi_enabled: true` for that host, or move it to Ethernet first.

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
