# Deployments – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/workloads/controllers/deployment/

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Deployment** | Declarative updates for Pods and ReplicaSets. You describe the desired state, and the controller rolls the actual state towards it at a controlled rate. For stateless apps. |
| **ReplicaSet per template** | Every distinct pod template gets its own ReplicaSet, named `<deploy>-<pod-template-hash>`. The hash label is also on the pods and in the selector. **Don't change it.** |
| **Rollout trigger** | Only `.spec.template` changes start a rollout. Scaling doesn't. |
| **RollingUpdate** (default) | `maxUnavailable` (default 25%, rounded down) and `maxSurge` (25%, rounded up), as an absolute number or %. Old and new run side by side. |
| **Recreate** | Kill all old Pods, then create new ones. Downtime, but never two versions at once. |
| **Rollover** | Updating during a rollout starts a newer ReplicaSet right away. It doesn't wait for the previous rollout. |
| **Rollback** | `kubectl rollout undo [--to-revision=N]`. Revisions live in the old ReplicaSets (`revisionHistoryLimit`, default 10; `0` means no rollback possible). |
| **Proportional scaling** | Scaling during a rollout spreads the extra replicas **proportionally** across the active ReplicaSets. |
| **Pause / resume** | Batch several template changes into **one** rollout. |
| **Status** | `Progressing` (new RS, scaling) → `Complete` (all updated, available, none old) or **Failed** after `progressDeadlineSeconds` (default 600) → `Progressing=False, reason ProgressDeadlineExceeded`. `kubectl rollout status` then exits **1**. |
| **minReadySeconds** | How long a new Pod must be Ready, without crashing, before it counts as available. |
| **terminatingReplicas** | (`DeploymentReplicaSetTerminatingReplicas`, beta, **on** in v1.37) `.status.terminatingReplicas` counts Pods still shutting down, so the total can briefly exceed `replicas`. |
| **Selector** | Immutable in `apps/v1`. Must match the template labels. |

## The demo app
The docs manifests are **verbatim**: [nginx-deployment.yaml](nginx-deployment.yaml) (3 × `nginx:1.14.2`) and the three strategy snippets [strategy-maxunavailable.yaml](strategy-maxunavailable.yaml), [strategy-maxsurge.yaml](strategy-maxsurge.yaml) and [strategy-both.yaml](strategy-both.yaml). Extra: [01-recreate.yaml](01-recreate.yaml) and [02-slow-terminating.yaml](02-slow-terminating.yaml).

---

## Lab 1 – Create (the docs' walk-through)
```bash
cd concepts/workloads/controllers/deployment
kubectl apply -f 00-namespace.yaml
kubectl apply -f nginx-deployment.yaml -n deploy-demo
kubectl rollout status deployment/nginx-deployment -n deploy-demo
#   Waiting for deployment "nginx-deployment" rollout to finish: 0 of 3 updated replicas are available...
#   deployment "nginx-deployment" successfully rolled out
kubectl get deploy,rs -n deploy-demo
kubectl get pods -n deploy-demo --show-labels       # app=nginx,pod-template-hash=54fd4d6d4c
```

## Lab 2 – Update (rolling) and rollover
```bash
kubectl set image deployment/nginx-deployment nginx=nginx:1.16.1 -n deploy-demo
kubectl rollout status deployment/nginx-deployment -n deploy-demo
kubectl get rs -n deploy-demo
#   nginx-deployment-54fd4d6d4c   0  0  0     <- old RS kept (for rollback), scaled to 0
#   nginx-deployment-76df5b8bb8   3  3  3     <- new RS
kubectl describe deployment nginx-deployment -n deploy-demo | grep -A12 Events     # ScalingReplicaSet up/down, step by step
```

## Lab 3 – A bad rollout gets stuck, then roll back
```bash
kubectl set image deployment/nginx-deployment nginx=nginx:1.161 -n deploy-demo      # typo in the tag, as in the docs
sleep 20 ; kubectl get rs -n deploy-demo
#   nginx-deployment-76df5b8bb8   3  3  3     <- still 3 good pods (maxUnavailable 25% of 3 = 0)
#   nginx-deployment-86769868fd   1  1  0     <- one new pod (maxSurge 25% of 3 -> 1), stuck in ImagePullBackOff
kubectl rollout history deployment/nginx-deployment -n deploy-demo
kubectl rollout history deployment/nginx-deployment -n deploy-demo --revision=2 | grep Image     # nginx:1.16.1
kubectl rollout undo deployment/nginx-deployment -n deploy-demo           # or --to-revision=2
kubectl get deploy nginx-deployment -n deploy-demo -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'   # nginx:1.16.1
```
Add `kubectl annotate deployment/nginx-deployment kubernetes.io/change-cause="…"` after each change to fill the CHANGE-CAUSE column.

## Lab 4 – Scaling and proportional scaling
```bash
kubectl scale deployment/nginx-deployment --replicas=10 -n deploy-demo ; kubectl rollout status deployment/nginx-deployment -n deploy-demo
kubectl set image deployment/nginx-deployment nginx=nginx:sometag -n deploy-demo      # a rollout that can't finish
sleep 5 ; kubectl get rs -n deploy-demo          # good RS 8, new (broken) RS 5
kubectl scale deployment/nginx-deployment --replicas=15 -n deploy-demo ; sleep 3
kubectl get deploy,rs -n deploy-demo
#   nginx-deployment   12/15   UP-TO-DATE 7
#   …-76df5b8bb8  12      <- 8 -> 12
#   …-b85c6c44f    7      <- 5 -> 7     the +5 (+surge) is split ~proportionally, not all to one RS
kubectl autoscale deployment/nginx-deployment --min=10 --max=15 --cpu-percent=80 -n deploy-demo   # docs command (needs metrics-server to act)
kubectl delete hpa nginx-deployment -n deploy-demo
kubectl rollout undo deployment/nginx-deployment -n deploy-demo ; kubectl scale deployment/nginx-deployment --replicas=3 -n deploy-demo
```

## Lab 5 – Pause, batch changes, resume
```bash
kubectl rollout pause deployment/nginx-deployment -n deploy-demo
kubectl set image deployment/nginx-deployment nginx=nginx:1.16.1 -n deploy-demo
kubectl set resources deployment/nginx-deployment -c=nginx --limits=cpu=200m,memory=512Mi -n deploy-demo
kubectl get rs -n deploy-demo                    # no new RS - nothing rolls out while paused
kubectl rollout resume deployment/nginx-deployment -n deploy-demo
kubectl rollout status deployment/nginx-deployment -n deploy-demo
kubectl get rs -n deploy-demo                    # ONE new RS containing both changes
```

## Lab 6 – Failed Deployment (progress deadline)
```bash
kubectl patch deployment/nginx-deployment -n deploy-demo -p '{"spec":{"progressDeadlineSeconds":20}}'    # docs uses 600
kubectl set image deployment/nginx-deployment nginx=nginx:does-not-exist -n deploy-demo
kubectl rollout status deployment/nginx-deployment -n deploy-demo ; echo "exit=$?"
#   error: deployment "nginx-deployment" exceeded its progress deadline
#   exit=1                                        <- CI pipelines rely on this exit code
kubectl get deploy nginx-deployment -n deploy-demo -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.reason}{"\n"}{end}'
#   Available=True MinimumReplicasAvailable
#   Progressing=False ProgressDeadlineExceeded
kubectl rollout undo deployment/nginx-deployment -n deploy-demo
```

## Lab 7 – Revision history limit
```bash
kubectl get rs -n deploy-demo | wc -l                     # many old ReplicaSets
kubectl patch deployment nginx-deployment -n deploy-demo -p '{"spec":{"revisionHistoryLimit":1}}'
kubectl get rs -n deploy-demo                             # current + 1 old
```

## Lab 8 – Recreate strategy
```bash
kubectl apply -f 01-recreate.yaml ; kubectl rollout status deploy/recreate-demo -n deploy-demo
kubectl set image deploy/recreate-demo nginx=nginx:1.16.1 -n deploy-demo
kubectl get pods -n deploy-demo -l app=recreate-demo -w
#   all 3 old pods go away (Terminating/Completed) BEFORE any new pod is created
```
Compare the strategy snippets: `strategy-maxsurge.yaml` (1 extra pod during a rollout, no capacity loss) and `strategy-maxunavailable.yaml` (one pod down at a time, no extra pods).

## Lab 9 – Terminating replicas
```bash
kubectl apply -f 02-slow-terminating.yaml ; kubectl rollout status deploy/slow-stop -n deploy-demo
kubectl scale deploy/slow-stop --replicas=1 -n deploy-demo ; sleep 3
kubectl get deploy slow-stop -n deploy-demo -o jsonpath='replicas={.status.replicas} terminating={.status.terminatingReplicas}{"\n"}'
#   replicas=1 terminating=2       <- 2 pods still shutting down (30s grace) and still using resources
```

---

## Useful commands
```bash
kubectl rollout status|history|undo|pause|resume|restart deployment/<name>
kubectl set image deployment/<name> <container>=<image>
kubectl scale deployment/<name> --replicas=N
kubectl get rs -l app=<label> ; kubectl describe deploy <name>
```

## Cleanup
```bash
./cleanup.sh
```
