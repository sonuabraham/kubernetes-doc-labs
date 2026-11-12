# Taints and Tolerations – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/

> The docs' two Pods are **verbatim** ([pod-with-toleration.yaml](pod-with-toleration.yaml), [pod-with-numeric-toleration.yaml](pod-with-numeric-toleration.yaml)), plus the page's `tolerations:` snippets (`*-excerpt.yaml`). Every taint goes on the **fake nodes** (`../fake-nodes.sh up 3`). NoExecute on the real minikube node would evict CoreDNS and friends.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Taint** (on a node) | `key=value:effect`, a node **repels** Pods. Effects: `NoSchedule`, `PreferNoSchedule` (soft), `NoExecute` (also **evicts** running Pods). |
| **Toleration** (on a Pod) | Lets a Pod **ignore** a matching taint. `Equal` (key+value) or `Exists` (key only; empty key + Exists = everything). It **doesn't attract**: combine with node affinity for dedicated nodes. |
| **Multiple taints** | All must be tolerated (NoSchedule ones for scheduling, NoExecute ones to stay). |
| **tolerationSeconds** | For NoExecute: how long a Pod may stay after the taint appears. |
| **Numeric operators** `Gt`/`Lt` | Compare integer values, e.g. SLA levels (`TaintTolerationComparisonOperators`, **alpha, off**). |
| **Taint-based evictions** | Node problems become taints: `node.kubernetes.io/not-ready`, `unreachable` (NoExecute), `memory-pressure`, `disk-pressure`, `pid-pressure`, `network-unavailable`, `unschedulable` (NoSchedule). |
| **Defaults** | DefaultTolerationSeconds admission gives every Pod `not-ready`/`unreachable` NoExecute tolerations for **300s**. DaemonSet Pods tolerate all node-condition taints indefinitely. |

---

## Lab 1 – Tolerate ≠ attract
```bash
cd concepts/scheduling-eviction/taint-and-toleration
kubectl create ns taint-demo ; N="-n taint-demo"
kubectl taint nodes fake-1 example-key=value:NoSchedule ; kubectl taint nodes fake-2 fake-3 other=x:NoSchedule
kubectl apply $N -f pod-with-toleration.yaml           # docs nginx: tolerates example-key
kubectl run plain $N --image=nginx --overrides='{"spec":{"nodeSelector":{"type":"fake"}}}'
kubectl get pods $N -o custom-columns=POD:.metadata.name,NODE:.spec.nodeName
#   nginx   minikube      <- it MAY use fake-1, but nothing pulls it there
#   plain   <none>        0/4 nodes are available: 1 ... node affinity/selector, 3 node(s) had untolerated taint(s).
kubectl get pod plain $N -o jsonpath='{.spec.tolerations}'
#   [{"effect":"NoExecute","key":"node.kubernetes.io/not-ready","operator":"Exists","tolerationSeconds":300},
#    {"effect":"NoExecute","key":"node.kubernetes.io/unreachable","operator":"Exists","tolerationSeconds":300}]   <- added at admission
```

## Lab 2 – The docs' node with three taints
```bash
kubectl taint nodes fake-1 example-key- ; kubectl taint nodes fake-2 fake-3 other-
kubectl taint nodes fake-1 key1=value1:NoSchedule key1=value1:NoExecute key2=value2:NoSchedule
# a Pod tolerating only the two key1 taints, pinned to fake-1 via nodeSelector:
#   0/4 nodes are available: 1 node(s) had untolerated taint(s), ...      <- key2:NoSchedule isn't tolerated
```

## Lab 3 – NoExecute and tolerationSeconds
```bash
# three Pods bound to fake-2: no-tol, tol-30s (key1 NoExecute, tolerationSeconds 30), tol-forever (key1 Exists, no seconds)
kubectl taint nodes fake-2 key1=value1:NoExecute
#   +6s : no-tol=DELETING tol-30s=alive    tol-forever=alive
#   +31s: no-tol=DELETING tol-30s=DELETING tol-forever=alive      <- exactly after tolerationSeconds
kubectl get events $N --field-selector reason=TaintManagerEviction -o custom-columns=OBJ:.involvedObject.name,M:.message
#   no-tol    Marking for deletion Pod taint-demo/no-tol
#   tol-30s   Marking for deletion Pod taint-demo/tol-30s
```
(They stay `Terminating` because no kubelet runs fake nodes. On a real node they'd be gone.)

## Lab 4 – Taint-based evictions (node unreachable)
```bash
kill $(cat ../.fake-nodes.pid)          # stop the fake "kubelet" heartbeat
#   ~52s later:
kubectl get node fake-3 -o jsonpath='{.spec.taints}'
#   [{"effect":"NoSchedule","key":"node.kubernetes.io/unreachable",...},{"effect":"NoExecute","key":"node.kubernetes.io/unreachable",...}]
kubectl get nodes -l type=fake          # NotReady - "Kubelet stopped posting node status."
kubectl get pod -n kube-system -l k8s-app=kube-proxy --field-selector spec.nodeName=fake-3 -o jsonpath='{.items[0].spec.tolerations}'
#   [{"operator":"Exists"}, not-ready/unreachable NoExecute, disk-/memory-/pid-pressure, unschedulable, network-unavailable NoSchedule]
../fake-nodes.sh up 3                    # heartbeat back → taints removed
```
Ordinary Pods there would be evicted after their default **300s** `unreachable` toleration. `tol-forever` (tolerates `key1` only) doesn't tolerate `unreachable`, so it would go too.

## Lab 5 – Numeric comparison (alpha)
```bash
kubectl apply $N -f pod-with-numeric-toleration.yaml --dry-run=server
#   spec.tolerations[0].operator: Unsupported value: "Gt": supported values: "Equal", "Exists", "Lt", "Gt"
```
The message lists `Gt` as supported while rejecting it: the gate is **off**, and the validation text is generated regardless.

---

## Useful commands
```bash
kubectl taint nodes <n> key=value:NoSchedule        # add      ...key=value:NoSchedule-   remove
kubectl get nodes -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints[*].key
kubectl describe node <n> | grep -A3 Taints
```

## Cleanup
```bash
./cleanup.sh
```
