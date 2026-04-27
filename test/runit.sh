#!/bin/bash -e

test_ping() {
  CONTAINER=$1
  shift
  REMOTES="$@"
  for r in $REMOTES; do
    if docker exec "$CONTAINER" /bin/bash -c "ping -i .1 -c 3 $r -q || echo 'NoPing'" | grep -q NoPing; then
      echo "Ping failed from $CONTAINER to $r"
      exit 1
    fi
    echo "Ping OK from $CONTAINER to $r"
  done
}

start_vpn() {
  VPN=$1
  echo "*** Starting docker for $VPN"
  RUN=$VPN docker compose up -d --wait
  sleep 5
}

test_vpn() {
  test_ping MainS 10.0.2.2 10.0.2.10 10.0.2.11
  test_ping MainC1 10.0.2.2 10.0.2.10 10.0.2.11
  test_ping MainC2 10.0.2.2 10.0.2.10 10.0.2.11
  test_ping FarS 10.0.1.2 10.0.1.10 10.0.1.11
  test_ping FarC1 10.0.1.2 10.0.1.10 10.0.1.11
  test_ping FarC2 10.0.1.2 10.0.1.10 10.0.1.11
  test_ping Remote 10.0.1.2 10.0.1.10 10.0.1.11 10.0.2.2 10.0.2.10 10.0.2.11
}

cleanup() {
  docker compose down -t 1
}

trap cleanup EXIT

TESTS=${1:-openvpn wireguard ipsec}

cleanup
for t in $TESTS; do
  start_vpn "$t.sh"
  test_vpn
  cleanup
done
