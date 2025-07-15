# fail2ban-jail.cf.readme.md

https://docker-mailserver.github.io/docker-mailserver/latest/config/security/fail2ban/#custom-files

fail2ban-jail.cf is copied to /etc/fail2ban/jail.d/user-jail.local with this
file, you can adjust the configuration of individual jails and their defaults.

Upstream: https://github.com/docker-mailserver/docker-mailserver/blob/master/config-examples/fail2ban-jail.cf

## Why sensitive

I have some custom knocking to avoid being blocked in certain scenarios.
