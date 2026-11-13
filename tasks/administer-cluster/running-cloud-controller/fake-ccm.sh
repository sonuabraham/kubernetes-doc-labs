#!/usr/bin/env bash
# A toy "cloud-controller-manager" for the lab cloud "fakecloud" - what a real CCM does, in a kubectl loop:
#  node controller:    for every node still tainted node.cloudprovider.kubernetes.io/uninitialized, look the node up
#                      in "the cloud" (here: invent it), set spec.providerID, region/zone/instance-type labels,
#                      then REMOVE the taint so workloads can schedule.
#  service controller: for every Service type=LoadBalancer without an address, "create a load balancer" and write
#                      its IP into status.loadBalancer.ingress (IPs from 192.168.184.200+; reachable is not the point).
#   ./fake-ccm.sh start|stop     (CTX=ccm-lab)    log: ./fake-ccm.log
cd "$(dirname "$0")" || exit 1
CTX=${CTX:-ccm-lab}; PIDF=.fake-ccm-$CTX.pid
k(){ kubectl --context "$CTX" "$@"; }
if [ "$1" = stop ]; then
  [ -f "$PIDF" ] && kill "$(cat "$PIDF")" 2>/dev/null
  rm -f -- "$PIDF"; echo stopped; exit 0
fi
loop(){ n=200; while true; do
  for node in $(k get nodes -o jsonpath='{range .items[?(@.spec.taints[*].key=="node.cloudprovider.kubernetes.io/uninitialized")]}{.metadata.name}{" "}{end}'); do
    k patch node "$node" --type=merge -p "{\"spec\":{\"providerID\":\"fakecloud://eu-lab-1a/$node\"},\"metadata\":{\"labels\":{
      \"topology.kubernetes.io/region\":\"eu-lab-1\",\"topology.kubernetes.io/zone\":\"eu-lab-1a\",\"node.kubernetes.io/instance-type\":\"fake.large\"}}}" >/dev/null
    k taint node "$node" node.cloudprovider.kubernetes.io/uninitialized:NoSchedule- >/dev/null
    echo "$(date +%T) node controller: initialized $node (providerID fakecloud://eu-lab-1a/$node)"
  done
  for svc in $(k get svc -A -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.namespace}/{.metadata.name}={.status.loadBalancer.ingress[0].ip}{" "}{end}'); do
    [ -n "${svc#*=}" ] && continue
    ns=${svc%%/*}; name=${svc#*/}; name=${name%=}
    k -n "$ns" patch svc "$name" --subresource=status --type=merge -p "{\"status\":{\"loadBalancer\":{\"ingress\":[{\"ip\":\"192.168.184.$n\"}]}}}" >/dev/null
    echo "$(date +%T) service controller: load balancer 192.168.184.$n for $ns/$name"; n=$((n+1))
  done
  sleep 3; done; }
loop >> fake-ccm.log 2>&1 &
echo $! > "$PIDF"; disown
echo "fake-ccm started (pid $(cat "$PIDF"))"
