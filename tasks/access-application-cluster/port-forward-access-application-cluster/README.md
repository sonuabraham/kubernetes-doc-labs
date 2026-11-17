# Use Port Forwarding to Access Applications in a Cluster – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/access-application-cluster/port-forward-access-application-cluster/

> Runs on the default **minikube** cluster, `default` namespace. Files (docs, **verbatim**): [mongo-deployment.yaml](mongo-deployment.yaml),
> [mongo-service.yaml](mongo-service.yaml). Not from the docs: [rbac-portforward.yaml](rbac-portforward.yaml).
> No local `mongosh` needed: `docker run --rm --network host mongo:7 mongosh …` reaches the forwarded port on 127.0.0.1.
>
> **Found:**
> 1. `port-forward service/mongo` doesn't load-balance. kubectl picks **one** Pod when it starts. If that Pod dies, the forward exits with
>    `error: lost connection to pod`, even though the Service still has other Pods (Lab 3).
> 2. `kubectl auth can-i create pods/portforward` says **no** even when it's allowed. Subresources need `--subresource=portforward`.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| Path | your machine → API server → kubelet → Pod port (tunnel; no Service, no NodePort needed) |
| Targets | `pod/…`, `deployment/…`, `replicaset/…`, `service/…`: all resolve to **one** Pod at start |
| Local port | `28015:27017` fixed, `:27017` = random free port; listens on 127.0.0.1 and [::1] (`--address` to change) |
| TCP only | no UDP |
| RBAC | `get` on `pods` + `create` on `pods/portforward` (+ `get` on the deployment/service if you name one) |

---

## Lab 1 – MongoDB (docs)
```bash
cd tasks/access-application-cluster/port-forward-access-application-cluster
kubectl apply -f mongo-deployment.yaml          # deployment.apps/mongo created
kubectl apply -f mongo-service.yaml             # service/mongo created
kubectl get pods,rs -l app.kubernetes.io/name=mongo
#   mongo-96649f476-qr88p   1/1   Running        mongo-96649f476   1   1   1
kubectl get service mongo                       # ClusterIP 10.96.84.202   27017/TCP
kubectl get pod mongo-96649f476-qr88p --template='{{(index (index .spec.containers 0).ports 0).containerPort}}{{"\n"}}'    # 27017
```

## Lab 2 – Forward and ping (docs)
```bash
kubectl port-forward mongo-96649f476-qr88p 28015:27017        # or pods/…, deployment/mongo, replicaset/mongo-96649f476, service/mongo
#   Forwarding from 127.0.0.1:28015 -> 27017
#   Forwarding from [::1]:28015 -> 27017
# second terminal:
docker run --rm -it --network host mongo:7 mongosh --port 28015     # docs: mongosh --port 28015
#   test> db.runCommand( { ping: 1 } )
#   { ok: 1 }
```
All five target forms gave `{"ok":1}` in this lab.
```bash
kubectl port-forward deployment/mongo :27017
#   Forwarding from 127.0.0.1:44909 -> 27017      <- random free port
```

## Lab 3 – A Service forward is pinned to one Pod (not from the docs)
```bash
kubectl scale deploy/mongo --replicas=2
kubectl port-forward service/mongo 28015:27017 &
docker run --rm --network host mongo:7 mongosh --quiet --port 28015 --eval 'db.hostInfo().system.hostname'
#   mongo-96649f476-qpjmn        <- every connection goes to this Pod
kubectl delete pod mongo-96649f476-qpjmn
#   (port-forward prints)  error: lost connection to pod     … and exits
docker run --rm --network host mongo:7 mongosh --quiet 'mongodb://127.0.0.1:28015/?serverSelectionTimeoutMS=3000' --eval 1
#   MongoNetworkError: connect ECONNREFUSED 127.0.0.1:28015
kubectl scale deploy/mongo --replicas=1
```

## Lab 4 – Who may port-forward (docs "Authorization", tested)
```bash
kubectl apply -f rbac-portforward.yaml          # SA pf-user: get/list pods only; Role pod-port-forwarder not bound yet
AS=--as=system:serviceaccount:default:pf-user
kubectl port-forward $AS pod/<mongo-pod> 28015:27017
#   error: error upgrading connection: pods "mongo-…" is forbidden: User "system:serviceaccount:default:pf-user" cannot create resource "pods/portforward" …
kubectl create rolebinding pf-user-port-forwarder --role=pod-port-forwarder --serviceaccount=default:pf-user
kubectl auth can-i create pods --subresource=portforward $AS     # yes
kubectl auth can-i create pods/portforward $AS                   # no   <- wrong syntax, misleading
kubectl port-forward $AS pod/<mongo-pod> 28015:27017             # Forwarding from 127.0.0.1:28015 -> 27017
kubectl port-forward $AS deployment/mongo 28015:27017
#   Error from server (Forbidden): deployments.apps "mongo" is forbidden: … cannot get resource "deployments" …
```

## Cleanup
```bash
./cleanup.sh
```
