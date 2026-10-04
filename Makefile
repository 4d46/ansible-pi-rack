VAULT_TPL := group_vars/pis/vault.yml.tpl
VAULT_YML := group_vars/pis/vault.yml
INVENTORY := inventory.yml
PLAYBOOK  := site.yml

# Prefix for any recipe that runs with the decrypted vault on disk. Each recipe
# line is its own shell, so a separate 'rm' line never runs once the playbook
# fails. The trap removes the vault however the shell ends (success, failure
# or Ctrl-C) and leaves the playbook's exit code for make to see.
WITH_VAULT_CLEANUP := trap 'rm -f $(VAULT_YML)' EXIT INT TERM;

INVENTORY_REF := op://System Credentials/PiRack/inventory

# Prefix for recipes that compare against the 1Password copy of the inventory.
# It holds real hostnames and IPs, so it goes in a mktemp file (mode 0600, in
# the per-user temp dir, outside the repo) that the trap removes however the
# recipe ends; if 'op read' fails the recipe stops there. The copy is "$$remote".
# Wrap what follows in { ...; } if it uses ||, or an op failure runs that
# fallback instead of failing the recipe.
WITH_REMOTE_INVENTORY := remote=$$(mktemp) && trap 'rm -f "$$remote"' EXIT INT TERM && \
	op read "$(INVENTORY_REF)" > "$$remote" &&

.PHONY: deploy deploy-bootstrap check clean lint test deps lock versions upgrades upgrade-review _inject

# Normal idempotent re-run (admin SSH key must already be deployed)
deploy: _inject
	$(WITH_VAULT_CLEANUP) ansible-playbook -i $(INVENTORY) $(PLAYBOOK) $(ARGS)

# First-run: Pi Imager creates admin user with password auth
# We disable SSH hardening here as a safety measure.
# We use IdentitiesOnly=yes to prevent "Too many authentication failures" from local keys.
deploy-bootstrap: _inject
	$(WITH_VAULT_CLEANUP) ansible-playbook -i $(INVENTORY) $(PLAYBOOK) -u admin --ask-pass --ask-become-pass \
		-e ssh_enforce_hardening=false \
		--ssh-common-args='-o IdentitiesOnly=yes' \
		$(ARGS)

# Dry-run with diff (does not make changes)
check: _inventory_check _inject
	$(WITH_VAULT_CLEANUP) ansible-playbook -i $(INVENTORY) $(PLAYBOOK) --check --diff $(ARGS)

# Push local inventory to 1Password
inventory-push:
	@if [ ! -f $(INVENTORY) ]; then echo "Error: $(INVENTORY) not found."; exit 1; fi
	op item edit "PiRack" --vault "System Credentials" "inventory[text]=$$(cat $(INVENTORY))"

# Pull latest inventory from 1Password. Written to a temp file and renamed into
# place only once 'op read' succeeds: redirecting straight into $(INVENTORY)
# would empty it before op even ran. mktemp makes the result mode 0600.
inventory-pull:
	@new=$$(mktemp $(INVENTORY).XXXXXX) && trap 'rm -f "$$new"' EXIT INT TERM && \
		op read "$(INVENTORY_REF)" > "$$new" && mv "$$new" $(INVENTORY) && \
		echo "Pulled $(INVENTORY) from 1Password."

# Show difference between local and 1Password inventory
inventory-diff:
	@if [ ! -f $(INVENTORY) ]; then echo "Local $(INVENTORY) missing."; exit 1; fi
	@$(WITH_REMOTE_INVENTORY) \
		if diff -u "$$remote" $(INVENTORY); then echo "Inventory is in sync."; \
		else printf '\nInventory mismatch found! Use %s or %s.\n' "'make inventory-push'" "'make inventory-pull'"; exit 1; fi

# Private target to ensure inventory exists and warn if out of sync
_inventory_check:
	@if [ ! -f $(INVENTORY) ]; then \
		echo "ERROR: $(INVENTORY) is missing!"; \
		echo "Run 'make inventory-pull' to fetch it from 1Password."; \
		exit 1; \
	fi
	@$(WITH_REMOTE_INVENTORY) { \
		diff -q "$$remote" $(INVENTORY) > /dev/null || { \
			echo "WARNING: Local $(INVENTORY) differs from 1Password!"; \
			echo "Run 'make inventory-diff' to see changes."; \
		}; }

# Always re-inject from 1Password — never reuse a stale vault.yml
_inject:
	@echo "Injecting secrets from 1Password..."
	op inject -f -i $(VAULT_TPL) -o $(VAULT_YML)

# Show each running container, how long it has been up, and the image it was
# started from with the first 12 hex digits of its pinned digest. docker ps
# hides the digest part of an image reference, so it is read with inspect.
# Compare against the *_image_tag pins in group_vars/pis/vars.yml to spot drift.
# Fixed column widths keep every host's lines aligned with each other.
# {% raw %} stops Ansible treating Docker's Go-template braces as Jinja.
versions:
	@ansible all -i $(INVENTORY) -b -m ansible.builtin.shell \
		-a 'docker ps --format "{% raw %}{{.Names}}|{{.Status}}{% endraw %}" \
			| while IFS="|" read -r name status; do \
				printf "%-28s  %-18s  %s\n" "$$name" "$$status" \
					"$$(docker inspect --format "{% raw %}{{.Config.Image}}{% endraw %}" "$$name")"; \
			done | sed -E "s/(@sha256:[0-9a-f]{12})[0-9a-f]+/\1/"'

# List open Renovate/Dependabot PRs with their version changes, so you can
# find PR numbers without the GitHub web UI. See: scripts/upgrades help
upgrades:
	@scripts/upgrades list

# AI risk review of one upgrade PR: advisory, read-only, prints to the terminal.
# Usage: make upgrade-review PR=13    (ARGS=--dry-run shows exactly what is sent)
upgrade-review:
	@test -n "$(PR)" || { echo "Usage: make upgrade-review PR=<number>   (find numbers with: make upgrades)"; exit 2; }
	@scripts/upgrades review $(PR) $(ARGS)

# Python packages first: ansible-galaxy comes from them. --require-hashes makes
# pip refuse any file whose SHA-256 doesn't match the lock.
deps:
	pip install --require-hashes -r requirements.txt
	ansible-galaxy collection install -r requirements.yml

# Regenerate requirements.txt (the hash-pinned lock) from requirements.in,
# keeping the current versions. To upgrade one package on purpose:
#   make lock ARGS="--upgrade-package ansible"
# pip-tools runs in a throwaway environment via uvx, on the .tool-versions
# Python (UV_PYTHON_DOWNLOADS=never stops uv fetching its own); nothing is installed.
# click<8.3: pip-tools 7.6.1 with newer click writes a spurious --no-index into
# the lock's header, and Dependabot re-runs that command when it updates the lock.
lock:
	UV_PYTHON_DOWNLOADS=never uvx --python python3 --with 'click<8.3' --from pip-tools pip-compile \
		--generate-hashes --allow-unsafe --strip-extras --quiet \
		--output-file=requirements.txt requirements.in $(ARGS)

lint:
	ansible-lint $(PLAYBOOK)

test:
	scripts/tests/test_upgrades.sh

clean:
	rm -f $(VAULT_YML)
	rm -rf .ansible_cache
