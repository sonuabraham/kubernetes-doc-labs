# Assign Pods to Nodes – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/configure-pod-container/assign-pods-nodes/

> minikube has one node. To give the scheduler a choice, three API-only nodes (`fake-1..3`, no kubelet) are added with
> [../../../concepts/scheduling-eviction/fake-nodes.sh](../../../concepts/scheduling-eviction/fake-nodes.sh).
> The **real** `minikube` node gets the `disktype=ssd` label, so the docs' Pod really runs. Pods in the `default` namespace, as in the docs.
> Files: [pod-nginx.yaml](pod-nginx.yaml), [pod-nginx-specific-node.yaml](pod-nginx-specific-node.yaml) (docs, **verbatim**).
> Not from the docs: [nodename-vs-selector.yaml](nodename-vs-selector.yaml).

## Key ideas (read first)

| Field | Who acts on it | Notes |
|---|---|---|
| **`nodeSelector`** | scheduler: only nodes with **all** these labels | No match means `Pending` until a node gets the label. Checked only at scheduling time; removing the label later doesn't evict. |
| **`nodeName`** | **bypasses the scheduler**: the Pod is bound directly | No resource fit, taint or selector check by the scheduler. The **kubelet** still rejects it if `nodeSelector`/affinity don't match. A non-existent node means the Pod hangs until PodGC deletes it. |

```
            nodeSelector disktype=ssd
                 │ scheduler filters
 fake-1  fake-2  fake-3  minikube(disktype=ssd) ◄── nginx
 nodeName: foo-node ──► (no such node) ──► Pending, then force-deleted by PodGC (~70 s)
```

---

## Step 0 – Nodes
```bash
cd tasks/configure-pod-container/assign-pods-nodes
../../../concepts/scheduling-eviction/fake-nodes.sh up 3
kubectl get nodes --show-labels
#   fake-1     Ready   <none>          …  …,kubernetes.io/hostname=fake-1,…,type=fake,topology.kubernetes.io/zone=zone-a
#   fake-2 / fake-3 …
#   minikube   Ready   control-plane   …  …,kubernetes.io/hostname=minikube,…
```

## Lab 1 – nodeSelector (docs)
Create the Pod **before** labelling, to see it wait:
```bash
kubectl apply -f pod-nginx.yaml
kubectl get pod nginx -o wide                     # Pending, NODE <none>
kubectl describe pod nginx | grep FailedScheduling
#   0/4 nodes are available: 4 node(s) didn't match Pod's node affinity/selector. preemption: … not helpful …
kubectl label nodes minikube disktype=ssd
kubectl get nodes -L disktype                     # minikube  ssd
kubectl get pods --output=wide
#   nginx   1/1   Running   0   9s   10.244.0.9   minikube
```
The scheduler retried as soon as a node changed.

## Lab 2 – Labels only matter at scheduling time (not from the docs)
```bash
kubectl label nodes minikube disktype-
kubectl get pod nginx -o wide                     # still Running on minikube
kubectl label nodes minikube disktype=ssd
kubectl delete pod nginx --now
```

## Lab 3 – nodeName (docs `foo-node`)
```bash
kubectl apply -f pod-nginx-specific-node.yaml
kubectl get pod nginx -o wide                     # Pending  NODE foo-node   <- bound without a scheduler; no kubelet called foo-node
sleep 75; kubectl get pod nginx                   # Error from server (NotFound)
kubectl logs -n kube-system kube-controller-manager-minikube | grep -E 'PodGC|orphaned' | tail -2
#   "PodGC is force deleting Pod" pod="default/nginx"
#   "Forced deletion of orphaned Pod succeeded" pod="default/nginx"
```
PodGC treats a Pod bound to a node that doesn't exist as orphaned (after a ~40 s quarantine) and force-deletes it.
Change `foo-node` to `minikube` in a copy of the file, and the Pod runs there immediately.

## Lab 4 – nodeName doesn't skip the kubelet's checks (not from the docs)
```bash
kubectl apply -f nodename-vs-selector.yaml        # nodeName: minikube, nodeSelector disktype=hdd
kubectl get pod nginx-nodename-mismatch -o wide
#   nginx-nodename-mismatch   0/1   NodeAffinity   0   …   minikube
kubectl get pod nginx-nodename-mismatch -o jsonpath='{.status.reason}: {.status.message}{"\n"}'
#   NodeAffinity: Pod was rejected: Predicate NodeAffinity failed: node(s) didn't match Pod's node affinity/selector
```
The kubelet re-runs the node-level admission predicates (selector/affinity, resources, taints with NoExecute) and fails the Pod.
Prefer `nodeSelector` or affinity over `nodeName`. `nodeName` is meant for custom schedulers.

## Useful commands
```bash
kubectl get nodes -L disktype,topology.kubernetes.io/zone
kubectl get pods -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName,SELECTOR:.spec.nodeSelector
```

## Cleanup
```bash
./cleanup.sh       # Pods, the disktype label, and the fake nodes
```
