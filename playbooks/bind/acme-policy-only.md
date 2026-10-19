# Media UI DNS-01 permissions

Use `acme-policy-only.yaml` to grant an existing ACME TSIG identity permission
to update only the configured application challenge TXT records. It does not
provision credentials, replace zone files, or change unrelated permissions.

Put these inputs in private inventory variables for the DNS server:

```yaml
bind_acme_policy_path: /etc/bind/application-update-policy.conf
bind_acme_tsig_key_name: acme-media.example.net.
bind_acme_challenge_hosts:
  - series.example.net
  - movies.example.net
  - profiles.example.net
```

The policy must already contain one `update-policy` block and be included by
the existing zone configuration. The challenge hostnames exclude the
`_acme-challenge` prefix and trailing dot; the TSIG identity includes its
trailing dot. Store actual names, paths, and any cross-host inventory references
privately, not in this playbook or public documentation.

```sh
ansible-playbook -i inventory.yaml playbooks/bind/acme-policy-only.yaml \
  --limit dns_hosts --check --diff --ask-become-pass
ansible-playbook -i inventory.yaml playbooks/bind/acme-policy-only.yaml \
  --limit dns_hosts --ask-become-pass
```

Replace `dns_hosts` with your DNS inventory group and set `bind_hosts` when it
differs from the play's default target. The live apply validates the complete
BIND configuration before reloading permissions, with rollback on failure.
This grants update permission; the ACME client creates and removes the actual
temporary TXT values during certificate issuance.
