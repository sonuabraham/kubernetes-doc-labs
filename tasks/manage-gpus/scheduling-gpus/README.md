# Schedule GPUs – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/manage-gpus/scheduling-gpus/

> Runs on the default **minikube** cluster, which has no GPU. The page is about how a vendor's device plugin exposes GPUs as an **extended resource**
> and how Pods request them. [gpu-capacity.sh](gpu-capacity.sh) (not from the docs) makes the node advertise `gpu-vendor.example/example-gpu: 2`
> (a node status patch, which is what the kubelet reports once a device plugin registers), so scheduling and validation can be tested for real.
> Files (docs' inline examples, **verbatim**): [example-vector-add.yaml](example-vector-add.yaml), [example-vector-add-nfd.yaml](example-vector-add-nfd.yaml).
> [example-vector-add-nfd-fixed.yaml](example-vector-add-nfd-fixed.yaml) is not from the docs.
> A real device plugin (gRPC, kubelet registration, Allocate) is built in the concept lab
> [concepts/extend-kubernetes/compute-storage-net/device-plugins](../../../concepts/extend-kubernetes/compute-storage-net/device-plugins/).
>
> **Found:** the NFD/affinity example is **invalid**: its second match expression has no `operator`.
> `The Pod "example-vector-add" is invalid: …matchExpressions[1].operator: Invalid value: "": not a valid selector operator`. The fixed file adds `operator: In`.
> Also, `registry.example/example-vector-add:v42` is a placeholder, so the Pod gets scheduled but can't start.

## Key ideas (read first)

| Rule (extended resources such as GPUs) | Result |
|---|---|
| `limits` only | `requests` defaulted to the same value |
| `requests` == `limits` | allowed |
| `requests` without `limits` | rejected: `Limit must be set for non overcommitable resources` |
| `requests` ≠ `limits` | rejected: `must be equal to … limit` |
| fractions (`500m`) | rejected: `must be an integer` (no GPU sharing through requests) |
| Different GPU types | node labels (by hand or Node Feature Discovery) + nodeSelector / node affinity |

---

## Lab 1 – Request a GPU (docs)
```bash
cd tasks/manage-gpus/scheduling-gpus
./gpu-capacity.sh add 2
kubectl get node minikube -o jsonpath='{.status.allocatable}' | jq -c 'with_entries(select(.key|test("gpu")))'   # {"gpu-vendor.example/example-gpu":"2"}
kubectl apply -f example-vector-add.yaml
kubectl get pod example-vector-add -o jsonpath='{.spec.nodeName} {.spec.containers[0].resources.requests}'
#   minikube {"gpu-vendor.example/example-gpu":"1"}          <- request filled in from the limit
kubectl describe node minikube | grep -A12 'Allocated resources' | grep gpu      # gpu-vendor.example/example-gpu  1  1
kubectl delete pod example-vector-add                       # (the placeholder image never starts)
```

## Lab 2 – Requests vs. limits (docs rules, tested)
```bash
# Pods with registry.k8s.io/pause:3.10 and these resources:
#   requests 1 + limits 1     → created, Running
#   requests 1 only           → … resources.limits: Required value: Limit must be set for non overcommitable resources
#   requests 1, limits 2      → … resources.requests: Invalid value: "1": must be equal to gpu-vendor.example/example-gpu limit of 2
#   limits 500m               → … Invalid value: "500m": must be an integer
#   a 2nd Pod with limit 1 (both GPUs in use) → Pending: 0/1 nodes are available: 1 Insufficient gpu-vendor.example/example-gpu.
```

## Lab 3 – Pick the right GPU type with labels (docs)
```bash
kubectl apply -f example-vector-add-nfd.yaml        # invalid … matchExpressions[1].operator: Invalid value: ""
kubectl apply -f example-vector-add-nfd-fixed.yaml  # Pending: 1 node(s) didn't match Pod's node affinity/selector
kubectl label node minikube gpu.gpu-vendor.example/installed-memory=81920 feature.node.kubernetes.io/pci-10.present=true
kubectl get pod example-vector-add-nfd -o jsonpath='{.spec.nodeName}'          # minikube   (81920 Gt 40535, pci-10 present)
```
The docs' `kubectl label nodes node1 accelerator=example-gpu-x100` + a `nodeSelector: {accelerator: …}` works the same way.

## Cleanup
```bash
./cleanup.sh          # Pods, labels, fake GPU capacity
```
