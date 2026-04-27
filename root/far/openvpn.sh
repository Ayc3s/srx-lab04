#!/bin/bash -e
if [ ! -d /dev/net ]; then
  mkdir -p /dev/net
  mknod /dev/net/tun c 10 200
  chmod 600 /dev/net/tun
fi

# A décommenter le moment voulu !!!

cd openvpn
openvpn --config client.conf
