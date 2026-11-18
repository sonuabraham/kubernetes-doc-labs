#!/usr/bin/env bash
# NOT from the docs: the page's "Illustrative Reconfiguration Steps" on the throwaway profile svc-lab
# (../extend-service-ip-ranges/svc-lab.sh start): replace the default ServiceCIDR 10.96.0.0/28 by 10.100.0.0/24.
#   ./reconfigure.sh 2-services | 3-new-cidr | 4-delete-default | 5-recreate | 6-apiserver | 7-kubernetes-svc | 8-apiserver-cert | check
set -euo pipefail
cd "$(dirname "$0")"
P=svc-lab; NEW=10.100.0.0/24; K="kubectl --context $P"
nodesh() { minikube -p $P ssh -- "$@"; }
edit_manifest() {  # $1 component, $2 python (m = manifest, c = container, setflag)
  nodesh "sudo cat /etc/kubernetes/manifests/$1.yaml" | cat > /tmp/$$.yaml
  python3 - /tmp/$$.yaml "$2" <<'PY'
import sys, yaml, time
p, code = sys.argv[1], sys.argv[2]; m = yaml.safe_load(open(p)); c = m["spec"]["containers"][0]
def setflag(n, v): c["command"] = [a for a in c["command"] if not a.startswith(f"--{n}=")] + [f"--{n}={v}"]
exec(code); m["metadata"].setdefault("annotations", {})["lab/restart"] = str(time.time())
yaml.safe_dump(m, open(p, "w"), sort_keys=False)
PY
  minikube -p $P cp /tmp/$$.yaml /etc/kubernetes/manifests/$1.yaml; rm -f /tmp/$$.yaml
}
case "${1:-}" in
2-services)        # step 2: initial Services (plus the app behind one of them)
  $K create deployment web --image=nginx:1.27 --replicas=1
  $K expose deployment web --port=80
  $K rollout status deploy/web
  $K get svc -A ;;
3-new-cidr)        # step 3: temporary target range
  printf 'apiVersion: networking.k8s.io/v1\nkind: ServiceCIDR\nmetadata: {name: migration}\nspec: {cidrs: ["%s"]}\n' $NEW | $K apply -f -
  $K get servicecidr ;;
4-delete-default)  # step 4: mark the default ServiceCIDR for deletion (stays, but no new IPs from it)
  $K delete servicecidr kubernetes --wait=false
  $K get servicecidr kubernetes -o jsonpath='{.metadata.deletionTimestamp} {.status.conditions[0].reason}{"\n"}' ;;
5-recreate)        # step 5: recreate the Services -> IPs from the new range
  $K get svc web -o json | jq 'del(.spec.clusterIP, .spec.clusterIPs, .metadata.resourceVersion, .metadata.uid, .metadata.creationTimestamp, .status)' > /tmp/web-svc.json
  $K delete svc web; $K create -f /tmp/web-svc.json; rm /tmp/web-svc.json
  # kube-dns has a FIXED IP that every kubelet writes into resolv.conf: give it 10.100.0.10 and tell the kubelet
  $K -n kube-system get svc kube-dns -o json | jq '.spec.clusterIP = "10.100.0.10" | del(.spec.clusterIPs, .metadata.resourceVersion, .metadata.uid, .metadata.creationTimestamp, .status)' > /tmp/kube-dns.json
  $K -n kube-system delete svc kube-dns; $K create -f /tmp/kube-dns.json; rm /tmp/kube-dns.json
  nodesh "sudo sed -i 's/- 10.96.0.10/- 10.100.0.10/' /var/lib/kubelet/config.yaml && sudo systemctl restart kubelet"
  $K get svc -A ;;
6-apiserver)       # step 6: restart kube-apiserver (and kube-controller-manager) with the new range
  edit_manifest kube-apiserver "setflag('service-cluster-ip-range', '$NEW')"
  edit_manifest kube-controller-manager "setflag('service-cluster-ip-range', '$NEW')"
  until $K get --raw /readyz >/dev/null 2>&1; do :; done; echo "API ready" ;;
7-kubernetes-svc)  # step 7: delete kubernetes.default; the apiserver recreates it in the new range
  $K delete svc kubernetes
  until $K get svc kubernetes >/dev/null 2>&1; do :; done
  $K get svc kubernetes; $K get servicecidr ;;
8-apiserver-cert)  # NOT in the docs: the apiserver certificate needs the new kubernetes.default IP (10.100.0.1) as SAN,
                   # or every in-cluster client using KUBERNETES_SERVICE_HOST gets "x509: certificate is valid for 10.96.0.1 …"
  KA=/var/lib/minikube/binaries/v1.37.0/kubeadm
  nodesh "sudo sed -i 's#serviceSubnet: .*#serviceSubnet: $NEW#' /var/tmp/minikube/kubeadm.yaml && sudo mv /var/lib/minikube/certs/apiserver.crt /var/lib/minikube/certs/apiserver.crt.old && sudo mv /var/lib/minikube/certs/apiserver.key /var/lib/minikube/certs/apiserver.key.old && sudo $KA init phase certs apiserver --config /var/tmp/minikube/kubeadm.yaml"
  nodesh "sudo openssl x509 -in /var/lib/minikube/certs/apiserver.crt -noout -ext subjectAltName" | tail -1
  edit_manifest kube-apiserver "pass"
  until $K get --raw /readyz >/dev/null 2>&1; do :; done
  $K -n kube-system rollout restart deploy/coredns; $K -n kube-system rollout status deploy/coredns ;;
check)
  $K get servicecidr; $K get svc -A; $K get ipaddress ;;
*) sed -n '2,5p' "$0"; exit 1 ;;
esac
