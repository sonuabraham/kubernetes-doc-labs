# Update a Deployment Without Downtime – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/run-application/update-deployment-rolling/

> Runs on the default **minikube** cluster, `default` namespace. Files: [deployment.yaml](deployment.yaml) (docs, **verbatim**),
> [availability-test.sh](availability-test.sh) (not from the docs: counts failed requests during an update).
>
> **Found:**
> 1. A plain RollingUpdate of nginx is **not** fully zero-downtime: 1–2 of about 50 requests failed in every run. The page doesn't mention it.
>    The cause is that old Pods get SIGTERM while kube-proxy still sends them traffic. A `preStop` sleep fixes it (0 failures, Lab 3).
> 2. `kubectl rollout undo` on a **paused** Deployment is refused (`resume it first`). Also, a paused Deployment still gives an existing matching
>    ReplicaSet a new revision number (Lab 2).

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| Trigger | only changes to `.spec.template` make a new ReplicaSet/revision (`replicas`, strategy, … don't) |
| `maxSurge` / `maxUnavailable` | default 25% / 25%; surge rounds **up**, unavailable rounds **down**. With 2 replicas: +1 extra, 0 unavailable |
| Pause | batch template changes into one rollout |
| Stalled | `progressDeadlineSeconds` → `Progressing=False ProgressDeadlineExceeded`; **no automatic rollback** |
| History | one old ReplicaSet per revision, up to `revisionHistoryLimit` (10); re-using an old template **moves** its revision number forward |
| `CHANGE-CAUSE` | the `kubernetes.io/change-cause` annotation; set it yourself |

---

## Step 0
```bash
cd tasks/run-application/update-deployment-rolling
kubectl apply -f deployment.yaml
kubectl rollout status deployment/nginx-deployment
```

## Lab 1 – Update (docs)
```bash
kubectl get deployment nginx-deployment -o yaml > /tmp/nginx-deployment.yaml
sed -i 's/image: nginx:1.14.2/image: nginx:1.16.1/' /tmp/nginx-deployment.yaml
kubectl diff -f /tmp/nginx-deployment.yaml
#   -  generation: 1
#   +  generation: 2
#   -      - image: nginx:1.14.2
#   +      - image: nginx:1.16.1
kubectl apply -f /tmp/nginx-deployment.yaml
kubectl rollout status deployment/nginx-deployment
#   Waiting … 1 out of 2 new replicas have been updated...
#   Waiting … 1 old replicas are pending termination...
#   deployment "nginx-deployment" successfully rolled out
kubectl set image deployment/nginx-deployment nginx=nginx:1.17.0      # image updated
kubectl get deployment nginx-deployment -o jsonpath='{.spec.template.spec.containers[0].image}'   # nginx:1.17.0
```

## Lab 2 – Pause / resume (docs + extras)
```bash
kubectl rollout pause deployment/nginx-deployment
kubectl set image deployment/nginx-deployment nginx=nginx:1.16.1
kubectl set env deployment/nginx-deployment COLOR=blue                 # second change (not from the docs)
kubectl get rs -l app=nginx                                            # no new ReplicaSet yet
kubectl get deploy nginx-deployment -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.reason}{"\n"}{end}'
#   Available=True MinimumReplicasAvailable
#   Progressing=Unknown DeploymentPaused
kubectl rollout undo deployment/nginx-deployment
#   error: you cannot rollback a paused deployment; resume it first with 'kubectl rollout resume' and try again
kubectl rollout resume deployment/nginx-deployment
kubectl get rs -l app=nginx -o custom-columns=NAME:.metadata.name,DESIRED:.spec.replicas,\
REV:.metadata.annotations.deployment\\.kubernetes\\.io/revision,IMAGE:.spec.template.spec.containers[0].image,ENV:.spec.template.spec.containers[0].env[0].value
#   nginx-deployment-54fd4d6d4c   0   1   nginx:1.14.2   <none>
#   nginx-deployment-5c89b4dd48   0   3   nginx:1.17.0   <none>
#   nginx-deployment-67b6bf96f9   2   5   nginx:1.16.1   blue     <- one rollout for both changes
#   nginx-deployment-76df5b8bb8   0   4   nginx:1.16.1   <none>   <- was rev 2; renumbered while paused (template matched it briefly)
```

## Lab 3 – Is it really without downtime? (not from the docs)
```bash
./availability-test.sh RollingUpdate
#   strategy=RollingUpdate  image nginx:1.16.1 -> nginx:1.17.0
#         1 FAIL      47 ok      (other runs: 2 FAIL / 48 ok, 1 FAIL / 49 ok)
./availability-test.sh Recreate
#   strategy=Recreate …   2 FAIL   44 ok    "Connection refused"   <- every Pod down at once (short here: image cached, nginx starts fast)
./availability-test.sh RollingUpdate+preStop
#   61 ok   /   52 ok      <- 0 failures in both runs
```
`RollingUpdate+preStop` adds `lifecycle.preStop.sleep.seconds: 5`. While it sleeps, the endpoint is removed everywhere, and only then
nginx gets SIGTERM. Real apps also need a **readinessProbe**, so that new Pods get traffic only when ready.

## Lab 4 – Stalled rollout, change-cause, rollback (docs + extras)
```bash
kubectl patch deployment nginx-deployment -p '{"spec":{"progressDeadlineSeconds":15}}'      # shorter for the lab
kubectl set image deployment/nginx-deployment nginx=nginx:does-not-exist
kubectl annotate deployment nginx-deployment kubernetes.io/change-cause="try nginx:does-not-exist"
kubectl rollout status deployment/nginx-deployment
#   error: deployment "nginx-deployment" exceeded its progress deadline
kubectl get pods -l app=nginx
#   2 old Pods Running + 1 new Pod ImagePullBackOff   <- maxUnavailable 25% of 2 = 0, so nothing old is removed
kubectl describe deployment nginx-deployment | sed -n '/^Conditions/,/^OldReplicaSets/p'
#   Available      True    MinimumReplicasAvailable
#   Progressing    False   ProgressDeadlineExceeded
kubectl rollout history deployment/nginx-deployment
#   …
#   13        try nginx:does-not-exist
kubectl rollout history deployment/nginx-deployment --revision=1 | grep Image      # nginx:1.14.2
kubectl rollout undo deployment/nginx-deployment --to-revision=1
kubectl rollout history deployment/nginx-deployment          # 1 is gone, 14 is new (same ReplicaSet, new number)
kubectl patch deployment nginx-deployment -p '{"spec":{"revisionHistoryLimit":0}}'
kubectl get rs -l app=nginx                                  # only the current ReplicaSet left
kubectl rollout undo deployment/nginx-deployment
#   error: no rollout history found for deployment "nginx-deployment"
```

## Cleanup
```bash
./cleanup.sh
```
