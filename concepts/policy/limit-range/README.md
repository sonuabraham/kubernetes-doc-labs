# Limit Ranges – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/policy/limit-range/

> The docs' 3 manifests are **verbatim**: [problematic-limit-range.yaml](problematic-limit-range.yaml), [example-conflict-with-limitrange-cpu.yaml](example-conflict-with-limitrange-cpu.yaml), [example-no-conflict-with-limitrange-cpu.yaml](example-no-conflict-with-limitrange-cpu.yaml). The docs run them in `default`, this lab uses namespace `lr-demo`. [01-more-constraints.yaml](01-more-constraints.yaml) covers the page's other constraint types.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **LimitRange** | Namespaced policy for **per-object** resource bounds (a ResourceQuota bounds the namespace **total**). |
| **Types** | `Container`, `Pod` (sum over containers), `PersistentVolumeClaim` (storage). |
| **Fields** | `min`, `max`, `default` (limit), `defaultRequest`, `maxLimitRequestRatio`. |
| **Admission order** | The LimitRanger plugin first **mutates** (fills defaults, adds annotation `kubernetes.io/limit-ranger`), then **validates** min/max/ratio. |
| **Existing Pods** | Unaffected: only checked at create/update. |
| **Gotcha** | Defaults are applied even when you set only the *other* field, so you can end up with request > default limit → **invalid Pod** (the docs' "problematic" example). |
| **Multiple LimitRanges** | Allowed, but which default wins is not deterministic. Keep one per namespace. |

---

## Lab 1 – Defaults (docs `cpu-resource-constraint`)
```bash
cd concepts/policy/limit-range
kubectl create ns lr-demo
kubectl apply -n lr-demo -f problematic-limit-range.yaml
kubectl run before -n lr-demo --image=registry.k8s.io/pause:3.8
kubectl get pod before -n lr-demo -o jsonpath='{.spec.containers[0].resources}  {.metadata.annotations.kubernetes\.io/limit-ranger}{"\n"}'
#   {"limits":{"cpu":"500m"},"requests":{"cpu":"500m"}}  LimitRanger plugin set: cpu request for container before; cpu limit for container before
```

## Lab 2 – The docs' conflict
```bash
kubectl apply -n lr-demo -f example-conflict-with-limitrange-cpu.yaml
#   The Pod "example-conflict-with-limitrange-cpu" is invalid: spec.containers[0].resources.requests:
#   Invalid value: "700m": must be less than or equal to cpu limit of 500m
kubectl apply -n lr-demo -f example-no-conflict-with-limitrange-cpu.yaml        # created - it sets the limit itself
```
The Pod only asked for a 700m **request**. LimitRanger added the 500m **default limit**, and that made it invalid (the docs' message now includes "of 500m").

## Lab 3 – min / max
```bash
kubectl run too-big -n lr-demo --image=registry.k8s.io/pause:3.8 --overrides='{"spec":{"containers":[{"name":"too-big","image":"registry.k8s.io/pause:3.8","resources":{"limits":{"cpu":"2"}}}]}}'
#   forbidden: maximum cpu usage per Container is 1, but limit is 2
kubectl run too-small -n lr-demo --image=registry.k8s.io/pause:3.8 --overrides='{"spec":{"containers":[{"name":"too-small","image":"registry.k8s.io/pause:3.8","resources":{"requests":{"cpu":"50m"}}}]}}'
#   forbidden: minimum cpu usage per Container is 100m, but request is 50m
```

## Lab 4 – Pod totals, ratios, PVC sizes; existing Pods
```bash
kubectl run old -n lr-demo --image=registry.k8s.io/pause:3.8 --overrides='{"spec":{"containers":[{"name":"old","image":"registry.k8s.io/pause:3.8","resources":{"limits":{"memory":"512Mi"}}}]}}'
kubectl apply -n lr-demo -f 01-more-constraints.yaml
kubectl get pod old -n lr-demo            # still there - 512Mi breaks the new Pod max, but it was admitted earlier
```
| Attempt | Result |
|---|---|
| 2 containers × 150Mi limit (Pod max 256Mi) | `maximum memory usage per Pod is 256Mi, but limit is 300Mi` |
| request 32Mi, limit 128Mi (ratio max 2) | `memory max limit to request ratio per Container is 2, but provided ratio is 4.000000` |
| PVC 500Mi / 5Gi / 1Gi (min 1Gi, max 2Gi) | `minimum storage usage per PersistentVolumeClaim is 1Gi` / `maximum ... is 2Gi` / **created** |

---

## Useful commands
```bash
kubectl describe limitrange -n <ns>
kubectl get pod <p> -o jsonpath='{.metadata.annotations.kubernetes\.io/limit-ranger}'
```

## Cleanup
```bash
./cleanup.sh
```
