#!/usr/bin/env bash
# Remove apiserver B and switch the feature back off on apiserver A.
P=arch-lab
minikube ssh -p $P -n arch-lab-m02 -- "sudo rm -f /etc/kubernetes/manifests/kube-apiserver-peer.yaml; sudo rm -rf /var/lib/minikube/peer-certs /var/lib/minikube/peer /tmp/certs.b64"
minikube ssh -p $P -n arch-lab -- "sudo sed -i '/UnknownVersionInteroperabilityProxy/d; /--peer-ca-file=/d' /etc/kubernetes/manifests/kube-apiserver.yaml"
echo "apiserver B removed; apiserver A restarts without the feature (wait ~40s)"
