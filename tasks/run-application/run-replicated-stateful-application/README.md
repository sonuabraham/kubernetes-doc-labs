# Run a Replicated Stateful Application – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/run-application/run-replicated-stateful-application/

> Runs on the default **minikube** cluster (one node, `standard` StorageClass), `default` namespace. Files (docs, **verbatim**):
> [mysql-configmap.yaml](mysql-configmap.yaml), [mysql-services.yaml](mysql-services.yaml), [mysql-statefulset.yaml](mysql-statefulset.yaml).
> Not from the docs: [convert-xtrabackup-image.sh](convert-xtrabackup-image.sh).
>
> **Found:**
> 1. `gcr.io/google-samples/xtrabackup:1.0` is a Docker **schema 1** image. containerd ≥ 2.1 (minikube 1.37) and Docker ≥ 29 can't pull it
>    (`media type "application/vnd.docker.distribution.manifest.v1+prettyjws" is no longer supported`), so every Pod would sit in `Init:ErrImagePull`.
>    [convert-xtrabackup-image.sh](convert-xtrabackup-image.sh) converts it with skopeo and loads it into minikube under the same name, so the YAML stays unchanged.
> 2. "Break the readiness probe" with `mv /usr/bin/mysql /usr/bin/mysql.off` **does nothing** now. A missing binary is a probe *error*
>    (`Readiness probe errored and resulted in unknown state … executable file not found in $PATH`), not a failure, and the kubelet keeps
>    the old Ready state. `mysql-2` stayed `2/2` for 23 hours. Lab 3 uses a stub that `exit 1`s instead.
> 3. "Drain a Node" needs several nodes. On one-node minikube, Lab 4 does cordon + delete to show the same scheduling step.

## Key ideas (read first)

| Piece | Role |
|---|---|
| Headless Service `mysql` | stable DNS per Pod: `mysql-0.mysql` = primary, used for writes |
| Service `mysql-read` | ClusterIP over all **Ready** Pods, used for reads |
| `init-mysql` | ordinal from hostname → `server-id = 100 + ordinal`; `primary.cnf` (log-bin) for 0, `replica.cnf` (super-read-only) for others |
| `clone-mysql` | on an empty PVC, stream a backup from Pod `N-1` (`ncat … 3307 | xbstream`) |
| `xtrabackup` sidecar | starts replication from the clone position, then serves backups on 3307 |
| Ordered start | Pod N+1 starts only after Pod N is Ready, so a clone source always exists |
| PVCs | `data-mysql-N` from `volumeClaimTemplates`; kept on scale-down |

---

## Step 0 – Make the xtrabackup image pullable (not from the docs)
```bash
cd tasks/run-application/run-replicated-stateful-application
./convert-xtrabackup-image.sh
#   … Writing manifest to image destination
#   gcr.io/google-samples/xtrabackup   1.0   c415dbd7af07a   273MB
```

## Lab 1 – Deploy (docs)
```bash
kubectl apply -f mysql-configmap.yaml
kubectl apply -f mysql-services.yaml
kubectl apply -f mysql-statefulset.yaml
kubectl rollout status sts/mysql            # ~35 s with images cached
kubectl get pods -l app=mysql
#   mysql-0   2/2   Running   0   35s
#   mysql-1   2/2   Running   0   24s        <- one after another
#   mysql-2   2/2   Running   0   12s
kubectl get pvc -l app=mysql                # data-mysql-0..2  Bound  10Gi  RWO  standard
```

## Lab 2 – Client traffic (docs + extras)
```bash
kubectl run mysql-client --image=mysql:5.7 -i --rm --restart=Never -- mysql -h mysql-0.mysql <<EOF
CREATE DATABASE test;
CREATE TABLE test.messages (message VARCHAR(250));
INSERT INTO test.messages VALUES ('hello');
EOF
kubectl run mysql-client --image=mysql:5.7 -i --rm --restart=Never -- mysql -h mysql-read -e "SELECT * FROM test.messages"
#   message
#   hello
```
Not from the docs:
```bash
kubectl run mysql-w --image=mysql:5.7 --restart=Never -- mysql -h mysql-1.mysql -e "INSERT INTO test.messages VALUES ('x')"
kubectl logs mysql-w
#   ERROR 1290 (HY000) at line 1: The MySQL server is running with the --super-read-only option so it cannot execute this statement
kubectl run mysql-client --image=mysql:5.7 -i --rm --restart=Never -- mysql -h mysql-2.mysql -e "SHOW SLAVE STATUS\G" | grep -E 'Master_Host|Running:|Behind'
#   Master_Host: mysql-0.mysql   Slave_IO_Running: Yes   Slave_SQL_Running: Yes   Seconds_Behind_Master: 0
kubectl logs mysql-1 -c xtrabackup | grep 'CHANGE MASTER'
#   + echo 'CHANGE MASTER TO MASTER_LOG_FILE='\''mysql-0-bin.000003'\'',        MASTER_LOG_POS=154'
```
The server-id loop (docs use `-i -t` + `bash -ic`; this version runs in the background):
```bash
kubectl run mysql-loop --image=mysql:5.7 --restart=Never -- bash -c "while sleep 1; do mysql -h mysql-read -N -e 'SELECT @@server_id'; done"
kubectl logs mysql-loop | sort | uniq -c          #   4 100   6 101   5 102
```

## Lab 3 – Readiness (docs, fixed)
```bash
kubectl exec mysql-2 -c mysql -- mv /usr/bin/mysql /usr/bin/mysql.off      # the docs' way
kubectl get pod mysql-2                                                       # still 2/2 …
kubectl get events --field-selector involvedObject.name=mysql-2,reason=Unhealthy -o jsonpath='{.items[-1:].message}'
#   Readiness probe errored and resulted in unknown state: … exec: "mysql": executable file not found in $PATH
kubectl exec mysql-2 -c mysql -- sh -c 'printf "#!/bin/sh\nexit 1\n" > /usr/bin/mysql; chmod +x /usr/bin/mysql'   # a real failure
kubectl get pod mysql-2                                                       # 1/2   (within ~6 s: 3 × 2 s)
kubectl logs mysql-loop --tail=12 | sort | uniq -c                            #   6 100   6 101    <- no 102
kubectl exec mysql-2 -c mysql -- mv /usr/bin/mysql.off /usr/bin/mysql         # repair (overwrites the stub)
kubectl logs mysql-loop --tail=12 | sort | uniq -c                            #   5 100   2 101   5 102
```

## Lab 4 – Delete a Pod; "drain" on one node (docs, adapted)
```bash
kubectl delete pod mysql-2            # ~30 s: mysqld shuts down cleanly
kubectl get pod mysql-2               # new mysql-2, same PVC data-mysql-2, no clone (data already there)
kubectl cordon minikube
kubectl delete pod mysql-2
kubectl get pod mysql-2               # Pending
#   FailedScheduling: 0/1 nodes are available: 1 node(s) were unschedulable. …
kubectl uncordon minikube
kubectl get pod mysql-2 -o wide       # 2/2 Running again
```
On a multi-node cluster `kubectl drain <node> --force --delete-emptydir-data --ignore-daemonsets` moves the Pod. That works only if
the PV can follow it: minikube's hostpath volumes can't, cloud disks can (within a zone).

## Lab 5 – Scale (docs)
```bash
kubectl scale statefulset mysql --replicas=5
kubectl logs mysql-loop --tail=30 | sort | uniq -c       # 103 and 104 appear
kubectl run mysql-client --image=mysql:5.7 -i --rm --restart=Never -- mysql -h mysql-3.mysql -e "SELECT * FROM test.messages"
#   hello                                               <- cloned data from before it existed
kubectl logs mysql-4 -c clone-mysql | grep ncat         # + ncat --recv-only mysql-3.mysql 3307   <- clones from N-1
kubectl scale statefulset mysql --replicas=3
kubectl get pvc -l app=mysql                            # still 5 PVCs (data-mysql-3, -4 kept)
```

## Cleanup
```bash
./cleanup.sh      # the docs' steps: loop pod, StatefulSet, then configmap,service,pvc -l app=mysql
```
