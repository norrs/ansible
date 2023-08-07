# Bind playbook

## Nice docs

https://kb.isc.org/docs/dnssec-key-and-signing-policy

Don't need additional salt iterations on
`nsec3`: https://datatracker.ietf.org/doc/html/draft-ietf-dnsop-nsec3-guidance-10#section-2.4

## Updates

Always make sure to update serial in the zonefile. Format `<yyyy><mm><dd><nn>` where `nn` is change
number for that particular day.

## DNS Sec

* Add `dnssec-policy nsec3;` and `inline-signing yes;` under zone
  in [files/etc/bind/named.conf.local](named.conf.local)
* `rndc reload` / `rndc reconfig` on server to regenerate keys.
* Extract DS record by using `dnssec-dsfromkey /var/lib/bind/keys/<Kdomain>.key` and add to
  parent-zone.
* Wait for parent zones to have published updated zonefiles.
* Verify everything is signed and fine with a trust from root to your nameserver, forexample
  by [https://dnsviz.net/](https://dnsviz.net/)
