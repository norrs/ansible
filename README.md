
# Rockj's ansible files

I guess it is time to put things in ansible for my infra.

This setup consists of [public ansible](https://github.com/norrs/ansible) configuration,
where [my private](https://github.com/norrs/ansible-private) ansible configuration is added as a
submodule. My private collection does not contain secrets, but sensitive enough that I simply
don't want to announce to the Internet(tm).

## Optional private companions

The `private/` submodule holds shared host configuration and operational runbooks.
The `friends/` submodule ([ansible-friends](https://github.com/norrs/ansible-friends))
contains my **invite-only playbooks**, shared privately with friends. Access
requires a personal invitation; cloning this public repository does not grant
access to that collection. It holds the media-stack and media-pruner playbooks,
their media-only helpers, and their media deployment variables.

Both companions require repository access; neither is necessary to read or
reuse the other public playbooks. Credentials are still obtained through the
secret provider, not stored in either submodule.

From an authorized checkout, initialize the companions you need:

```bash
git submodule update --init private
git submodule update --init friends
```

Alternatively, authorized users can clone with `--recurse-submodules`. Public
clones without access should omit recursive initialization. Media entry points
under `playbooks/` are symlinks into `friends/`; initialize that module before
running the media-enabled host playbook. Run through the parent entry points so
relative imports of shared proxy/authentication roles continue to resolve.

For this host, `group_vars/dalaran/` loads `00-private.yaml` from
`private/group_vars/dalaran.yaml` and `10-media.yaml` from
`friends/group_vars/dalaran.yaml` through symlinks. Keep shared settings in the
first file and media-only settings in the second; avoid duplicate keys because
later files replace earlier values rather than merging lists. Both companions
are required for the complete host inventory. No extra-vars or command changes
are needed to load the split configuration.

Commit and push companion changes before updating their pinned revisions here.
Updating submodules alone does not deploy services or migrate media files.

## Collections

NB: Doesn't use onepassword.connect yet, but keeping it for now.

```
$ ansible-galaxy collection install onepassword.connect
$ ansible-galaxy collection install community.general
```

## Secrets

Obtained via 1password integrations.

## Playbooks for nodes

`$ ansible-playbook --connection=local --inventory 127.0.0.1 --limit 127.0.0.1 playbooks/$HOSTNAME/playbook.yaml --ask-become-pass`

`$ ansible-playbook --connection=local --inventory 127.0.0.1 --limit 127.0.0.1 playbooks/orgrimmar/playbook.yaml --ask-become-pass`
`$ ansible-playbook --connection=local --inventory 127.0.0.1 --limit 127.0.0.1 playbooks/qhira/playbook.yaml --ask-become-pass`

## Example running a playbook from control host to what-ever-inventory is configured

`$ ansible-playbook playbooks/webserver/diablo.norrs.no/playbook.yaml --ask-become-pass`

Run a single Diablo stack part through the wrapper:

```bash
scripts/play-host.bash
scripts/play-host.bash diablo wireguard --ask-become-pass
scripts/play-host.bash diablo beszel-agent --ask-become-pass
scripts/play-host.bash diablo hosts-entry --ask-become-pass --check --diff
scripts/play-host.bash dalaran ordered-tags --ask-become-pass
```

The wrapper uses `fzf` for interactive selection when available. With no
arguments, it first asks for a run mode: single part, ordered tags, or full
playbook(s). In full-playbook mode the host menu supports selecting multiple
top-level playbooks; when using the numbered selector, enter comma-separated
numbers, ranges like `1-3`, or `all`. In ordered-tags mode, tags are selected
one at a time and run as separate `ansible-playbook --tags ...` calls in the
selected order. In interactive mode it asks whether to include
`--ask-become-pass`.

For auth migrations on Dalaran, use ordered-tags mode and select `tinyauth`,
`rtorrent-rutorrent`, `beszel`, then `nginx-validate`.

# Tips

Check facts:

`$ ansible --connection=local -i 127.0.0.1, all -m setup | less -R`

# Links to READMEs

- [playbooks/bind/readme.md](./playbooks/bind/readme.md)
- [playbooks/dalaran/readme.md](./playbooks/dalaran/readme.md)
- [playbooks/diun/readme.md](./playbooks/diun/readme.md)
- [playbooks/mailserver/readme.md](./playbooks/mailserver/readme.md)
- [playbooks/oauth2-proxy-remove/readme.md](./playbooks/oauth2-proxy-remove/readme.md)
- [playbooks/oauth2-proxy/readme.md](./playbooks/oauth2-proxy/readme.md)
- [playbooks/rtorrent-rutorrent/readme.md](./playbooks/rtorrent-rutorrent/readme.md)
- [playbooks/samba-new/readme.md](./playbooks/samba-new/readme.md)
- [playbooks/tinyauth-remove/readme.md](./playbooks/tinyauth-remove/readme.md)
- [playbooks/tinyauth/readme.md](./playbooks/tinyauth/readme.md)
- [playbooks/wireguard-client/readme.md](./playbooks/wireguard-client/readme.md)
- [playbooks/webmail/readme.md](./playbooks/webmail/readme.md)
- [private/README.md](https://github.com/norrs/ansible-private/blob/main/README.md)
- [private/playbooks/dalaran/readme.md](https://github.com/norrs/ansible-private/blob/main/playbooks/dalaran/readme.md)
