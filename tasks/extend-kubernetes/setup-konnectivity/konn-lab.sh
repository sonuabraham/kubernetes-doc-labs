#!/usr/bin/env bash
# NOT from the docs: run the page's steps on a THROWAWAY minikube profile "konn-lab".
#   ./konn-lab.sh start       stop the default minikube (inotify limit), start konn-lab
#   ./konn-lab.sh configure   docs steps: kubeconfig for konnectivity-server, egress config, kube-apiserver flag + UDS volume,
#                             server static Pod, RBAC, agents
#   ./konn-lab.sh delete      delete konn-lab and start the default minikube again
# minikube differences: certs live in /var/lib/minikube/certs (not /etc/kubernetes/pki); the egress config file is put
# into the UDS directory /etc/kubernetes/konnectivity-server, which the docs mount into kube-apiserver anyway.
set -euo pipefail
cd "$(dirname "$0")"
P=konn-lab; K="kubectl --context $P"; T=$(mktemp -d); trap 'rm -rf $T' EXIT
nodesh() { minikube -p $P ssh -- "$@"; }

case "${1:-}" in
start)
  minikube stop || true
  minikube start -p $P --memory 2200 --cpus 2 --kubernetes-version v1.37.0
  kubectl config use-context $P ;;

configure)
  echo "## kubeconfig for konnectivity-server (docs openssl + kubectl config commands, minikube CA)"
  nodesh sudo cat /var/lib/minikube/certs/ca.key | cat > $T/ca.key
  nodesh sudo cat /var/lib/minikube/certs/ca.crt | cat > $T/ca.crt
  openssl req -subj "/CN=system:konnectivity-server" -new -newkey rsa:2048 -noenc -out $T/konnectivity.csr -keyout $T/konnectivity.key 2>/dev/null
  openssl x509 -req -in $T/konnectivity.csr -CA $T/ca.crt -CAkey $T/ca.key -CAcreateserial -out $T/konnectivity.crt -days 375 -sha256 2>/dev/null
  SERVER=$(kubectl config view --minify --context $P -o jsonpath='{.clusters..server}')    # docs: without --minify (see README)
  KC=$T/konnectivity-server.conf
  kubectl --kubeconfig $KC config set-credentials system:konnectivity-server --client-certificate $T/konnectivity.crt --client-key $T/konnectivity.key --embed-certs=true
  kubectl --kubeconfig $KC config set-cluster kubernetes --server "$SERVER" --certificate-authority $T/ca.crt --embed-certs=true
  kubectl --kubeconfig $KC config set-context system:konnectivity-server@kubernetes --cluster kubernetes --user system:konnectivity-server
  kubectl --kubeconfig $KC config use-context system:konnectivity-server@kubernetes
  nodesh "sudo mkdir -p /etc/kubernetes/konnectivity-server"
  minikube -p $P cp $KC /etc/kubernetes/konnectivity-server.conf
  minikube -p $P cp egress-selector-configuration.yaml /etc/kubernetes/konnectivity-server/egress-selector-configuration.yaml

  echo "## RBAC + konnectivity server (static Pod) first, so the UDS socket exists when kube-apiserver restarts"
  $K apply -f konnectivity-rbac.yaml
  minikube -p $P cp konnectivity-server-minikube.yaml /etc/kubernetes/manifests/konnectivity-server.yaml
  until nodesh "sudo test -S /etc/kubernetes/konnectivity-server/konnectivity-server.socket" 2>/dev/null; do :; done

  echo "## kube-apiserver: --egress-selector-config-file + konnectivity-uds volume (docs step 3 and 4)"
  nodesh sudo cat /etc/kubernetes/manifests/kube-apiserver.yaml | cat > $T/apiserver.yaml
  cp $T/apiserver.yaml ./kube-apiserver.yaml.orig
  python3 - $T/apiserver.yaml <<'PY'
import sys, yaml
p = sys.argv[1]; m = yaml.safe_load(open(p))
c = m["spec"]["containers"][0]
c["command"].append("--egress-selector-config-file=/etc/kubernetes/konnectivity-server/egress-selector-configuration.yaml")
c.setdefault("volumeMounts", []).append({"name": "konnectivity-uds", "mountPath": "/etc/kubernetes/konnectivity-server", "readOnly": False})
m["spec"].setdefault("volumes", []).append({"name": "konnectivity-uds", "hostPath": {"path": "/etc/kubernetes/konnectivity-server", "type": "DirectoryOrCreate"}})
yaml.safe_dump(m, open(p, "w"), sort_keys=False)
PY
  minikube -p $P cp $T/apiserver.yaml /etc/kubernetes/manifests/kube-apiserver.yaml
  timeout 30 tail -f /dev/null || true    # let the kubelet notice the new manifest
  until $K get --raw /readyz >/dev/null 2>&1; do :; done
  $K -n kube-system get pod -l component=kube-apiserver -o jsonpath='{.items[0].spec.containers[0].command}' | tr ',' '\n' | grep egress

  echo "## agents"
  NODE_IP=$(minikube -p $P ip)
  sed "s/NODE_IP/$NODE_IP/" konnectivity-agent-minikube.yaml | $K apply -f -
  $K -n kube-system rollout status ds/konnectivity-agent --timeout=180s ;;

delete)
  minikube delete -p $P; rm -f kube-apiserver.yaml.orig
  minikube start ;;
*) echo "usage: $0 start|configure|delete"; exit 1 ;;
esac
