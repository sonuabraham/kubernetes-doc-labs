#!/usr/bin/env bash
# Build a 2-API-server control plane on the arch-lab profile (lab only!):
#   apiserver A = the existing one on arch-lab     (192.168.67.2:8443), default APIs
#   apiserver B = a NEW static pod on arch-lab-m02 (192.168.67.3:8443) with
#                 --runtime-config=api/all=true, i.e. it ALSO serves every
#                 alpha/beta API version - like a newer server during an upgrade.
# Both get --feature-gates=UnknownVersionInteroperabilityProxy=true and --peer-ca-file.
# B shares A's etcd (192.168.67.2:2379) and A's certificates; it gets its own
# serving certificate (SAN 192.168.67.3) signed by the cluster CA so A can verify it.
set -euo pipefail
P=arch-lab; CP=arch-lab; W=arch-lab-m02
CP_IP=$(kubectl get node $CP -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
W_IP=$(kubectl get node $W -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
TMP=$(mktemp -d)
echo "1) copy certificates + manifest from $CP"
minikube ssh -p $P -n $CP -- "sudo tar czf - -C /var/lib/minikube certs | base64 -w0" > $TMP/certs.b64
minikube ssh -p $P -n $CP -- "sudo cat /etc/kubernetes/manifests/kube-apiserver.yaml" > $TMP/kube-apiserver.yaml
minikube cp -p $P $TMP/certs.b64 $W:/tmp/certs.b64 >/dev/null
echo "2) unpack certs on $W into /var/lib/minikube/peer-certs and make a serving cert for $W_IP"
minikube ssh -p $P -n $W -- "sudo mkdir -p /var/lib/minikube/peer && base64 -d /tmp/certs.b64 | sudo tar xzf - -C /var/lib/minikube/peer && sudo rm -rf /var/lib/minikube/peer-certs && sudo mv /var/lib/minikube/peer/certs /var/lib/minikube/peer-certs && cd /var/lib/minikube/peer-certs && \
  sudo openssl req -new -newkey rsa:2048 -nodes -keyout peer-apiserver.key -subj /CN=kube-apiserver-peer -out peer.csr 2>/dev/null && \
  printf 'subjectAltName=IP:$W_IP,IP:10.96.0.1,IP:127.0.0.1,DNS:localhost,DNS:kubernetes,DNS:kubernetes.default,DNS:kubernetes.default.svc,DNS:kubernetes.default.svc.cluster.local\nextendedKeyUsage=serverAuth\n' | sudo tee ext.cnf >/dev/null && \
  sudo openssl x509 -req -in peer.csr -CA ca.crt -CAkey ca.key -CAcreateserial -days 30 -extfile ext.cnf -out peer-apiserver.crt 2>/dev/null && echo cert ok"
echo "3) write the static pod manifest for apiserver B on $W"
sed -e "s#name: kube-apiserver\$#name: kube-apiserver-peer#" \
    -e "s#/var/lib/minikube/certs#/var/lib/minikube/peer-certs#g" \
    -e "s#--advertise-address=$CP_IP#--advertise-address=$W_IP#" \
    -e "s#--etcd-servers=https://127.0.0.1:2379#--etcd-servers=https://$CP_IP:2379#" \
    -e "s#host: $CP_IP#host: $W_IP#g" \
    -e "s#peer-certs/apiserver.crt#peer-certs/peer-apiserver.crt#; s#peer-certs/apiserver.key#peer-certs/peer-apiserver.key#" \
    -e "s#    - --allow-privileged=true#    - --allow-privileged=true\n    - --feature-gates=UnknownVersionInteroperabilityProxy=true\n    - --peer-ca-file=/var/lib/minikube/peer-certs/ca.crt\n    - --runtime-config=api/all=true#" \
    $TMP/kube-apiserver.yaml > $TMP/kube-apiserver-peer.yaml
minikube cp -p $P $TMP/kube-apiserver-peer.yaml $W:/tmp/kube-apiserver-peer.yaml >/dev/null
minikube ssh -p $P -n $W -- "sudo cp /tmp/kube-apiserver-peer.yaml /etc/kubernetes/manifests/kube-apiserver-peer.yaml"
echo "4) enable the feature on apiserver A ($CP)"
minikube ssh -p $P -n $CP -- "sudo grep -q UnknownVersionInteroperabilityProxy /etc/kubernetes/manifests/kube-apiserver.yaml || sudo sed -i 's#    - --allow-privileged=true#    - --allow-privileged=true\n    - --feature-gates=UnknownVersionInteroperabilityProxy=true\n    - --peer-ca-file=/var/lib/minikube/certs/ca.crt#' /etc/kubernetes/manifests/kube-apiserver.yaml"
rm -rf $TMP
echo "5) waiting for both API servers (up to 3 min)..."
for i in $(seq 60); do
  n=$(kubectl -n kube-system get lease -l apiserver.kubernetes.io/identity=kube-apiserver --no-headers 2>/dev/null | wc -l)
  [ "$n" -ge 2 ] && curl -sk -m2 https://$W_IP:8443/readyz >/dev/null && break; sleep 3; done
kubectl -n kube-system get lease -l apiserver.kubernetes.io/identity=kube-apiserver -L kubernetes.io/hostname
