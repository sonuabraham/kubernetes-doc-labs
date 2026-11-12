#!/usr/bin/env bash
# bandwidth.sh on|off [profile] - add/remove the CNI "bandwidth" plugin in kindnet's chain on the node.
#   on : backs up /etc/cni/net.d/10-kindnet.conflist to /var/lib/minikube/10-kindnet.conflist.orig,
#        appends {"type":"bandwidth","capabilities":{"bandwidth":true}}  (the binary is already in /opt/cni/bin)
#   off: restores the backup.
# Only Pods created AFTER the change get the new chain (CNI runs once, at sandbox creation).
set -euo pipefail
P=${2:-minikube}; F=/etc/cni/net.d/10-kindnet.conflist; B=/var/lib/minikube/10-kindnet.conflist.orig
case ${1:-} in
on)
  minikube ssh -p "$P" -- "sudo test -f $B || sudo cp $F $B"
  minikube ssh -p "$P" -- "sudo cat $B" | python3 -c '
import json,sys
c=json.loads(sys.stdin.read())
c["plugins"].append({"type":"bandwidth","capabilities":{"bandwidth":True}})
print(json.dumps(c,indent=2))' > /tmp/.kindnet-bw.conflist
  minikube cp -p "$P" /tmp/.kindnet-bw.conflist "$F" >/dev/null; rm -f /tmp/.kindnet-bw.conflist ;;
off)
  minikube ssh -p "$P" -- "sudo test -f $B && sudo cp $B $F && sudo rm -f $B" ;;
*) echo "usage: $0 on|off [profile]"; exit 1 ;;
esac
minikube ssh -p "$P" -- "sudo cat $F" | python3 -c 'import json,sys; print("chain:", [p["type"] for p in json.loads(sys.stdin.read())["plugins"]])'
