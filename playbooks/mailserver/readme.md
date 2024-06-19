# Playbook: mailserver

* https://github.com/docker-mailserver/docker-mailserver
* https://docker-mailserver.github.io/docker-mailserver/latest/

## Custom: Ensure source IP addresses is the one specified by SPF

Bind outgoing SMTP connections to specific IP-addresses to ensure MX records are aligned with
PTR-records in DNS when sending emails to avoid getting blocked by SPF.

We can use the tricks
of [overriding defaults in postfix configuration](https://docker-mailserver.github.io/docker-mailserver/latest/config/advanced/override-defaults/postfix/)
by supplying a custom `docker-data/dms/config/postfix-master.cf`
and `docker-data/dms/config/postfix-main.cf`.

In `postfix-main.cf` you'll have to set
the [smtp_bind_address](https://www.postfix.org/postconf.5.html#smtp_bind_address)
and [smtp_bind_address6](https://www.postfix.org/postconf.5.html#smtp_bind_address6)
to the respective IP-address on the server you want to use.

IP-addresses shown below are reserved documentation IP-addresses by
IANA, [RFC-5737](https://datatracker.ietf.org/doc/rfc5737/)
and [RFC-3849](https://datatracker.ietf.org/doc/html/rfc3849).

Example `postfix-main.cf`:

```
smtp_bind_address = 198.51.100.10
smtp_bind_address6 = 2001:DB8::10
```

One problem with using `smtp_bind_address` is that the default configuration for `smtp-amavis` in
DMS needs to be updated & explicit configured to connect via loopback (localhost) to avoid using
the `smtp_bind_address` as source address when "forwarding" email for filtering via amavis.
This seems to be a better configuration than adding your bind-addresses to `mynetworks`
configuration in
Postfix.

Example `postfix-master.cf`:

```
smtp-amavis/unix/smtp_bind_address=127.0.0.1
smtp-amavis/unix/smtp_bind_address6=::1
```
