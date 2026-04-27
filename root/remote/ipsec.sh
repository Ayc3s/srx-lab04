#!/bin/bash -e
cp /root/ipsec/ca_cert.pem     /etc/swanctl/x509ca/
cp /root/ipsec/remote_cert.pem /etc/swanctl/x509/
cp /root/ipsec/remote_key.pem  /etc/swanctl/private/
cp /root/ipsec/swanctl.conf    /etc/swanctl/swanctl.conf
/usr/lib/ipsec/charon &
sleep 2
swanctl --load-all
