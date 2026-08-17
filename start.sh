#!/bin/sh
# nginx.conf proxies /ws to "relay" (the compose service name); in this
# all-in-one image the relay is local, so alias it
grep -q " relay$" /etc/hosts || echo "127.0.0.1 relay" >> /etc/hosts
# HOST=0.0.0.0 so the relay is reachable through the container port mapping
cd /opt/relay && HOST=0.0.0.0 node index.js &
nginx -g 'daemon off;'
