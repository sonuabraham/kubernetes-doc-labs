# Run a Single-Instance Stateful Application – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/run-application/run-single-instance-stateful-application/

> Runs on the default **minikube** cluster (one node), `default` namespace. Files (docs, **verbatim**): [mysql-pv.yaml](mysql-pv.yaml),
> [mysql-deployment.yaml](mysql-deployment.yaml). The PV is a `hostPath` at `/mnt/data` **inside the minikube node**.
>
> **Found:**
> 1. `ReadWriteOnce` doesn't stop a second Pod. It limits the volume to one **node**, not one Pod. On a single node, a RollingUpdate or
>    `--replicas=2` starts a second mysqld on the same data directory. It loops on `Unable to lock ./ibdata1` and crashes, but shows `1/1 Running`
>    until then, because there's no readiness probe. `ReadWriteOncePod` would enforce one Pod.
> 2. The PVC shows a harmless `ProvisioningFailed … storageclass "manual" not found` event. The binder tries dynamic provisioning before it binds the static PV.
> 3. `kubectl delete pv` leaves `/mnt/data` on the node. A re-run starts with the **old** database and the old root password. [cleanup.sh](cleanup.sh) removes it.

## Key ideas (read first)

| Piece | Why |
|---|---|
| PV (`hostPath`, `storageClassName: manual`) + PVC | the static PV is bound by matching class, size and access mode |
| Deployment `replicas: 1`, `strategy: Recreate` | old Pod stops before the new one starts: never two mysqld on one data dir |
| Headless Service (`clusterIP: None`) | `mysql` resolves straight to the Pod IP |
| Password in plain `env` | insecure; use a Secret ([distribute-credentials-secure](../../inject-data-application/distribute-credentials-secure/)) |

---

## Lab 1 – Deploy (docs)
```bash
cd tasks/run-application/run-single-instance-stateful-application
kubectl apply -f mysql-pv.yaml
kubectl apply -f mysql-deployment.yaml
kubectl rollout status deploy/mysql                # about 1 min the first time (mysql:9 is ~250 MB)
kubectl describe deployment mysql | grep -E 'Replicas|Strategy|Image|Available|Progressing'
#   Replicas:           1 desired | 1 updated | 1 total | 1 available | 0 unavailable
#   StrategyType:       Recreate
#     Image:      mysql:9
kubectl describe pvc mysql-pv-claim
#   StorageClass:  manual
#   Status:        Bound
#   Volume:        mysql-pv-volume
#   Used By:       mysql-6b4f58b4b5-vkthl
#   Unused   False   …   PodUsingPVC   A pod is currently referencing this PVC
#   Warning  ProvisioningFailed  persistentvolume-controller  storageclass.storage.k8s.io "manual" not found   <- harmless
```

## Lab 2 – Connect, and the data survives (docs + extras)
The docs' `kubectl run -it … mysql -h mysql -ppassword` gives an interactive prompt. Non-interactive version:
```bash
kubectl run -i --rm --image=mysql:9 --restart=Never mysql-client -- mysql -h mysql -ppassword -e \
  "CREATE DATABASE labdb; CREATE TABLE labdb.t (msg VARCHAR(50)); INSERT INTO labdb.t VALUES ('survives pod deletion'); SELECT VERSION();"
#   VERSION()
#   9.7.4
kubectl delete pod -l app=mysql
kubectl rollout status deploy/mysql
kubectl run -i --rm --image=mysql:9 --restart=Never mysql-client -- mysql -h mysql -ppassword -e "SELECT * FROM labdb.t"
#   msg
#   survives pod deletion          <- (retry for a few seconds: the Pod is Ready before mysqld is)
minikube ssh -- sudo ls /mnt/data  # ibdata1  labdb  mysql  binlog.000003 …
```

## Lab 3 – Why Recreate and one replica (not from the docs)
```bash
kubectl patch deployment mysql --type=json -p='[{"op":"replace","path":"/spec/strategy","value":{"type":"RollingUpdate","rollingUpdate":{"maxSurge":1,"maxUnavailable":0}}}]'
kubectl set env deployment/mysql LAB=rolling
kubectl logs deploy/mysql | grep -E 'lock|ready for connections'
#   [ERROR] [MY-012574] [InnoDB] Unable to lock ./ibdata1 error: 11     <- old mysqld still held the files
#   /usr/sbin/mysqld: ready for connections …                           <- lucky: the old Pod was killed at once (no readiness probe)
kubectl scale deploy/mysql --replicas=2
kubectl get pods -l app=mysql                    # both 1/1 Running   <- RWO allowed the 2nd Pod (same node)
kubectl logs <newest-pod> | grep -c 'Unable to lock'     # keeps rising (~1 per second) …
kubectl logs <newest-pod> --previous | grep ERROR | tail -3
#   [ERROR] [MY-010334] [Server] Failed to initialize DD Storage Engine
#   [ERROR] [MY-010020] [Server] Data Dictionary initialization failed.
#   [ERROR] [MY-010119] [Server] Aborting         <- after ~100 s; then restarts, and the cycle repeats
kubectl scale deploy/mysql --replicas=1
```
The headless Service also returned the broken Pod's IP the whole time. For replicated databases use a StatefulSet
([run-replicated-stateful-application](../run-replicated-stateful-application/)).

## Cleanup
```bash
./cleanup.sh      # also deletes /mnt/data on the node
```
