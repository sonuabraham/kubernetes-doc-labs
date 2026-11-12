#!/usr/bin/env bash
# Runs ON THE NODE as root (cni-by-hand.sh copies it there). Does what containerd does for every Pod sandbox:
#   create a network namespace, run CNI plugins (loopback, then bridge + host-local IPAM) with
#   CNI_COMMAND=ADD and the network config on stdin, CHECK it, DEL it, clean up.
# Own bridge (cni-hand0) and subnet 10.99.0.0/24, so real Pod networking is untouched.
set -u
NS=cni-hand
export CNI_PATH=/opt/cni/bin CNI_NETNS=/var/run/netns/$NS CNI_CONTAINERID=hand-1 CNI_IFNAME=eth0
CONF='{"cniVersion":"1.0.0","name":"by-hand","type":"bridge","bridge":"cni-hand0","isGateway":true,
       "ipam":{"type":"host-local","subnet":"10.99.0.0/24","dataDir":"/run/cni-hand-ipam"}}'
LO='{"cniVersion":"1.0.0","name":"lo","type":"loopback"}'

ip netns add $NS
echo "== a fresh netns has only a DOWN loopback"
ip netns exec $NS ip -o link | awk '{print "   ",$2,$9}'

echo "== CNI_COMMAND=ADD  loopback"
echo "$LO" | CNI_COMMAND=ADD CNI_IFNAME=lo /opt/cni/bin/loopback | tr -d '\n '; echo

echo "== CNI_COMMAND=ADD  bridge (+ host-local IPAM)"
RESULT=$(echo "$CONF" | CNI_COMMAND=ADD /opt/cni/bin/bridge)
echo "$RESULT" | python3 -c 'import json,sys;r=json.load(sys.stdin);print("    cniVersion:",r["cniVersion"],"ips:",[i["address"] for i in r["ips"]],"interfaces:",[i["name"] for i in r["interfaces"]])'

echo "== inside the netns now"
ip netns exec $NS ip -o -4 addr | awk '{print "   ",$2,$4}'
ip netns exec $NS ping -c1 -W1 10.99.0.1 | grep -E "bytes from" | sed 's/^/    /'

echo "== IPAM bookkeeping (host-local): one file per allocated IP, containing the container ID"
for f in /run/cni-hand-ipam/by-hand/10.*; do echo "    $(basename $f) -> $(head -1 $f)"; done

echo "== CNI_COMMAND=CHECK without prevResult, then with it (the runtime caches ADD's result for this)"
echo "$CONF" | CNI_COMMAND=CHECK /opt/cni/bin/bridge | tr -d '\n' | sed 's/^/    /'; echo
python3 -c 'import json,sys;c=json.loads(sys.argv[1]);c["prevResult"]=json.loads(sys.argv[2]);print(json.dumps(c))' "$CONF" "$RESULT" |
  CNI_COMMAND=CHECK /opt/cni/bin/bridge && echo "    exit 0: network is as ADD left it"

echo "== CNI_COMMAND=DEL"
echo "$CONF" | CNI_COMMAND=DEL /opt/cni/bin/bridge && echo "    exit 0"
if ls /run/cni-hand-ipam/by-hand/ | grep -q '^10\.'; then echo "    still allocated!"; else echo "    IP released (only $(ls /run/cni-hand-ipam/by-hand/ | tr '\n' ' ')left)"; fi

ip netns del $NS; ip link del cni-hand0; rm -rf /run/cni-hand-ipam
