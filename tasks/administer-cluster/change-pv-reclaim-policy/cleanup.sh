#!/usr/bin/env bash
# Set any of this lab's retained volumes back to Delete first, so deleting the claim also removes the PV and
# its directory on the node; then delete the demo objects. Released leftovers (no claim) are deleted directly.
for pv in $(kubectl get pv -o jsonpath='{range .items[?(@.spec.claimRef.namespace=="default")]}{.metadata.name}:{.spec.claimRef.name}{"\n"}{end}' | grep -E ':claim[0-9]' | cut -d: -f1); do
  kubectl patch pv "$pv" -p '{"spec":{"persistentVolumeReclaimPolicy":"Delete"}}'
done
kubectl delete pod writer reader --ignore-not-found
kubectl delete pvc claim1 claim2 claim3 claim3-restored --ignore-not-found
sleep 5
for pv in $(kubectl get pv -o jsonpath='{range .items[?(@.status.phase=="Released")]}{.metadata.name}:{.spec.claimRef.name}{"\n"}{end}' | grep -E ':claim[0-9]' | cut -d: -f1); do
  kubectl delete pv "$pv"
done
minikube ssh -- 'sudo ls /tmp/hostpath-provisioner/default/ 2>/dev/null' | grep -E "claim[0-9]" || echo "no claim directories left on the node"
