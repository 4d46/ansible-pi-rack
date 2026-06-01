VAULT_TPL := group_vars/pis/vault.yml.tpl
VAULT_YML := group_vars/pis/vault.yml
INVENTORY := inventory.yml
PLAYBOOK  := site.yml

.PHONY: deploy deploy-bootstrap check clean lint deps _inject

# Normal idempotent re-run (admin SSH key must already be deployed)
deploy: _inject
	ansible-playbook -i $(INVENTORY) $(PLAYBOOK) $(ARGS)
	@rm -f $(VAULT_YML)

# First-run: Pi Imager creates admin user with password auth
# We disable SSH hardening here as a safety measure.
# We use IdentitiesOnly=yes to prevent "Too many authentication failures" from local keys.
deploy-bootstrap: _inject
	ansible-playbook -i $(INVENTORY) $(PLAYBOOK) -u admin --ask-pass --ask-become-pass \
		-e ssh_enforce_hardening=false \
		--ssh-common-args='-o IdentitiesOnly=yes' \
		$(ARGS)
	@rm -f $(VAULT_YML)

# Dry-run with diff (does not make changes)
check: _inventory_check _inject
	ansible-playbook -i $(INVENTORY) $(PLAYBOOK) --check --diff $(ARGS)
	@rm -f $(VAULT_YML)

# Push local inventory to 1Password
inventory-push:
	@if [ ! -f $(INVENTORY) ]; then echo "Error: $(INVENTORY) not found."; exit 1; fi
	op item edit "PiRack" --vault "System Credentials" "inventory[text]=$$(cat $(INVENTORY))"

# Pull latest inventory from 1Password
inventory-pull:
	op read "op://System Credentials/PiRack/inventory" > $(INVENTORY)

# Show difference between local and 1Password inventory
inventory-diff:
	@if [ ! -f $(INVENTORY) ]; then echo "Local $(INVENTORY) missing."; exit 1; fi
	@op read "op://System Credentials/PiRack/inventory" > .inventory.yml.tmp
	@diff -u .inventory.yml.tmp $(INVENTORY) || (echo "\nInventory mismatch found! Use 'make inventory-push' or 'make inventory-pull'."; rm .inventory.yml.tmp; exit 1)
	@rm .inventory.yml.tmp
	@echo "Inventory is in sync."

# Private target to ensure inventory exists and warn if out of sync
_inventory_check:
	@if [ ! -f $(INVENTORY) ]; then \
		echo "ERROR: $(INVENTORY) is missing!"; \
		echo "Run 'make inventory-pull' to fetch it from 1Password."; \
		exit 1; \
	fi
	@op read "op://System Credentials/PiRack/inventory" > .inventory.yml.tmp
	@diff -q .inventory.yml.tmp $(INVENTORY) > /dev/null || ( \
		echo "WARNING: Local $(INVENTORY) differs from 1Password!"; \
		echo "Run 'make inventory-diff' to see changes."; \
	)
	@rm .inventory.yml.tmp

# Always re-inject from 1Password — never reuse a stale vault.yml
_inject:
	@echo "Injecting secrets from 1Password..."
	op inject -f -i $(VAULT_TPL) -o $(VAULT_YML)

deps:
	ansible-galaxy collection install -r requirements.yml
	pip install -r requirements.txt

lint:
	ansible-lint $(PLAYBOOK)

clean:
	rm -f $(VAULT_YML)
	rm -rf .ansible_cache
