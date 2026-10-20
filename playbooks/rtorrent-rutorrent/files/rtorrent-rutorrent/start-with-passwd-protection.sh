#!/bin/sh
set -eu

# s6 v2 changes init-script attributes. Give it a container-local copy so it
# need not chown/chmod a read-only host bind; the managed sources stay read-only.
cp /usr/local/share/rtorrent/99-protect-htpasswd.sh /etc/cont-init.d/99-protect-htpasswd.sh
chmod 0755 /etc/cont-init.d/99-protect-htpasswd.sh
exec /init "$@"
