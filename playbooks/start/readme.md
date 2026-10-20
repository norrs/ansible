# Start launchpad

Deploy a prebuilt Start image behind the existing nginx-proxy. Start uses
native OIDC through TinyAuth; it is not protected solely by forward-auth.
The container runs non-root with a read-only root filesystem and persists its
database in the service data directory. Its diagnostic port binds to loopback.

Configure these settings in private inventory:

```yaml
start_hostname: start.example.com
start_image: registry.example.com/start:reviewed-version
start_admin_group: start-admins
start_trusted_proxies: 172.16.0.0/12
start_op_vault: your-private-vault
start_op_item: your-tinyauth-item
```

Register Start under `tinyauth_oidc_clients` with `START_CLIENT_ID`,
`START_CLIENT_SECRET` and callback `https://start.example.com/auth/callback`.
Deploy the DNS alias, ACME update permission, Pocket ID group and TinyAuth
client first. The playbook reads credentials from the secret store; the client
secret is mounted read-only as a protected file, not stored in the environment.
It does not build or fetch the image: deliver it to the target Docker daemon
before deployment.

```bash
ansible-playbook -i inventory.yaml playbooks/start/playbook.yaml \
  --limit your-host --check --diff --ask-become-pass
```

Use the host entry point's scoped tags to apply dependencies in order. The
private operational runbook contains installation-specific commands and values.
No playbook invocation is required merely to validate the syntax or render the
templates in unit tests.
