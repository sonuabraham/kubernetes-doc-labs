# Run a Stateless Application Using a Deployment – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/run-application/run-stateless-application-deployment/

> Runs on the default **minikube** cluster, `default` namespace. Files (docs, **verbatim**): [deployment.yaml](deployment.yaml),
> [deployment-update.yaml](deployment-update.yaml), [deployment-scale.yaml](deployment-scale.yaml).
>
> **Found:** the sample `describe` output is from 2016. Now the Deployment has `Labels: <none>` (the manifest sets labels only on the
> Pod template), the default strategy is `25% max unavailable, 25% max surge` (not `1`/`1`), and ReplicaSet names use a 10-character hash.

## Key ideas (read first)

| Object | Role |
|---|---|
| Deployment | desired state: template + replicas + strategy; keeps a revision history |
| ReplicaSet | one per template version (`pod-template-hash` label); the Deployment scales old down / new up |
| `kubectl apply` of a file | sets **every** field in it: applying a 2-replica file after scaling to 4 brings you back to 2 |
| ReplicationController | the old way; no rollouts. Use Deployments |

---

## Lab 1 – Create and inspect (docs)
```bash
cd tasks/run-application/run-stateless-application-deployment
kubectl apply -f deployment.yaml
kubectl rollout status deploy/nginx-deployment
kubectl describe deployment nginx-deployment
#   Labels:                 <none>
#   Annotations:            deployment.kubernetes.io/revision: 1
#   Replicas:               2 desired | 2 updated | 2 total | 2 available | 0 unavailable
#   RollingUpdateStrategy:  25% max unavailable, 25% max surge
#   NewReplicaSet:   nginx-deployment-54fd4d6d4c (2/2 replicas created)
#   Normal  ScalingReplicaSet  … Scaled up replica set nginx-deployment-54fd4d6d4c from 0 to 2
kubectl get pods -l app=nginx
#   nginx-deployment-54fd4d6d4c-9rfbm   1/1   Running
#   nginx-deployment-54fd4d6d4c-vmpnk   1/1   Running
kubectl describe pod <pod-name>
```

## Lab 2 – Update (docs)
```bash
kubectl apply -f deployment-update.yaml
kubectl get pods -l app=nginx -L pod-template-hash
#   nginx-deployment-54fd4d6d4c-9rfbm   1/1   Running             54fd4d6d4c
#   nginx-deployment-54fd4d6d4c-vmpnk   1/1   Running             54fd4d6d4c
#   nginx-deployment-76df5b8bb8-zhljf   0/1   ContainerCreating   76df5b8bb8   <- surge pod from the new ReplicaSet
kubectl rollout status deploy/nginx-deployment
kubectl get rs -l app=nginx
#   nginx-deployment-54fd4d6d4c   0   0   0      <- old RS kept (scaled to 0) for rollback
#   nginx-deployment-76df5b8bb8   2   2   2
kubectl rollout history deploy/nginx-deployment     # revisions 1 and 2
```

## Lab 3 – Scale (docs)
```bash
kubectl apply -f deployment-scale.yaml
kubectl get pods -l app=nginx                       # 4 pods, all 76df5b8bb8 (same template, so no new ReplicaSet)
```

## Lab 4 – Pitfall and rollback (not from the docs)
```bash
kubectl apply -f deployment-update.yaml
kubectl get deploy nginx-deployment                 # 2/2   <- the file says replicas: 2, so apply scaled back down
kubectl rollout undo deploy/nginx-deployment
kubectl get deploy nginx-deployment -o jsonpath='{.spec.template.spec.containers[0].image}'    # nginx:1.14.2
kubectl rollout history deploy/nginx-deployment     # revisions 2 and 3   <- rev 1 was re-used as rev 3
```
If something else (an HPA, `kubectl scale`) owns `replicas`, leave the field out of the file you apply.

## Lab 5 – Delete (docs)
```bash
kubectl delete deployment nginx-deployment
kubectl get rs,pods -l app=nginx                    # ReplicaSets gone at once; pods terminating, then gone (cascading delete)
```

## Cleanup
```bash
./cleanup.sh
```
