# API-initiated Eviction – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/scheduling-eviction/api-eviction/

> The docs' [eviction.json](eviction.json) is **verbatim** (`default/quux`). [00-quux.yaml](00-quux.yaml) creates that Pod, [01-pdb.yaml](01-pdb.yaml) protects it, and [02-unready-pdb.yaml](02-unready-pdb.yaml) reproduces a *stuck eviction*. The docs' `curl … /eviction -d @eviction.json` is done with `kubectl create --raw` (same request, your kubeconfig's credentials).

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Eviction subresource** | `POST /api/v1/namespaces/<ns>/pods/<pod>/eviction` with an `Eviction` object: a **polite delete**. `kubectl drain` and autoscalers use it. |
| **Checks** | The API server checks **PodDisruptionBudgets** first. Allowed → `201` and a graceful delete (`terminationGracePeriodSeconds`, or `deleteOptions` in the Eviction). Not allowed → `429 Too Many Requests` (retry later). Misconfigured (several PDBs) → `500`. |
| **DisruptionTarget** | The evicted Pod gets condition `DisruptionTarget=True, reason EvictionByEvictionAPI` before termination. Job pod failure policies can use it. |
| **vs node-pressure** | API eviction respects PDBs and grace periods. Kubelet eviction ignores PDBs (see `../node-pressure-eviction`). |
| **Stuck evictions** | Common cause: a PDB guarding Pods that never become Ready. Fix with `unhealthyPodEvictionPolicy: AlwaysAllow` on the PDB, or delete the Pod. |

---

## Lab 1 – The docs' eviction, with and without a PDB
```bash
cd concepts/scheduling-eviction/api-eviction
kubectl apply -f 00-quux.yaml -f 01-pdb.yaml
kubectl get pdb quux-pdb                    # MIN AVAILABLE 1   ALLOWED DISRUPTIONS 0
kubectl create --raw /api/v1/namespaces/default/pods/quux/eviction -f eviction.json
#   Error from server (TooManyRequests): Cannot evict pod as it would violate the pod's disruption budget.
kubectl delete pdb quux-pdb
kubectl create --raw /api/v1/namespaces/default/pods/quux/eviction -f eviction.json
#   {"kind":"Status","apiVersion":"v1","metadata":{},"status":"Success","code":201}
kubectl get pod quux -o jsonpath='{.metadata.deletionTimestamp} {range .status.conditions[?(@.type=="DisruptionTarget")]}{.type}={.status} {.reason}: {.message}{end}'
#   2026-11-12T03:57:42Z DisruptionTarget=True EvictionByEvictionAPI: Eviction API: evicting
```

## Lab 2 – A stuck eviction and the fix
```bash
kubectl apply -f 02-unready-pdb.yaml        # Pod never-ready (readiness probe "false") + PDB minAvailable 1
kubectl get pdb never-ready-pdb -o jsonpath='{.status.currentHealthy}/{.status.desiredHealthy} allowed={.status.disruptionsAllowed}'    # 0/1 allowed=0
echo '{"apiVersion":"policy/v1","kind":"Eviction","metadata":{"name":"never-ready","namespace":"default"}}' | \
  kubectl create --raw /api/v1/namespaces/default/pods/never-ready/eviction -f -
#   TooManyRequests ...           <- default (unset = IfHealthyBudget): an unhealthy Pod can't be evicted while the app is "disrupted"
kubectl patch pdb never-ready-pdb --type=merge -p '{"spec":{"unhealthyPodEvictionPolicy":"AlwaysAllow"}}'
echo '{"apiVersion":"policy/v1","kind":"Eviction","metadata":{"name":"never-ready","namespace":"default"},"deleteOptions":{"gracePeriodSeconds":0}}' | \
  kubectl create --raw /api/v1/namespaces/default/pods/never-ready/eviction -f -
#   ... "code":201                  <- an unready Pod gives the budget nothing, so evicting it is always fine
```
Watch out when re-running: `kubectl apply` of the unchanged PDB file does **not** reset a field you patched in (`AlwaysAllow` stays). Delete and recreate it.

---

## Useful commands
```bash
kubectl get pdb -A -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,ALLOWED:.status.disruptionsAllowed,POLICY:.spec.unhealthyPodEvictionPolicy
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data       # uses the Eviction API for every Pod (not on single-node minikube!)
```

## Cleanup
```bash
./cleanup.sh
```
