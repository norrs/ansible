# Bind playbook

## Nice docs

https://kb.isc.org/docs/dnssec-key-and-signing-policy

Don't need additional salt iterations on
`nsec3`: https://datatracker.ietf.org/doc/html/draft-ietf-dnsop-nsec3-guidance-10#section-2.4

## Updates

Always make sure to update serial in the zonefile. Format `<yyyy><mm><dd><nn>` where `nn` is change
number for that particular day.

`norrs.no` uses inline signing and can receive dynamic DNS updates for ACME
challenges. The playbook freezes the zone before replacing the static zone file
and thaws it afterward, so BIND can sync/clean journal state before reloading.

## Dalaran ACME DNS-01

Dalaran uses RFC2136 dynamic DNS updates for ACME DNS-01 challenges.

The TSIG key is rendered from 1Password:

```text
vault: infra.norrs
item: bind9/named.conf.acme-dalaran
field: TSIG_SECRET
```

The private update-policy fragment lives at:

```text
private/playbooks/bind/files/etc/bind/named.conf.acme-dalaran-policy
```

The public `named.conf.local` includes `/etc/bind/named.conf.acme-dalaran-policy`
inside the `norrs.no` zone block. Keep concrete ACME challenge names in the
private policy fragment.

`/etc/bind/named.conf.acme-dalaran` is installed as `root:bind 0640` so the BIND
daemon can read it during `rndc reconfig`.

## Dynamic ACL address

BIND ACL address match lists do not accept arbitrary DNS hostnames; they need
IP addresses/prefixes, keys, ACL names, nested lists, or built-ins such as
`localhost` and `localnets`.

For private dynamic addresses, keep the concrete hostname and marker in:

```text
private/playbooks/bind/files/etc/bind/named.conf.acl
```

Example ACL entry:

```bind
acl trusted {
  203.0.113.42/32; // dynamic-ip: host.example.internal
};
```

`203.0.113.42` is from the RFC 5737 documentation range. The `dynamic-ip:`
comment is the marker. `scripts/update-dynamic-bind-acl.bash --all` scans the
private ACL file for those markers, resolves each hostname, and replaces the
address on that same line when it has changed.

The BIND playbook runs this helper locally before copying `named.conf.acl` to the
server. To run it manually:

```bash
scripts/update-dynamic-bind-acl.bash --all
```

## DNS Sec

* Add `dnssec-policy nsec3;` and `inline-signing yes;` under zone
  in [files/etc/bind/named.conf.local](named.conf.local)
* `rndc reload` / `rndc reconfig` on server to regenerate keys.
* Extract DS record by using `dnssec-dsfromkey /var/lib/bind/keys/<Kdomain>.key` and add to
  parent-zone.
* Wait for parent zones to have published updated zonefiles.
* Verify everything is signed and fine with a trust from root to your nameserver, forexample
  by [https://dnsviz.net/](https://dnsviz.net/)
