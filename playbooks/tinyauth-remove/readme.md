# TinyAuth removal playbook

This playbook decommissions a previous TinyAuth deployment without deleting
TinyAuth's data by default.

It stops and disables `tinyauth`, runs `docker compose down` when
`/service/tinyauth/compose.yaml` exists, removes any leftover `tinyauth`
container, removes `/etc/systemd/system/tinyauth.service`, and removes the old
nginx-proxy vhost snippet when `tinyauth_remove_hostname` is set and the file
still contains the old TinyAuth logout marker. This avoids deleting the new
oauth2-proxy snippet when both use the same auth hostname.

Run it through the Dalaran playbook with the explicit cleanup tag:

```bash
ansible-playbook playbooks/dalaran/playbook.yaml --tags dalaran-remove-tinyauth --ask-become-pass
```

The service directory `/service/tinyauth` is retained. To remove it too, set:

```yaml
tinyauth_remove_purge_data: true
```
