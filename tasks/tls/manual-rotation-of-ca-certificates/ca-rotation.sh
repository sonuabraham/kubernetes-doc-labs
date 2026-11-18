#!/usr/bin/env bash
# NOT from the docs: the page's steps, adapted to a THROWAWAY single-node minikube profile "ca-lab".
# One phase per call, so you can check the cluster in between:
#   ./ca-rotation.sh start | backup | 1-new-ca | 2-kcm-bundle | 4-restart-pods | 5-apiserver-bundle | 7-user-cert | 8-cp-kubeconfigs |
#                   9a-kubelet-bundle | 9b-new-serving-certs | 10-cluster-info | 11-verify | 12-drop-old-ca (continues into 12b-kubelet) | delete
# minikube paths: certs in /var/lib/minikube/certs, kubeconfigs in /etc/kubernetes, kubelet config /var/lib/kubelet/config.yaml.
# Your ~/.minikube files are never changed: the lab uses its own kubeconfig ./kubeconfig-ca-lab (CA embedded).
set -euo pipefail
cd "$(dirname "$0")"
P=ca-lab; C=/var/lib/minikube/certs; W=work; mkdir -p $W
export KUBECONFIG=$PWD/kubeconfig-ca-lab
nodesh() { minikube -p $P ssh -- "$@"; }
get()    { nodesh "sudo cat $1" | cat > "$2"; }               # node file -> local file
put()    { minikube -p $P cp "$1" "$2"; }                      # local file -> node file
kc()     { kubectl --request-timeout=10s "$@"; }
wait_api() { until kc get --raw /readyz >/dev/null 2>&1; do :; done; echo "API ready"; }
edit_manifest() {  # $1 = component, $2 = python code working on dict m (container = c)
  get /etc/kubernetes/manifests/$1.yaml $W/$1.yaml
  python3 - $W/$1.yaml "$2" <<'PY'
import sys, yaml
p, code = sys.argv[1], sys.argv[2]
m = yaml.safe_load(open(p)); c = m["spec"]["containers"][0]
def setflag(name, value):
    c["command"] = [a for a in c["command"] if not a.startswith(f"--{name}=")] + [f"--{name}={value}"]
exec(code)
import time; m["metadata"].setdefault("annotations", {})["lab/ca-rotation"] = str(time.time())   # force a restart
yaml.safe_dump(m, open(p, "w"), sort_keys=False)
PY
  put $W/$1.yaml /etc/kubernetes/manifests/$1.yaml
}
sign() {  # $1 name, $2 subj, $3 CA prefix (local), $4 extfile content ; reuses the node's key for $1
  get $C/$1.key $W/$1.key
  openssl req -new -key $W/$1.key -subj "$2" -out $W/$1.csr 2>/dev/null
  printf '%s\n' "$4" > $W/$1.ext
  openssl x509 -req -in $W/$1.csr -CA $W/$3.crt -CAkey $W/$3.key -CAcreateserial -days 365 -extfile $W/$1.ext -out $W/$1.crt 2>/dev/null
  put $W/$1.crt $C/$1.crt
}

case "${1:-}" in
start)
  KUBECONFIG= minikube stop || true
  KUBECONFIG= minikube start -p $P --memory 2200 --cpus 2 --kubernetes-version v1.37.0     # writes ~/.kube/config, not the lab file
  KUBECONFIG= kubectl config view --minify --flatten --context $P | cat > kubeconfig-ca-lab
  kc get nodes ;;

backup)  # docs caution: back up the certificate directory and configuration files
  nodesh "sudo rm -rf /root/ca-backup && sudo mkdir -p /root/ca-backup && sudo cp -a $C /etc/kubernetes /var/lib/kubelet/config.yaml /root/ca-backup/ && sudo ls /root/ca-backup" ;;

1-new-ca)  # step 1: new CA + new front-proxy CA next to the old ones; bundles = old + new
  for ca in ca front-proxy-ca; do
    openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj "/CN=new-$ca" -keyout $W/new-$ca.key -out $W/new-$ca.crt \
      -addext "keyUsage=critical,digitalSignature,keyEncipherment,keyCertSign" 2>/dev/null
    get $C/$ca.crt $W/old-$ca.crt
    cat $W/old-$ca.crt $W/new-$ca.crt > $W/$ca-bundle.crt
    put $W/new-$ca.crt $C/new-$ca.crt; put $W/new-$ca.key $C/new-$ca.key; put $W/$ca-bundle.crt $C/$ca-bundle.crt
  done
  nodesh "ls $C | grep -E 'new-|bundle'" ;;

2-kcm-bundle)  # step 2-3: --root-ca-file = bundle (client-ca-file / cluster-signing-cert-file must NOT be bundles)
  edit_manifest kube-controller-manager "setflag('root-ca-file', '$C/ca-bundle.crt')"
  until [ "$(kc -n default get cm kube-root-ca.crt -o jsonpath='{.data.ca\.crt}' 2>/dev/null | grep -c BEGIN)" = 2 ]; do :; done
  echo "kube-root-ca.crt now has $(kc -n default get cm kube-root-ca.crt -o jsonpath='{.data.ca\.crt}' | grep -c BEGIN) certificates" ;;

4-restart-pods)  # step 4 (+ the docs' annotate loop): Pods re-read kube-root-ca.crt
  for ns in $(kc get namespace -o jsonpath='{.items[*].metadata.name}'); do
    for name in $(kc get deployments -n $ns -o jsonpath='{.items[*].metadata.name}'); do
      kc patch deployment -n $ns $name -p '{"spec":{"template":{"metadata":{"annotations":{"ca-rotation": "1"}}}}}'; done
    for name in $(kc get daemonset -n $ns -o jsonpath='{.items[*].metadata.name}'); do
      kc patch daemonset -n $ns $name -p '{"spec":{"template":{"metadata":{"annotations":{"ca-rotation": "1"}}}}}'; done
  done
  kc -n kube-system rollout status deploy/coredns; kc -n kube-system rollout status ds/kube-proxy ;;

5-apiserver-bundle)  # step 5: kube-apiserver trusts client certs of both CAs (+ front-proxy bundle for aggregation)
  edit_manifest kube-apiserver "setflag('client-ca-file', '$C/ca-bundle.crt'); setflag('requestheader-client-ca-file', '$C/front-proxy-ca-bundle.crt')"
  wait_api ;;

7-user-cert)  # step 7: a new admin client cert from the NEW CA; kubeconfig CA data = old + new
  openssl req -newkey rsa:2048 -nodes -subj "/O=system:masters/CN=minikube-user" -keyout $W/admin.key -out $W/admin.csr 2>/dev/null
  openssl x509 -req -in $W/admin.csr -CA $W/new-ca.crt -CAkey $W/new-ca.key -CAcreateserial -days 365 -out $W/admin.crt 2>/dev/null
  kubectl config set-credentials ca-lab --client-certificate=$W/admin.crt --client-key=$W/admin.key --embed-certs=true
  kubectl config set-cluster ca-lab --certificate-authority=$W/ca-bundle.crt --embed-certs=true
  kc auth whoami ;;

8-cp-kubeconfigs)  # NOT an explicit docs step, but needed before 9b: the control plane's own kubeconfigs must trust the
                   # bundle, or kube-scheduler / kube-controller-manager reject the new apiserver cert (x509: unknown authority)
  for k in controller-manager scheduler admin super-admin; do
    get /etc/kubernetes/$k.conf $W/$k.conf
    kubectl --kubeconfig $W/$k.conf config set-cluster "$(kubectl --kubeconfig $W/$k.conf config view -o jsonpath='{.clusters[0].name}')" \
      --certificate-authority=$W/ca-bundle.crt --embed-certs=true >/dev/null
    put $W/$k.conf /etc/kubernetes/$k.conf
  done
  edit_manifest kube-controller-manager "pass"; edit_manifest kube-scheduler "pass"
  wait_api ;;

9a-kubelet-bundle)  # step 9 (kubelet): clientCAFile and kubelet.conf CA = bundle
  nodesh "sudo sed -i 's#clientCAFile: .*#clientCAFile: $C/ca-bundle.crt#' /var/lib/kubelet/config.yaml && sudo grep clientCAFile /var/lib/kubelet/config.yaml"
  get /etc/kubernetes/kubelet.conf $W/kubelet.conf
  kubectl --kubeconfig $W/kubelet.conf config set-cluster "$(kubectl --kubeconfig $W/kubelet.conf config view -o jsonpath='{.clusters[0].name}')" \
    --certificate-authority=$W/ca-bundle.crt --embed-certs=true >/dev/null
  put $W/kubelet.conf /etc/kubernetes/kubelet.conf
  nodesh "sudo systemctl restart kubelet"; wait_api; kc get nodes ;;

9b-new-serving-certs)  # step 9 (API server): apiserver.crt, apiserver-kubelet-client.crt, front-proxy-client.crt from the new CAs
  SANS=$(nodesh "sudo openssl x509 -in $C/apiserver.crt -noout -ext subjectAltName" | tail -1 | tr -d ' \r' | sed 's/IPAddress/IP/g')
  sign apiserver "/CN=minikube" new-ca "subjectAltName=$SANS
extendedKeyUsage=serverAuth"
  sign apiserver-kubelet-client "/O=kubeadm:cluster-admins/CN=kube-apiserver-kubelet-client" new-ca "extendedKeyUsage=clientAuth"
  sign front-proxy-client "/CN=front-proxy-client" new-front-proxy-ca "extendedKeyUsage=clientAuth"
  edit_manifest kube-apiserver "pass"
  wait_api
  echo | openssl s_client -connect $(minikube -p $P ip):8443 2>/dev/null | openssl x509 -noout -issuer ;;

10-cluster-info)  # step 10: bootstrap tokens - kube-public/cluster-info carries the CA (here: the bundle)
  base64_encoded_ca="$(base64 -w0 $W/ca-bundle.crt)"
  kc get cm/cluster-info --namespace kube-public -o yaml | \
      /bin/sed "s/\(certificate-authority-data:\).*/\1 ${base64_encoded_ca}/" | \
      kc apply -f - ;;

11-verify)  # step 11: no TLS errors
  kc get nodes; kc -n kube-system get pods
  kc run ca-check --image=busybox:1.36 --restart=Never --rm -i --command -- true >/dev/null 2>&1 && echo "Pod create/schedule OK"
  kc logs -n kube-system -l k8s-app=kube-dns --tail=200 | grep -ci 'x509\|tls' || true
  nodesh "sudo journalctl -u kubelet --since -5min --no-pager | grep -ci 'x509' || true" ;;

12-drop-old-ca)  # step 12: only the new CA everywhere. ca.crt/ca.key := new CA, so every flag can point to ca.crt again.
  put $W/new-ca.crt $C/ca.crt; put $W/new-ca.key $C/ca.key
  put $W/new-front-proxy-ca.crt $C/front-proxy-ca.crt; put $W/new-front-proxy-ca.key $C/front-proxy-ca.key
  # kubeconfigs of the control plane carry client certs from the OLD CA: re-sign them with kubeadm (it signs with ca.crt/ca.key)
  nodesh "sudo /var/lib/minikube/binaries/v1.37.0/kubeadm kubeconfig user --client-name system:kube-controller-manager --config /var/tmp/minikube/kubeadm.yaml 2>/dev/null | sudo tee /etc/kubernetes/controller-manager.conf >/dev/null"
  nodesh "sudo /var/lib/minikube/binaries/v1.37.0/kubeadm kubeconfig user --client-name system:kube-scheduler --config /var/tmp/minikube/kubeadm.yaml 2>/dev/null | sudo tee /etc/kubernetes/scheduler.conf >/dev/null"
  nodesh "sudo grep -c client-certificate-data /etc/kubernetes/controller-manager.conf /etc/kubernetes/scheduler.conf"
  edit_manifest kube-apiserver "setflag('client-ca-file', '$C/ca.crt'); setflag('requestheader-client-ca-file', '$C/front-proxy-ca.crt')"
  wait_api
  edit_manifest kube-controller-manager "setflag('root-ca-file', '$C/ca.crt')"
  edit_manifest kube-scheduler "pass"
  # admin.conf / super-admin.conf also hold old-CA client certs (kubeadm token create below uses admin.conf)
  nodesh "sudo /var/lib/minikube/binaries/v1.37.0/kubeadm kubeconfig user --client-name kubernetes-admin --org kubeadm:cluster-admins --config /var/tmp/minikube/kubeadm.yaml 2>/dev/null | sudo tee /etc/kubernetes/admin.conf >/dev/null"
  nodesh "sudo /var/lib/minikube/binaries/v1.37.0/kubeadm kubeconfig user --client-name kubernetes-super-admin --org system:masters --config /var/tmp/minikube/kubeadm.yaml 2>/dev/null | sudo tee /etc/kubernetes/super-admin.conf >/dev/null" ;&

12b-kubelet)  # (second half of step 12) kubelet: CA = new only; its client cert is from the old CA -> TLS bootstrap a new one
  nodesh "sudo sed -i 's#clientCAFile: .*#clientCAFile: $C/ca.crt#' /var/lib/kubelet/config.yaml"
  TOKEN=$(nodesh "sudo /var/lib/minikube/binaries/v1.37.0/kubeadm token create --ttl 1h --kubeconfig /etc/kubernetes/admin.conf" | tr -d '\r')
  SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
  B=$W/bootstrap-kubelet.conf; rm -f $B
  kubectl --kubeconfig $B config set-cluster bootstrap --server=$SERVER --certificate-authority=$W/new-ca.crt --embed-certs=true >/dev/null
  kubectl --kubeconfig $B config set-credentials kubelet-bootstrap --token=$TOKEN >/dev/null
  kubectl --kubeconfig $B config set-context bootstrap --cluster=bootstrap --user=kubelet-bootstrap >/dev/null
  kubectl --kubeconfig $B config use-context bootstrap >/dev/null
  put $B /etc/kubernetes/bootstrap-kubelet.conf
  nodesh "sudo systemctl stop kubelet && sudo rm -f /etc/kubernetes/kubelet.conf && sudo sh -c 'rm -f /var/lib/kubelet/pki/kubelet-client-*' && sudo systemctl start kubelet"
  kubectl config set-cluster ca-lab --certificate-authority=$W/new-ca.crt --embed-certs=true
  wait_api; until kc get nodes 2>/dev/null | grep -q ' Ready'; do :; done; kc get nodes
  base64_encoded_ca="$(base64 -w0 $W/new-ca.crt)"
  kc get cm/cluster-info --namespace kube-public -o yaml | /bin/sed "s/\(certificate-authority-data:\).*/\1 ${base64_encoded_ca}/" | kc apply -f -
  until [ "$(kc -n default get cm kube-root-ca.crt -o jsonpath='{.data.ca\.crt}' | grep -c BEGIN)" = 1 ]; do :; done
  echo "kube-root-ca.crt: $(kc -n default get cm kube-root-ca.crt -o jsonpath='{.data.ca\.crt}' | openssl x509 -noout -subject)" ;;

delete)   # unset the lab KUBECONFIG first, or minikube writes the default context into the lab file
  export KUBECONFIG=
  minikube delete -p $P; rm -rf $W kubeconfig-ca-lab
  minikube start; kubectl config use-context minikube ;;
*) sed -n '2,8p' "$0"; exit 1 ;;
esac
