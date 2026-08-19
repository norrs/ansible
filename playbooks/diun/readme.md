# Diun playbook

This playbook runs [Diun](https://crazymax.dev/diun/) as a Docker Compose
service under `/service/diun`.

Diun watches local Docker images and sends notifications when image updates are
available. It does not update containers.

Notifications include the Diun container hostname. The playbook sets:

```yaml
diun_hostname: "{{ inventory_hostname }}"
```

Override `diun_hostname` per host if the inventory name is not the name you want
to see in Discord or Pushover.

## 1Password

Notification secrets are read from the `infra.norrs` vault by default.

Default item:

```text
diun/notifications
```

Expected fields when both Discord and Pushover are enabled:

```text
discord_webhook_url: https://discord.com/api/webhooks/...
pushover_token: <Pushover application/API token>
pushover_recipient: <Pushover user key>
```

The playbook renders those values to root-owned files under
`/service/diun/secrets` and configures Diun with `webhookURLFile`, `tokenFile`,
and `recipientFile`.

## Defaults

The Docker provider is enabled with:

```yaml
diun_docker_watch_by_default: true
diun_docker_watch_stopped: false
```

The default schedule is every six hours:

```yaml
diun_watch_schedule: "0 */6 * * *"
```

Sources:

- https://crazymax.dev/diun/install/docker/
- https://crazymax.dev/diun/providers/docker/
- https://crazymax.dev/diun/notif/discord/
- https://crazymax.dev/diun/notif/pushover/
