#!/bin/bash -e
chmod 600 /root/wireguard/wg0.conf
wg-quick up /root/wireguard/wg0.conf
