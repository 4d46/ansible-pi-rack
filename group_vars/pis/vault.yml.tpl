# Generated at deploy time by: op inject -i vault.yml.tpl -o vault.yml
# DO NOT commit vault.yml — it is git-ignored

# 1Password item: System Credentials/PiRack
vault_admin_password: "{{ op://System Credentials/PiRack/password }}"
vault_admin_ssh_key:  "{{ op://System Credentials/PiRack/ssh-public-key }}"
vault_grafana_pdc_token: "{{ op://System Credentials/PiRack/es pdc agent token }}"
vault_grafana_pdc_cluster: "{{ op://System Credentials/PiRack/es pdc cluster }}"
vault_grafana_pdc_hosted_grafana_id: "{{ op://System Credentials/PiRack/es pdc hosted grafana id }}"
vault_tailscale_authkey: "{{ op://System Credentials/PiRack/tailscale authkey }}"
vault_rack_subnet: "{{ op://System Credentials/PiRack/rack subnet }}"
vault_gandi_token: "{{ op://System Credentials/PiRack/gandi-livedns-token }}"
vault_tls_hostname_fqdn: "{{ op://System Credentials/PiRack/hostname-fqdn }}"


