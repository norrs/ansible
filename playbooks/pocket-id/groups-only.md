# Scoped application groups

`groups-only.yaml` creates only the explicitly selected Pocket ID groups and
preserves existing memberships. It does not restart Pocket ID or change users.
Configure these inputs privately:

```yaml
pocket_id_hostname: identity.example.net
pocket_id_api_op_vault: YOUR_PRIVATE_VAULT
pocket_id_api_op_item: pocket-id
pocket_id_api_key_field: API_KEY
pocket_id_group_names: [media-admins, media-users]
pocket_id_user_groups:
  - name: media-admins
    friendly_name: Media Administrators
  - name: media-users
    friendly_name: Media Users
```

Store the existing administrator API key in the configured secret-manager
field, not in inventory. Keep actual domains and group names private.

```sh
ansible-playbook -i inventory.yaml playbooks/pocket-id/groups-only.yaml \
  --limit media_hosts --ask-become-pass
```

Set `pocket_id_hosts` if the play's default target does not match your inventory.
The separate full Pocket ID playbook also supports a `members` list per group.
Only supply it when you intend authoritative membership replacement: usernames
must each resolve exactly once, and the resulting member list replaces the
existing list. Omitting `members` leaves that group's membership unmanaged.
The groups-only play never applies those membership lists.
