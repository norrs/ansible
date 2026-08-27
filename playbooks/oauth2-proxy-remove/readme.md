# oauth2-proxy removal playbook

This playbook decommissions oauth2-proxy without deleting its service directory
by default.

It stops and disables `oauth2-proxy`, runs `docker compose down` when
`/service/oauth2-proxy/compose.yaml` exists, removes any leftover
`oauth2-proxy` container, removes `/etc/systemd/system/oauth2-proxy.service`,
and removes the old nginx-proxy auth-host snippet when
`oauth2_proxy_remove_hostname` is set and the file still contains oauth2-proxy
logout markers.

Run it through the Dalaran playbook with:

```bash
ansible-playbook playbooks/dalaran/playbook.yaml --tags dalaran-remove-oauth2-proxy --ask-become-pass
```

The service directory `/service/oauth2-proxy` is retained. To remove it too,
set:

```yaml
oauth2_proxy_remove_purge_data: true
```
