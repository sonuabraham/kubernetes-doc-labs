# Operator Pattern – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/extend-kubernetes/operator/

> The page describes a **SampleDB** operator in 7 steps and gives two commands (`kubectl get SampleDB`, `kubectl edit SampleDB/example-database`). This lab **builds that operator** for real, mapping each docs step to a file:
>
> | Docs step | Here |
> |---|---|
> | 1. A custom resource named SampleDB | [00-sampledb-crd.yaml](00-sampledb-crd.yaml): `spec.version`, `storage`, `backupSchedule`; status subresource; printer columns Wanted/Running/Phase |
> | 2. A Deployment running the controller | [01-operator.yaml](01-operator.yaml): namespace `sampledb-system`, ServiceAccount + RBAC, Deployment |
> | 3. A container image of the operator code | `python:3.12-slim` + [sampledb_operator.py](sampledb_operator.py) from a ConfigMap ([deploy.sh](deploy.sh)) |
> | 4./5. Query SampleDBs, make reality match: PVCs, StatefulSet, initial-config Job | Secret, headless Service, StatefulSet (postgres + PVC), Job `<db>-init` |
> | 5. On delete: snapshot, then remove StatefulSet and volumes | finalizer → Job `<db>-final-snapshot` into PVC `<db>-snapshots` (kept) → data PVCs deleted → garbage collection |
> | 6. Regular backups using a Secret | CronJob `<db>-backup` (pg_dump, credentials from the Secret) |
> | 7. Upgrade old versions with Jobs | version change → rolling StatefulSet → Job `<db>-upgrade-<version>` verifies and migrates |
>
> [02-example-database.yaml](02-example-database.yaml) is the docs' `example-database`. [03-read-snapshot.yaml](03-read-snapshot.yaml) reads the snapshot that's left behind. The operator is ~210 lines of stdlib Python that talks REST to the API server.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Operator** | Custom resource + custom controller, encoding a human operator's knowledge (deploy, back up, upgrade, recover) in code. It extends Kubernetes **without changing Kubernetes**. |
| **Controller loop** | Read desired state (the SampleDB), compare with reality, act, update `status`. **Level-triggered**: every pass recomputes everything, so missed events and drift both get fixed. This one resyncs every 5s; real ones use watches + work queues (client-go informers, controller-runtime). |
| **Server-side apply** | Declare the full object you want on every pass (`PATCH application/apply-patch+yaml`, `fieldManager`). Idempotent, and it only owns the fields it sets. |
| **ownerReferences** | Everything the operator creates points at the SampleDB, so the **garbage collector** deletes it when the SampleDB goes. |
| **Finalizers** | Let the operator do work **before** deletion completes (here: a final snapshot). |
| **status subresource** | The operator reports `phase`, `version` (actually running), `observedGeneration`, and emits **Events**. |
| **Deploying / using** | CRD + controller (usually a Deployment, outside the control plane). Users just create, edit and delete the custom resource. |
| **Frameworks** | kubebuilder / Operator SDK (Go), Kopf (Python), kube-rs, Java Operator SDK, Metacontroller, shell-operator… |

---

## Step 1 – Install the operator
```bash
cd concepts/extend-kubernetes/operator
./deploy.sh                       # CRD, code ConfigMap, RBAC, Deployment
kubectl logs -n sampledb-system deploy/sampledb-operator
#   09:36:43 sampledb-operator started, resync every 5s
```

## Lab 1 – Use it: `kubectl get SampleDB`
```bash
kubectl create ns db-demo
kubectl apply -f 02-example-database.yaml
kubectl get SampleDB -n db-demo                  # the docs' command (also: sampledbs, sdb)
#   NAME               WANTED   RUNNING   PHASE   READY   AGE
#   example-database   16.4     16.4      Ready   1       10s        <- ~10-30s from create to Ready
kubectl get sts,svc,secret,job,cronjob,pvc -n db-demo -o name
#   statefulset.apps/example-database          service/example-database      secret/example-database-credentials
#   job.batch/example-database-init            cronjob.batch/example-database-backup
#   persistentvolumeclaim/data-example-database-0
kubectl exec example-database-0 -n db-demo -- psql -U postgres -d app -tAc 'SELECT * FROM items'
#   1|created by the init Job
kubectl describe sdb example-database -n db-demo | tail -4
#   Normal  Created  ...  sampledb-operator  Secret example-database-credentials
#   Normal  Ready    ...  sampledb-operator  postgres 16.4 is ready
```

## Lab 2 – Regular backups
```bash
kubectl get jobs -n db-demo | grep backup             # one per minute (backupSchedule "*/1 * * * *")
kubectl logs job/$(kubectl get jobs -n db-demo -o name | grep backup | head -1 | cut -d/ -f2) -n db-demo
#   backup 2026-11-12T09:38:00Z: 1797 bytes, 91 lines
```

## Lab 3 – It keeps things in good shape
```bash
kubectl delete sts example-database -n db-demo        # "accident"
#   recreated within ~5s (next resync); the PVC was retained, so the data is still there:
kubectl exec example-database-0 -n db-demo -- psql -U postgres -d app -tAc 'SELECT * FROM items'     # 1|created by the init Job
```

## Lab 4 – `kubectl edit SampleDB/example-database`: an upgrade
```bash
kubectl edit SampleDB/example-database -n db-demo     # set spec.version: "16.6"  (or:)
kubectl patch sdb example-database -n db-demo --type=merge -p '{"spec":{"version":"16.6"}}'
kubectl get sdb -n db-demo -w
#   example-database   16.6   16.4   Upgrading   ...
#   example-database   16.6   16.6   Ready       1                    <- 12-40s, mostly the image pull
kubectl logs job/example-database-upgrade-16-6 -n db-demo
#   PostgreSQL 16.6 on x86_64-pc-linux-musl, compiled by gcc (Alpine 14.2.0) 14.2.0, 64-bit
#   ALTER TABLE
#   UPDATE 1
kubectl exec example-database-0 -n db-demo -- psql -U postgres -d app -tAc 'SELECT * FROM items'     # 1|created by the init Job|16.6
```

## Lab 5 – Delete: snapshot first, then clean up
```bash
kubectl delete sdb example-database -n db-demo        # returns in ~10s
kubectl get events -n db-demo --field-selector involvedObject.kind=SampleDB --sort-by=.lastTimestamp -o custom-columns=REASON:.reason,MSG:.message | tail -4
#   Upgraded         now running 16.6 (Job example-database-upgrade-16-6 verified it)
#   FinalSnapshot    taking a final snapshot into PVC example-database-snapshots before deleting
#   VolumesDeleted   deleted data PVCs of example-database; snapshot kept in PVC example-database-snapshots
kubectl get all,pvc,secret -n db-demo
#   only job/example-database-final-snapshot and pvc/example-database-snapshots remain
kubectl apply -f 03-read-snapshot.yaml ; kubectl logs read-snapshot -n db-demo
#   -rw-r--r--  1 root root 1837 Nov 12 09:38 final-20261112-093856.sql
#   COPY public.items (id, name, migrated_to) FROM stdin;
#   1	created by the init Job	16.6
```

## Bugs found while building it (operator lessons)
Each of these happened during testing and is fixed in the code:

| Symptom | Cause / fix |
|---|---|
| Pod crash: `cannot import name 'eq' from partially initialized module 'operator'` | The file was called `operator.py`, which shadows Python's stdlib module. Renamed to `sampledb_operator.py`. |
| Deleting the StatefulSet **lost the data** | `persistentVolumeClaimRetentionPolicy.whenDeleted: Delete` takes the PVC with it. Now `Retain`, and the operator deletes the PVCs itself, only when the **SampleDB** is deleted. |
| Data PVC never deleted, yet the event said "VolumesDeleted" | A collection DELETE needs the **`deletecollection`** verb (403), and the response wasn't checked. Added the verb, and the code now checks the result and keeps the finalizer on failure. |
| `Job ... spec.template: field is immutable` after the upgrade | The init Job was server-side-applied on every pass, and the new image changed its template. Jobs are now **created once** (409 = already exists). |
| `kubectl delete ns db-demo` hung forever | The finalizer tried to create the snapshot Job in a **terminating namespace** ("unable to create new content in namespace db-demo because it is being terminated"): a deadlock. The operator now detects `Terminating`, emits a `SnapshotSkipped` Warning and releases the finalizer. |
| Deleting the credentials Secret | It's recreated (drift repair) with a **new random password**, but an existing database keeps the old one. A real operator must store or derive credentials so they can be repaired, or refuse. Not fixed here. Seen: the Secret came back within ~1s. Expected but **not tested**: backups and Jobs then fail authentication. |

---

## Useful commands
```bash
kubectl get SampleDB -A ; kubectl describe sdb <name> -n <ns>
kubectl logs -n sampledb-system deploy/sampledb-operator -f
kubectl get all,pvc,secret -n <ns> -l sampledb=<name>
```

## Cleanup
```bash
./cleanup.sh        # SampleDBs first (operator still running, so finalizers finish), then namespace, operator, CRD
```
