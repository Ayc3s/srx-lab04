#!/bin/bash -e

if ip link | grep -q eth1; then
  echo "It's a server"
else
  IP=$( ip addr show eth0 | awk '/inet / {print $2}' | cut -d/ -f1 )
  if [[ "$IP" =~ 10.0.0. ]]; then
    echo "It's the remote laptop"
  else
    echo "It's a client"
    # shellcheck disable=SC2001
    IP_SERVER=$( echo "$IP" | sed -e 's/[0-9]*$/2/' )
    ip route del default
    ip route add default via "$IP_SERVER"
  fi
fi

if [ "$RUN" ]; then
  echo "Running $RUN"
  /root/"$RUN"
fi

# Wait forever
tail -f /dev/null