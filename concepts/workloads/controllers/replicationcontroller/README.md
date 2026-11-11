# ReplicationController – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/workloads/controllers/replicationcontroller/

> **Legacy.** A Deployment that configures a ReplicaSet is the recommended way to set up replication. This lab shows what the RC does and what it lacks.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **ReplicationController** | Keeps a specified number of Pod replicas running: too many → kill, too few → start. API group **core `v1`** (not `apps`). |
| **Selector** | **Equality-based only** (a plain map). ReplicaSet adds set-based `matchExpressions`. If omitted, it defaults to the template's labels. |
| **Delete** | `kubectl delete rc` scales to 0 and deletes the pods. `--cascade=orphan` keeps them. |
| **Isolate** | Change a pod's labels and the RC replaces it. |
| **Patterns** | Rescheduling (node failure), scaling, **rolling updates done by the client** (new RC up, old RC down), **multiple release tracks** behind one Service. |
| **Responsibilities** | Only "N pods matching the selector". No readiness or liveness logic, no autoscaling, no rollout history. Those live in other components. |
| **Alternatives** | ReplicaSet (set-based selectors), **Deployment (recommended)**: server-side rolling updates and rollback. |

## The demo app
[replication.yaml](replication.yaml) is the docs manifest **verbatim**: RC `nginx`, 3 replicas. Extra (namespace `rc-demo`): [01-tracks.yaml](01-tracks.yaml) (`web-stable` ×3 + `web-canary` ×1 behind one Service) and [02-set-based-selector.yaml](02-set-based-selector.yaml) (invalid).

---

## Lab 1 – The docs walk-through
```bash
cd concepts/workloads/controllers/replicationcontroller
kubectl apply -f 00-namespace.yaml
kubectl apply -f replication.yaml -n rc-demo          # (docs: kubectl apply -f https://k8s.io/examples/controllers/replication.yaml)
kubectl describe replicationcontrollers/nginx -n rc-demo | grep -E 'Selector|Replicas|Pods Status'
#   Selector:     app=nginx
#   Replicas:     3 current / 3 desired
#   Pods Status:  3 Running / 0 Waiting / 0 Succeeded / 0 Failed
pods=$(kubectl get pods -n rc-demo --selector=app=nginx --output=jsonpath={.items..metadata.name}) ; echo $pods
#   nginx-7hkrl nginx-xk66z nginx-z68d5
```

## Lab 2 – Scale, delete only the RC
```bash
kubectl scale rc nginx --replicas=5 -n rc-demo ; kubectl get rc nginx -n rc-demo      # 5 5 5
kubectl delete rc nginx -n rc-demo --cascade=orphan
kubectl get pods -n rc-demo -l app=nginx                                              # 5 pods, now unmanaged
kubectl apply -f replication.yaml -n rc-demo          # a new RC with the same selector ADOPTS them, then trims to 3
```

## Lab 3 – Equality selectors only
```bash
kubectl apply -f 02-set-based-selector.yaml
#   Error from server (BadRequest): ... cannot be handled as a ReplicationController: json: cannot unmarshal array into ... selector of type map[string]string
```
That's the main API difference from ReplicaSet (`kubectl explain rc.spec.selector` vs `kubectl explain rs.spec.selector`).

## Lab 4 – Multiple release tracks behind one Service
```bash
kubectl apply -f 01-tracks.yaml ; kubectl wait --for=condition=Ready pod -l app=web -n rc-demo --timeout=90s
kubectl run c -n rc-demo --restart=Never --image=busybox:1.36 -- sh -c 'for i in $(seq 40); do wget -qO- web/hostname; echo; done'
kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/c -n rc-demo ; kubectl logs c -n rc-demo | sed 's/-[a-z0-9]*$//' | sort | uniq -c
#   10 web-canary        <- 1 of 4 pods
#   30 web-stable        <- 3 of 4 pods - traffic split by replica count
```
The Service selects `app=web`. Each RC selects `app=web` **plus** its own `track`, so the RCs never fight over each other's pods.

## Lab 5 – A "rolling update" by hand
```bash
kubectl scale rc web-canary --replicas=2 -n rc-demo ; kubectl scale rc web-stable --replicas=2 -n rc-demo
kubectl scale rc web-canary --replicas=3 -n rc-demo ; kubectl scale rc web-stable --replicas=1 -n rc-demo
kubectl scale rc web-canary --replicas=4 -n rc-demo ; kubectl scale rc web-stable --replicas=0 -n rc-demo
kubectl delete rc web-stable -n rc-demo
```
Every step is **your** job, with no readiness gating, no history and no `undo`. A Deployment does all this server-side with `kubectl set image` (`../deployment`).

## Lab 6 – Field selector support
```bash
kubectl get rc -n rc-demo --field-selector status.replicas=3 -o name      # works for RCs (not for ReplicaSets on v1.37 - see field-selectors lab)
```

---

## Useful commands
```bash
kubectl get rc ; kubectl describe rc <name>
kubectl scale rc <name> --replicas=N
kubectl delete rc <name> [--cascade=orphan]
```

## Cleanup
```bash
./cleanup.sh
```
