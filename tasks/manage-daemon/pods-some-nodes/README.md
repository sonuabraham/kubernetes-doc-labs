# Running Pods on Only Some Nodes – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/manage-daemon/pods-some-nodes/

> Runs on the default **minikube** cluster plus three **API-only fake nodes** from
> [concepts/scheduling-eviction/fake-nodes.sh](../../../concepts/scheduling-eviction/fake-nodes.sh): they're Ready and get Pods assigned, but nothing
> runs there (Pods stay `Pending` with a node name). That's enough to watch the DaemonSet controller follow the labels.
> File: [daemonset-label-selector.yaml](daemonset-label-selector.yaml) (docs, **verbatim**).
>
> **Notes:**
> - `image: example-image` is a placeholder. On a real node the Pod ends in `ErrImagePull` / `ImagePullBackOff`. Put a real image in for real use.
> - Step 3 says "create the DaemonSet" but shows no command; it's `kubectl apply -f daemonset-label-selector.yaml`.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| `nodeSelector: ssd: "true"` in the Pod template | the DaemonSet only targets nodes with that label |
| Label added | controller creates a Pod for the node at once |
| Label removed | controller deletes that node's Pod |
| How Pods are pinned | each Pod gets `nodeAffinity` … `matchFields metadata.name In [<node>]` (plus the template's nodeSelector) |

---

## Lab 1 – The docs' steps
```bash
cd tasks/manage-daemon/pods-some-nodes
CTX=minikube ../../../concepts/scheduling-eviction/fake-nodes.sh up 3       # fake-1, fake-2, fake-3 (Ready)
kubectl label nodes fake-1 fake-2 ssd=true                                  # docs: example-node-1 example-node-2
kubectl apply -f daemonset-label-selector.yaml
kubectl get pods -l app=ssd-driver-pod -o wide
#   ssd-driver-d26l4   0/1   Pending   …   fake-1
#   ssd-driver-mmmcw   0/1   Pending   …   fake-2          <- not on minikube, not on fake-3
kubectl label nodes fake-3 ssd=true                                         # docs: example-node-3
kubectl get pods -l app=ssd-driver-pod -o wide                              # + ssd-driver-2qz72 on fake-3, within a second
kubectl get ds ssd-driver
#   ssd-driver   3   3   0   3   0   ssd=true
```

## Lab 2 – The other direction (not from the docs)
```bash
kubectl label nodes fake-1 ssd-
kubectl get ds ssd-driver                                                   # DESIRED 2 – fake-1's Pod deleted
kubectl label nodes minikube ssd=false
kubectl get ds ssd-driver                                                   # still 2 – value must be exactly "true"
kubectl get pod <one-pod> -o jsonpath='{.spec.affinity.nodeAffinity}{"\n"}{.spec.nodeSelector}'
#   {"requiredDuringSchedulingIgnoredDuringExecution":{"nodeSelectorTerms":[{"matchFields":[{"key":"metadata.name","operator":"In","values":["fake-3"]}]}]}}
#   {"ssd":"true"}
kubectl label nodes minikube ssd=true --overwrite
kubectl get pods -l app=ssd-driver-pod -o wide | grep minikube              # … ErrImagePull   <- example-image doesn't exist
```

## Cleanup
```bash
./cleanup.sh       # DaemonSet, labels, fake nodes (+ DaemonSet Pods left on them)
```
