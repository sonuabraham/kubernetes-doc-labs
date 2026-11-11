#!/usr/bin/env bash
# A pretend cloud-controller-manager for the fictional cloud "fakecloud".
# Runs every 3s and impersonates system:serviceaccount:kube-system:cloud-controller-manager,
# so every call is checked against the docs' ClusterRole.
#
#  Node controller    : for nodes without spec.providerID -> set providerID "fakecloud://<node>",
#                       add region/zone/instance-type labels, remove the
#                       node.cloudprovider.kubernetes.io/uninitialized taint
#  Service controller : for type=LoadBalancer Services without an ingress IP ->
#                       "provision" a load balancer (IP from 203.0.113.0/24, a
#                       documentation range) and write it to status.loadBalancer
#  (Route controller  : nothing to do - kindnet already routes pod CIDRs)
AS="--as=system:serviceaccount:kube-system:cloud-controller-manager"
# For the status PATCH we call the API directly with the SA's own token:
# "kubectl patch --subresource=status" first GETs services/status, and the docs'
# ClusterRole grants only patch/update on services/status (no get) - a real CCM
# (client-go) just sends the PATCH.
SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
CA=$(kubectl config view --minify --raw -o jsonpath='{.clusters[0].cluster.certificate-authority}')
TOKEN=$(kubectl create token cloud-controller-manager -n kube-system --duration=2h)
echo "fake-ccm running as system:serviceaccount:kube-system:cloud-controller-manager (Ctrl-C to stop)"
i=0
while true; do
  # ---- node controller ----
  for n in $(kubectl $AS get nodes -o json | jq -r '.items[] | select(.spec.providerID == null or .spec.providerID == "") | .metadata.name'); do
    zone=fakecloud-1$([ $((i % 2)) -eq 0 ] && echo a || echo b); i=$((i+1))
    kubectl $AS patch node "$n" --type=merge -p "{\"spec\":{\"providerID\":\"fakecloud://$n\"},\"metadata\":{\"labels\":{\"topology.kubernetes.io/region\":\"fakecloud-1\",\"topology.kubernetes.io/zone\":\"$zone\",\"node.kubernetes.io/instance-type\":\"fake.medium\"}}}" >/dev/null \
      && echo "$(date +%T) node-controller: initialized $n (providerID fakecloud://$n, zone $zone)"
  done
  for n in $(kubectl $AS get nodes -o json | jq -r '.items[] | select(any(.spec.taints[]?; .key=="node.cloudprovider.kubernetes.io/uninitialized")) | .metadata.name'); do
    kubectl $AS taint node "$n" node.cloudprovider.kubernetes.io/uninitialized- >/dev/null \
      && echo "$(date +%T) node-controller: removed uninitialized taint from $n"
  done
  # ---- service controller ----
  kubectl $AS get services -A -o json | jq -r '.items[] | select(.spec.type=="LoadBalancer" and (.status.loadBalancer.ingress // [] | length)==0) | "\(.metadata.namespace) \(.metadata.name)"' |
  while read -r ns name; do
    ip="203.0.113.$(( (RANDOM % 200) + 10 ))"
    code=$(curl -s -o /dev/null -w '%{http_code}' --cacert "$CA" -H "Authorization: Bearer $TOKEN" \
      -H 'Content-Type: application/merge-patch+json' -X PATCH \
      -d "{\"status\":{\"loadBalancer\":{\"ingress\":[{\"ip\":\"$ip\"}]}}}" \
      "$SERVER/api/v1/namespaces/$ns/services/$name/status")
    echo "$(date +%T) service-controller: provisioned LB $ip for $ns/$name (HTTP $code)"
  done
  sleep 3
done
