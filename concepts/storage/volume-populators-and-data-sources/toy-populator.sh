#!/usr/bin/env bash
# A toy volume populator for kind ExampleDataSource (example.storage.k8s.io).
# Real populators (built on lib-volume-populator) create a hidden "prime" PVC, fill it with a Pod and rebind
# the PV to the user's claim. This toy takes the shortest path that shows the idea:
#   unbound PVC with dataSourceRef -> ExampleDataSource  ==>  write the files into a node dir,
#   create a PV pre-bound (claimRef) to that PVC.  Runs from your workstation (uses minikube ssh). Ctrl-C to stop.
set -uo pipefail
while true; do
  kubectl get pvc -A -o json | jq -r '.items[]
     | select(.spec.dataSourceRef.kind=="ExampleDataSource" and .spec.dataSourceRef.apiGroup=="example.storage.k8s.io" and (.spec.volumeName // "")=="")
     | [.metadata.namespace, .metadata.name, .metadata.uid, .spec.dataSourceRef.name, (.spec.storageClassName // ""), .spec.resources.requests.storage] | @tsv' |
  while IFS=$'\t' read -r ns pvc uid src class size; do
    pv="populated-$uid"
    kubectl get pv "$pv" >/dev/null 2>&1 && continue
    files=$(kubectl get exampledatasource "$src" -n "$ns" -o json 2>/dev/null | jq -c '.spec.files // {}') \
      || { echo "$(date +%T) $ns/$pvc: ExampleDataSource $ns/$src not found, waiting"; continue; }
    dir=/tmp/populated/$uid
    cmd="sudo mkdir -p $dir"
    for f in $(echo "$files" | jq -r 'keys[]'); do
      b64=$(echo "$files" | jq -r --arg f "$f" '.[$f]' | base64 -w0)
      cmd="$cmd && echo $b64 | base64 -d | sudo tee $dir/$f >/dev/null"
    done
    minikube ssh -- "$cmd" </dev/null >/dev/null
    cat <<YAML | kubectl apply -f - >/dev/null
apiVersion: v1
kind: PersistentVolume
metadata:
  name: $pv
  labels: {populated-by: toy-populator}
spec:
  storageClassName: "$class"
  capacity: {storage: $size}
  accessModes: ["ReadWriteOnce"]
  persistentVolumeReclaimPolicy: Delete
  hostPath: {path: $dir}
  claimRef: {namespace: $ns, name: $pvc, uid: $uid}
YAML
    echo "$(date +%T) populated $ns/$pvc from ExampleDataSource $src ($(echo "$files" | jq -r 'keys|join(", ")')) -> PV $pv"
  done
  sleep 3
done
