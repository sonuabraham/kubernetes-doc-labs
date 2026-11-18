#!/usr/bin/env bash
# NOT from the docs: watch kubelet client-certificate rotation on a THROWAWAY profile "rot-lab".
#   ./rot-lab.sh start      stop default minikube; start rot-lab with kube-controller-manager --cluster-signing-duration=10m
#   ./rot-lab.sh bootstrap  give the kubelet a bootstrap kubeconfig (bootstrap token), delete its client cert, restart it
#                           -> TLS bootstrap: CSR, auto-approval, a 10-minute certificate
#   ./rot-lab.sh status     current cert dates + CSRs
#   ./rot-lab.sh delete     delete rot-lab, start the default minikube
set -euo pipefail
P=rot-lab; K="kubectl --context $P"
nodesh() { minikube -p $P ssh -- "$@"; }
case "${1:-}" in
start)
  minikube stop || true
  minikube start -p $P --memory 2200 --cpus 2 --kubernetes-version v1.37.0 \
    --extra-config=controller-manager.cluster-signing-duration=10m
  kubectl config use-context $P ;;
bootstrap)
  KA=/var/lib/minikube/binaries/v1.37.0/kubeadm
  TOKEN=$(nodesh "sudo $KA token create --ttl 1h --kubeconfig /etc/kubernetes/admin.conf" | tr -d '\r')
  SERVER=$(nodesh "sudo grep server: /etc/kubernetes/kubelet.conf" | awk '{print $2}' | tr -d '\r')
  F=$(mktemp); cat > $F <<KC
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority: /var/lib/minikube/certs/ca.crt
    server: $SERVER
  name: bootstrap
contexts:
- context: {cluster: bootstrap, user: kubelet-bootstrap}
  name: bootstrap
current-context: bootstrap
users:
- name: kubelet-bootstrap
  user: {token: $TOKEN}
KC
  minikube -p $P cp $F /etc/kubernetes/bootstrap-kubelet.conf; rm -f $F    # (minikube ssh does not forward stdin)
  nodesh "sudo systemctl stop kubelet && sudo sh -c 'rm -f /var/lib/kubelet/pki/kubelet-client-*' && sudo systemctl start kubelet"
  echo "kubelet restarted with bootstrap token ${TOKEN%%.*}.<secret>" ;;
status)
  nodesh "sudo openssl x509 -in /var/lib/kubelet/pki/kubelet-client-current.pem -noout -subject -startdate -enddate; sudo ls -l /var/lib/kubelet/pki/ | grep client"
  $K get csr ;;
delete)
  minikube delete -p $P; minikube start ;;
*) echo "usage: $0 start|bootstrap|status|delete"; exit 1 ;;
esac
