# WireGuard monitoring client

## Goal

Remote monitored servers should reach the Beszel hub on Dalaran through the
monitoring WireGuard server at Dune.

The intended flow is:

```text
agent host -> WireGuard client -> Dune -> dalaran Beszel hub
```

Beszel agents should use WebSocket mode after the tunnel is up:

```text
agent -> https://<dalaran Beszel hub>/api/beszel/agent-connect
```

Dalaran does not need to initiate Beszel agent connections to remote hosts.

## 1Password layout

Use the `infra.norrs` vault.

Server item:

```text
wireguard/dune/server/monitoring
```

Expected fields:

```text
endpoint_host: vpn.example.net
endpoint_port: 51820
server_public_key: <WireGuard server public key>
network_name: monitoring
```

Peer item example:

```text
wireguard/dune/peers/monitoring/diablo
```

Expected fields:

```text
peer_name: monitored-host-01
client_ipv4: 192.0.2.10
client_ipv6: 2001:db8:50::10
client_public_key: <WireGuard client public key>
client_private_key: <WireGuard client private key>
preshared_key: <WireGuard peer pre-shared key>
allowed_ips: 192.0.2.25/32,2001:db8:50::25/128
persistent_keepalive: 25
```

`client_ipv4` and `client_ipv6` may include CIDR suffixes. If omitted, the
playbook renders `/32` for IPv4 and `/128` for IPv6.

`allowed_ips` should be narrow. For the monitoring VPN, prefer the Dalaran
Beszel hub address only, for example:

```text
10.0.0.10/32
```

or, if using IPv6:

```text
fd00:example::10/128
```

`AllowedIPs` controls client routing. Access control still belongs at Dune,
where the peer should be allowed only to reach Dalaran's Beszel hub URL/port and
denied broad LAN access.

## Bootstrap order

1. Install and configure the WireGuard client on the remote host.
2. Bring up `wg-monitoring`.
3. Verify the peer can reach only Dalaran's Beszel hub port through Dune.
4. Install/configure the Beszel agent with WebSocket mode:

```text
HUB_URL=<dalaran Beszel hub URL>
KEY=<Beszel hub public key>
TOKEN=<Beszel universal registration token>
SYSTEM_NAME=<inventory host name>
DISABLE_SSH=true
```

5. Confirm the agent self-registers in Beszel.

Beszel hub registration material belongs in one shared 1Password item:

```text
beszel/hub/dalaran
```

The per-agent Beszel config should normally be derived from Ansible inventory
and defaults rather than duplicated in 1Password.
