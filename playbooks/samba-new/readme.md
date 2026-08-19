# Samba New playbook

This playbook runs `crazymax/samba` as a Docker Compose service.

Concrete volumes, users, shares, and Samba options belong in private vars.
Passwords are read from 1Password and rendered as root-owned secret files, then
referenced from `config.yml` using `password_file`.

## 1Password

Default item:

```text
vault: infra.norrs
item: samba-new/dalaran
```

Each `samba_new_auth` entry must define a `password_field`, for example:

```yaml
samba_new_auth:
  - user: example
    group: example
    uid: 1000
    gid: 1000
    password_field: example_password
```

The password is mounted into the container as:

```text
/run/secrets/example_password
```

Source:

- https://github.com/crazy-max/docker-samba
