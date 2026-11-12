#!/usr/bin/env bash
# fake-dra.sh up|down - a pretend DRA driver "gpu.example.com" for the DRA labs:
#   2 fake nodes (../../scheduling-eviction/fake-nodes.sh) + one ResourceSlice per node, published by hand the way a
#   real driver's kubelet plugin would:   fake-1: gpu-0, gpu-1 = model a100, 40Gi    fake-2: gpu-0, gpu-1 = model h100, 80Gi
#   + DeviceClass "gpu.example.com" selecting every device of the driver.
# The scheduler allocates these devices for real (ResourceClaim status); nothing ever "prepares" them because fake
# nodes have no kubelet, so Pods stay Pending/ContainerCreating - look at claims and spec.nodeName.
set -euo pipefail
D=$(cd "$(dirname "$0")" && pwd); F=$D/../../scheduling-eviction/fake-nodes.sh
if [ "${1:-up}" = down ]; then
  kubectl delete resourceslices -l lab=fake-dra --ignore-not-found; kubectl delete deviceclass gpu.example.com --ignore-not-found
  "$F" down; exit 0
fi
"$F" up 2 >/dev/null
slice(){ # node model mem
kubectl apply -f - >/dev/null <<Y
apiVersion: resource.k8s.io/v1
kind: ResourceSlice
metadata: {name: $1-gpu.example.com, labels: {lab: fake-dra}}
spec:
  driver: gpu.example.com
  nodeName: $1
  pool: {name: $1, generation: 1, resourceSliceCount: 1}
  devices:
  - name: gpu-0
    attributes: {model: {string: $2}, index: {int: 0}, driverVersion: {version: 1.2.0}}
    capacity: {memory: {value: $3}}
  - name: gpu-1
    attributes: {model: {string: $2}, index: {int: 1}, driverVersion: {version: 1.2.0}}
    capacity: {memory: {value: $3}}
Y
}
slice fake-1 a100 40Gi; slice fake-2 h100 80Gi
kubectl apply -f - >/dev/null <<Y
apiVersion: resource.k8s.io/v1
kind: DeviceClass
metadata: {name: gpu.example.com}
spec:
  selectors:
  - cel: {expression: 'device.driver == "gpu.example.com"'}
Y
kubectl get resourceslices -l lab=fake-dra -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName,DEVICES:.spec.devices[*].name
