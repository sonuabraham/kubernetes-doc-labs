# Debug a StatefulSet – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/debug/debug-application/debug-statefulset/

> The page is three sentences: list the Pods by label, handle `Unknown`/`Terminating` Pods (→ Delete StatefulSet Pods), and debug
> single Pods (→ Debug Pods). This lab adds the one problem that is **specific** to StatefulSets: ordered start-up stalling.
> Runs on the default **minikube** cluster, namespace `debug-sts-demo`. Not from the docs: [myapp-statefulset.yaml](myapp-statefulset.yaml),
> [myapp-parallel.yaml](myapp-parallel.yaml). Both use the docs' label `app.kubernetes.io/name=MyApp`.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **OrderedReady** (default `podManagementPolicy`) | Pod *N+1* is only created when *N* is Running **and Ready**. One unready Pod stops everything after it, and there's **no event** saying so. You only see Pods that are missing. |
| **Parallel** | All ordinals are created at once. A broken Pod doesn't block the others. (It doesn't change rolling updates.) |
| **Stuck `Unknown` / `Terminating`** | The StatefulSet won't create a replacement with the same name until the old Pod object is gone (at-most-one semantics). See [Force Delete StatefulSet Pods](../../../run-application/force-delete-stateful-set-pod/). |
| **Single Pods** | Same as any Pod: [debug-pods](../debug-pods/), [debug-running-pod](../debug-running-pod/). |

---

## Step 0
```bash
cd tasks/debug/debug-application/debug-statefulset
kubectl create ns debug-sts-demo
kubectl apply -f myapp-statefulset.yaml          # 3 replicas, ordinal 1 never becomes Ready
```

## Lab 1 – List the Pods (docs)
```bash
kubectl get pods -n debug-sts-demo -l app.kubernetes.io/name=MyApp
#   myapp-0   1/1   Running   0   18s
#   myapp-1   0/1   Running   0   17s
#                                       <- no myapp-2, ever
kubectl get sts myapp -n debug-sts-demo               # READY 1/3
kubectl rollout status sts/myapp -n debug-sts-demo --timeout=5s
#   Waiting for 2 pods to be ready...
kubectl describe sts myapp -n debug-sts-demo | grep -A6 Events
#   SuccessfulCreate  Create Pod myapp-0 …   SuccessfulCreate  Create Pod myapp-1 …    <- and nothing about myapp-2
kubectl describe pod myapp-1 -n debug-sts-demo | grep 'Readiness probe failed'
#   Readiness probe failed: cat: can't open '/tmp/ready': No such file or directory      <- the real cause, on the Pod
```

## Lab 2 – Same app, `podManagementPolicy: Parallel`
```bash
kubectl apply -f myapp-parallel.yaml
kubectl get pods -n debug-sts-demo -l app.kubernetes.io/name=MyApp -L variant
#   myapp-par-0   1/1   Running   par
#   myapp-par-1   0/1   Running   par
#   myapp-par-2   1/1   Running   par      <- created anyway
```
`podManagementPolicy` is immutable: changing it means recreating the StatefulSet. Use `kubectl delete sts --cascade=orphan`
to keep the Pods while doing so.

## Lab 3 – Fix the blocking Pod
```bash
kubectl exec -n debug-sts-demo myapp-1 -- touch /tmp/ready
kubectl get pods -n debug-sts-demo -l 'app.kubernetes.io/name=MyApp,!variant'
#   myapp-0 1/1   myapp-1 1/1   myapp-2 1/1 (12s)      <- the controller continues immediately
kubectl get sts myapp -n debug-sts-demo                # 3/3
```

## Useful commands
```bash
kubectl get pods -l app.kubernetes.io/name=MyApp -o wide
kubectl get sts <name> -o jsonpath='{.spec.podManagementPolicy} {.status.readyReplicas}/{.spec.replicas}{"\n"}'
kubectl rollout status sts/<name>
```

## Cleanup
```bash
./cleanup.sh
```
