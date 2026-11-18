# Perform a Rollback on a DaemonSet – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/manage-daemon/rollback-daemon-set/

> Runs on the default **minikube** cluster, `default` namespace. The page only uses placeholders, so [demo-daemonset.yaml](demo-daemonset.yaml)
> (**not from the docs**, nginx 1.26) is updated twice (1.27, then a broken tag) and rolled back.
>
> **Found:**
> 1. `--record` (mentioned for `CHANGE-CAUSE`) is deprecated: `Flag --record has been deprecated, --record will be removed in the future`.
>    Set the `kubernetes.io/change-cause` annotation yourself.
> 2. "If `--to-revision` is not specified, kubectl picks the most recent revision" means the **previous** revision, which isn't always a good one.
>    After rolling back from the broken revision 3 to 1, a plain `kubectl rollout undo` went to **revision 3 again** (the broken image).

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| ControllerRevision | one per DaemonSet template version (`<ds>-<hash>`), holds the template + annotations, owned by the DaemonSet |
| `rollout undo --to-revision=N` | copies revision N's template into the DaemonSet → a normal rolling update |
| Roll forward only | the revision you return to gets the **next** number (1 → 4); the old number disappears from the history |

---

## Lab 1 – Build some history
```bash
cd tasks/manage-daemon/rollback-daemon-set
kubectl apply -f demo-daemonset.yaml                                   # revision 1: nginx:1.26
kubectl set image ds/demo-ds app=nginx:1.27 --record                   # revision 2  (Flag --record has been deprecated …)
kubectl annotate ds demo-ds kubernetes.io/change-cause="bad image tag" --overwrite
kubectl set image ds/demo-ds app=nginx:does-not-exist                  # revision 3: ErrImagePull
```

## Lab 2 – Roll back (docs steps 1–3)
```bash
kubectl rollout history daemonset demo-ds
#   REVISION  CHANGE-CAUSE
#   1         <none>
#   2         kubectl set image ds/demo-ds app=nginx:1.27 --record=true
#   3         bad image tag
kubectl rollout history daemonset demo-ds --revision=1 | grep Image     # Image:  nginx:1.26
kubectl get controllerrevision -l app=demo-ds
#   demo-ds-58d45cc955   daemonset.apps/demo-ds   1
#   demo-ds-848bb94b7d   daemonset.apps/demo-ds   2
#   demo-ds-9858d7767    daemonset.apps/demo-ds   3
kubectl rollout undo daemonset demo-ds --to-revision=1                 # daemonset.apps/demo-ds rolled back
kubectl rollout status ds/demo-ds                                      # successfully rolled out → nginx:1.26
kubectl get controllerrevision -l app=demo-ds
#   demo-ds-58d45cc955   …   4        <- the same object, revision 1 → 4 (docs note)
#   demo-ds-848bb94b7d   …   2
#   demo-ds-9858d7767    …   3
```

## Lab 3 – A plain `undo` afterwards (not from the docs)
```bash
kubectl rollout undo daemonset demo-ds                                 # rolled back … to revision 3!
kubectl rollout status ds/demo-ds --timeout=20s                        # error: timed out waiting for the condition
kubectl get pods -l app=demo-ds -o jsonpath='{.items[0].spec.containers[0].image}'      # nginx:does-not-exist
```
Always look at `rollout history` and use `--to-revision`.

## Cleanup
```bash
./cleanup.sh
```
