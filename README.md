
# Rockj's ansible files

I guess it is time to put things in ansible for my infra.

This setup consists of [public ansible](https://github.com/norrs/ansible) configuration,
where [my private](https://github.com/norrs/ansible-private) ansible configuration is added as a
submodule. My private collection does not contain secrets, but sensitive enough that I simply
don't want to announce to the Internet(tm).

## Collections

NB: Doesn't use onepassword.connect yet, but keeping it for now.

```
$ ansible-galaxy collection install onepassword.connect
$ ansible-galaxy collection install community.general
```

## Secrets

Obtained via 1password integrations.


# Links to READMEs

- [playbooks/bind/readme.md](./playbooks/bind/readme.md)
- [playbooks/mailserver/readme.md](./playbooks/mailserver/readme.md)
- [private/README.md](https://github.com/norrs/ansible-private/blob/main/README.md)
