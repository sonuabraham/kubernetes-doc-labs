#!/usr/bin/env bash
C="--context arch-lab"
kubectl $C delete namespace ccm-demo --ignore-not-found
kubectl $C delete clusterrolebinding cloud-controller-manager --ignore-not-found
kubectl $C delete clusterrole cloud-controller-manager --ignore-not-found
kubectl $C delete serviceaccount cloud-controller-manager -n kube-system --ignore-not-found
for n in arch-lab arch-lab-m02; do
  kubectl $C label node $n topology.kubernetes.io/region- topology.kubernetes.io/zone- node.kubernetes.io/instance-type- >/dev/null 2>&1
  kubectl $C taint node $n node.cloudprovider.kubernetes.io/uninitialized- >/dev/null 2>&1
done
echo "note: spec.providerID cannot be removed once set; recreate the profile to reset it (minikube delete -p arch-lab)"
