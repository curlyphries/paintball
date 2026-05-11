#!/bin/sh
cd /opt/relay && node index.js &
nginx -g 'daemon off;'
