# Assign Pods to Nodes using Node Affinity – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/configure-pod-container/assign-pods-nodes-using-node-affinity/

> Same setup as [../assign-pods-nodes](../assign-pods-nodes/): three API-only nodes `fake-1..3` (zones a/b/c, label
> `type=fake`, no kubelet, so Pods bound there stay Pending) plus the real `minikube` node, which gets `disktype=ssd`.
> Files: [pod-nginx-required-affinity.yaml](pod-nginx-required-affinity.yaml), [pod-nginx-preferred-affinity.yaml](pod-nginx-preferred-affinity.yaml)
> (docs, **verbatim**). Not from the docs: [no-affinity-control.yaml](no-affinity-control.yaml), [affinity-terms.yaml](affinity-terms.yaml).

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **`requiredDuringScheduling…`** | A hard filter, like `nodeSelector` but with operators `In, NotIn, Exists, DoesNotExist, Gt, Lt`. No match means Pending. |
| **`preferredDuringScheduling…`** | A score. Matching nodes get `weight` (1–100). The NodeAffinity plugin normalizes this to 0–100, and the plugin has weight 2 in the default profile, so even `weight: 1` beats the small differences of the balancing plugins. |
| **Combining** | `nodeSelectorTerms` are **ORed**. `matchExpressions` inside one term are **ANDed**. |
| **`…IgnoredDuringExecution`** | Like nodeSelector: label changes don't move running Pods. |

---

## Step 0
```bash
cd tasks/configure-pod-container/assign-pods-nodes-using-node-affinity
../../../concepts/scheduling-eviction/fake-nodes.sh up 3
kubectl label nodes minikube disktype=ssd
kubectl get nodes -L disktype,topology.kubernetes.io/zone
#   fake-1  …  zone-a     fake-2  …  zone-b     fake-3  …  zone-c     minikube  ssd
```

## Lab 1 – Required node affinity (docs)
```bash
kubectl apply -f pod-nginx-required-affinity.yaml
kubectl get pods --output=wide              # nginx   Running   minikube
kubectl delete pod nginx --now
```

## Lab 2 – Preferred node affinity (docs), with a control group
```bash
for i in 1 2 3 4 5 6; do sed "s/name: nginx$/name: nginx-pref-$i/" pod-nginx-preferred-affinity.yaml | kubectl apply -f -; done
for i in 1 2 3 4 5 6; do sed "s/name: nginx-noaff$/name: nginx-noaff-$i/" no-affinity-control.yaml | kubectl apply -f -; done
kubectl get pods -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName
```
| Pods | Placement |
|---|---|
| nginx-pref-1…6 (`weight: 1` for ssd) | **all 6 on minikube** |
| nginx-noaff-1…6 (no affinity) | fake-1, fake-3, fake-2, fake-1, fake-2, fake-3: the emptier fake nodes win on resource balance |

So the preference really changed the decision, even at the lowest weight.

## Lab 3 – When nothing matches (not from the docs)
```bash
kubectl delete pod $(kubectl get pods -o name | grep -E 'pref|noaff' | sed 's|pod/||') --grace-period=0 --force
kubectl label nodes minikube disktype-
kubectl apply -f pod-nginx-required-affinity.yaml
sed 's/name: nginx$/name: nginx-preferred/' pod-nginx-preferred-affinity.yaml | kubectl apply -f -
kubectl get pods -o wide
#   nginx             Pending   <none>      <- required: waits
#   nginx-preferred   Pending   fake-1      <- preferred: scheduled anyway (Pending only because fake-1 has no kubelet)
kubectl describe pod nginx | grep FailedScheduling
#   0/4 nodes are available: 4 node(s) didn't match Pod's node affinity/selector …
kubectl label nodes minikube disktype=ssd
kubectl get pod nginx -o wide               # Running on minikube a few seconds later
```

## Lab 4 – OR between terms, AND inside a term (not from the docs)
```bash
kubectl apply -f affinity-terms.yaml
kubectl get pods -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName | grep -E 'terms|exprs|not-in'
```
| Pod | Rule | Landed on | Allowed nodes |
|---|---|---|---|
| terms-or | zone-a **OR** disktype=ssd | minikube | fake-1, minikube |
| exprs-and | zone-b **AND** type=fake | fake-2 | fake-2 only |
| not-in | zone `Exists` AND zone `NotIn [zone-a, zone-b]` | fake-3 | fake-3 only (minikube has no zone label) |

## Useful commands
```bash
kubectl explain pod.spec.affinity.nodeAffinity
kubectl get events --field-selector reason=Scheduled -o custom-columns=MSG:.message
kubectl get pods -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName
```

## Cleanup
```bash
./cleanup.sh       # Pods (force: some sit on fake nodes), the disktype label, the fake nodes
```
