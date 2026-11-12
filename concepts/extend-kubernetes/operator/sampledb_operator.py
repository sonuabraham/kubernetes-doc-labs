#!/usr/bin/env python3
"""SampleDB operator - the docs' example, made real (Python stdlib only, talks REST to the API server).

For each SampleDB (sampledb.example.com/v1) it reconciles, with server-side apply:
  Secret <db>-credentials (created once)    Service <db> (headless, 5432)
  StatefulSet <db> (postgres:<version>-alpine + PVC)   Job <db>-init (initial configuration)
  CronJob <db>-backup (regular backups using the Secret)
  Upgrades: when the running version differs from spec.version, it rolls the StatefulSet and then
            runs Job <db>-upgrade-<version> to verify / migrate.
  Deletion: finalizer sampledb.example.com/final-snapshot -> Job <db>-final-snapshot dumps the DB into
            PVC <db>-snapshots (NOT owned, so it survives), the operator deletes the data PVCs, then removes
            the finalizer and garbage collection deletes everything owned by the SampleDB.
Level-triggered: every RESYNC seconds it lists all SampleDBs and reconciles each one. Running it twice is
harmless, and it repairs anything that drifted (try deleting the StatefulSet).
"""
import json, os, ssl, time, secrets, urllib.request, urllib.error, datetime

API = "https://kubernetes.default.svc"
SA = "/var/run/secrets/kubernetes.io/serviceaccount"
TOKEN = open(f"{SA}/token").read() if os.path.exists(f"{SA}/token") else ""
CTX = ssl.create_default_context(cafile=f"{SA}/ca.crt") if os.path.exists(f"{SA}/ca.crt") else None
G, V, PLURAL = "sampledb.example.com", "v1", "sampledbs"
FINALIZER = "sampledb.example.com/final-snapshot"
MANAGER = "sampledb-operator"
RESYNC = int(os.environ.get("RESYNC", "5"))


def log(*a):
    print(time.strftime("%H:%M:%S"), *a, flush=True)


def api(method, path, body=None, ctype="application/json"):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(API + path, data=data, method=method,
                                 headers={"Authorization": f"Bearer {TOKEN}", "Content-Type": ctype, "Accept": "application/json"})
    try:
        with urllib.request.urlopen(req, context=CTX, timeout=30) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"{}")


def apply(path, obj):
    """Server-side apply: declare the whole object, the API server merges, we own the fields."""
    code, out = api("PATCH", f"{path}?fieldManager={MANAGER}&force=true", obj, "application/apply-patch+yaml")
    if code >= 300:
        log(f"  apply {path} failed: {code} {out.get('message')}")
    return out


def event(db, reason, msg, etype="Normal"):
    ns, now = db["metadata"]["namespace"], datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    api("POST", f"/api/v1/namespaces/{ns}/events", {
        "metadata": {"generateName": db["metadata"]["name"] + "."},
        "involvedObject": {"apiVersion": f"{G}/{V}", "kind": "SampleDB", "name": db["metadata"]["name"],
                           "namespace": ns, "uid": db["metadata"]["uid"]},
        "reason": reason, "message": msg, "type": etype, "firstTimestamp": now, "lastTimestamp": now, "count": 1,
        "source": {"component": MANAGER}})
    log(f"  [{db['metadata']['name']}] {reason}: {msg}")


def pg_env(name):
    return [{"name": "PGHOST", "value": name}, {"name": "PGUSER", "value": "postgres"}, {"name": "PGDATABASE", "value": "app"},
            {"name": "PGPASSWORD", "valueFrom": {"secretKeyRef": {"name": f"{name}-credentials", "key": "password"}}}]


def job(name, ns, jobname, script, image, owner, volumes=None, mounts=None):
    spec = {"backoffLimit": 6, "ttlSecondsAfterFinished": 3600, "template": {"spec": {"restartPolicy": "OnFailure",
            "containers": [{"name": "run", "image": image, "command": ["sh", "-c", script], "env": pg_env(name),
                            "volumeMounts": mounts or []}], "volumes": volumes or []}}}
    meta = {"name": jobname, "namespace": ns, "labels": {"sampledb": name}}
    if owner:
        meta["ownerReferences"] = [owner]
    # Create once, never re-apply: a Job's Pod template is immutable, so applying it again with a new image
    # (e.g. after an upgrade) fails with "spec.template: field is immutable". 409 = already exists = fine.
    code, out = api("POST", f"/apis/batch/v1/namespaces/{ns}/jobs", {"apiVersion": "batch/v1", "kind": "Job", "metadata": meta, "spec": spec})
    if code not in (201, 409):
        log(f"  create job {jobname} failed: {code} {out.get('message')}")
    return out


def job_done(ns, jobname):
    code, j = api("GET", f"/apis/batch/v1/namespaces/{ns}/jobs/{jobname}")
    return code == 200 and j.get("status", {}).get("succeeded", 0) >= 1


def reconcile(db):
    m, spec = db["metadata"], db.get("spec", {})
    name, ns = m["name"], m["namespace"]
    version = spec.get("version", "16.4")
    image = f"postgres:{version}-alpine"
    base = f"/apis/{G}/{V}/namespaces/{ns}/{PLURAL}/{name}"
    owner = {"apiVersion": f"{G}/{V}", "kind": "SampleDB", "name": name, "uid": m["uid"], "controller": True, "blockOwnerDeletion": True}
    status = db.get("status", {})

    # ---- deletion: take a snapshot, then let go -------------------------------------------------
    if m.get("deletionTimestamp"):
        if FINALIZER not in m.get("finalizers", []):
            return
        snap = f"{name}-final-snapshot"
        _, nsobj = api("GET", f"/api/v1/namespaces/{ns}")
        skipped = nsobj.get("status", {}).get("phase") == "Terminating"
        if skipped:
            # The whole namespace is going away: nothing new can be created in it (no snapshot Job, no PVC).
            # Waiting would deadlock the namespace deletion, so give up the snapshot and let go.
            event(db, "SnapshotSkipped", "namespace is terminating - cannot create the snapshot Job; releasing the finalizer", "Warning")
        elif not job_done(ns, snap):
            if status.get("phase") != "Deleting":
                event(db, "FinalSnapshot", f"taking a final snapshot into PVC {name}-snapshots before deleting")
                api("PATCH", base + "/status", {"status": {"phase": "Deleting"}}, "application/merge-patch+json")
            apply(f"/api/v1/namespaces/{ns}/persistentvolumeclaims/{name}-snapshots", {"apiVersion": "v1", "kind": "PersistentVolumeClaim",
                  "metadata": {"name": f"{name}-snapshots", "namespace": ns, "labels": {"sampledb-snapshots": name}},   # no ownerReference: it outlives the DB
                  "spec": {"accessModes": ["ReadWriteOnce"], "resources": {"requests": {"storage": "100Mi"}}}})
            job(name, ns, snap, 'until pg_isready -q; do sleep 1; done; f=/snapshots/final-$(date +%Y%m%d-%H%M%S).sql; '
                'pg_dump > $f && ls -l /snapshots', image, None,
                [{"name": "s", "persistentVolumeClaim": {"claimName": f"{name}-snapshots"}}], [{"name": "s", "mountPath": "/snapshots"}])
            return
        # "makes sure that the StatefulSet and Volumes are also removed": the data PVCs (they carry the Pod
        # labels, sampledb=<name>) are not owned by anything, so the operator deletes them itself.
        code, out = api("DELETE", f"/api/v1/namespaces/{ns}/persistentvolumeclaims?labelSelector=sampledb%3D{name}")
        if code >= 300:      # e.g. 403 without the "deletecollection" verb: keep the finalizer and retry
            event(db, "VolumesNotDeleted", f"{code} {out.get('message')}", "Warning")
            return
        event(db, "VolumesDeleted", f"deleted data PVCs of {name}" + ("" if skipped else f"; snapshot kept in PVC {name}-snapshots"))
        fins = m["finalizers"]
        api("PATCH", base, [{"op": "test", "path": "/metadata/finalizers", "value": fins},
                            {"op": "replace", "path": "/metadata/finalizers", "value": [f for f in fins if f != FINALIZER]}],
            "application/json-patch+json")
        log(f"  [{name}] {'snapshot skipped' if skipped else 'snapshot done'}, finalizer removed -> garbage collector deletes the owned objects")
        return

    # ---- normal reconcile -------------------------------------------------------------------------
    if FINALIZER not in m.get("finalizers", []):
        api("PATCH", base, {"metadata": {"finalizers": m.get("finalizers", []) + [FINALIZER]}}, "application/merge-patch+json")

    code, _ = api("POST", f"/api/v1/namespaces/{ns}/secrets", {"metadata": {"name": f"{name}-credentials", "namespace": ns,
                  "labels": {"sampledb": name}, "ownerReferences": [owner]}, "stringData": {"password": secrets.token_hex(12)}})
    if code == 201:
        event(db, "Created", f"Secret {name}-credentials")

    apply(f"/api/v1/namespaces/{ns}/services/{name}", {"apiVersion": "v1", "kind": "Service",
          "metadata": {"name": name, "namespace": ns, "labels": {"sampledb": name}, "ownerReferences": [owner]},
          "spec": {"clusterIP": "None", "selector": {"sampledb": name}, "ports": [{"name": "pg", "port": 5432}]}})

    sts = apply(f"/apis/apps/v1/namespaces/{ns}/statefulsets/{name}", {"apiVersion": "apps/v1", "kind": "StatefulSet",
          "metadata": {"name": name, "namespace": ns, "labels": {"sampledb": name}, "ownerReferences": [owner]},
          "spec": {"serviceName": name, "replicas": 1, "selector": {"matchLabels": {"sampledb": name}},
                   "persistentVolumeClaimRetentionPolicy": {"whenDeleted": "Retain", "whenScaled": "Retain"},   # data survives a deleted StatefulSet
                   "template": {"metadata": {"labels": {"sampledb": name}}, "spec": {"containers": [{
                       "name": "postgres", "image": image, "ports": [{"containerPort": 5432}],
                       "env": [{"name": "POSTGRES_DB", "value": "app"}, {"name": "PGDATA", "value": "/var/lib/postgresql/data/pgdata"},
                               {"name": "POSTGRES_PASSWORD", "valueFrom": {"secretKeyRef": {"name": f"{name}-credentials", "key": "password"}}}],
                       "readinessProbe": {"exec": {"command": ["pg_isready", "-U", "postgres"]}, "periodSeconds": 3},
                       "volumeMounts": [{"name": "data", "mountPath": "/var/lib/postgresql/data"}]}]}},
                   "volumeClaimTemplates": [{"metadata": {"name": "data"}, "spec": {"accessModes": ["ReadWriteOnce"],
                                             "resources": {"requests": {"storage": spec.get("storage", "1Gi")}}}}]}})

    job(name, ns, f"{name}-init", "until pg_isready -q; do sleep 1; done; psql -v ON_ERROR_STOP=1 -c "
        "\"CREATE TABLE IF NOT EXISTS items(id serial primary key, name text); INSERT INTO items(name) VALUES ('created by the init Job');\"",
        image, owner)

    apply(f"/apis/batch/v1/namespaces/{ns}/cronjobs/{name}-backup", {"apiVersion": "batch/v1", "kind": "CronJob",
          "metadata": {"name": f"{name}-backup", "namespace": ns, "labels": {"sampledb": name}, "ownerReferences": [owner]},
          "spec": {"schedule": spec.get("backupSchedule", "*/5 * * * *"), "successfulJobsHistoryLimit": 2, "concurrencyPolicy": "Forbid",
                   "jobTemplate": {"spec": {"backoffLimit": 2, "template": {"spec": {"restartPolicy": "OnFailure", "containers": [{
                       "name": "backup", "image": image, "env": pg_env(name),
                       "command": ["sh", "-c", 'pg_dump > /tmp/b.sql && echo "backup $(date -u +%FT%TZ): $(wc -c < /tmp/b.sql) bytes, '
                                   '$(grep -c ^ /tmp/b.sql) lines"']}]}}}}}})

    # ---- status, upgrades -------------------------------------------------------------------------
    st = sts.get("status", {})
    ready = st.get("readyReplicas", 0) == 1 and st.get("updatedReplicas", 0) == 1 and st.get("currentRevision") == st.get("updateRevision")
    running = status.get("version")
    phase, new = status.get("phase"), {"observedGeneration": m.get("generation"), "readyReplicas": st.get("readyReplicas", 0)}
    if running and running != version:
        new["phase"] = "Upgrading"
        if phase != "Upgrading":
            event(db, "Upgrading", f"{running} -> {version}: rolling StatefulSet {name}")
        if ready:
            up = f"{name}-upgrade-{version.replace('.', '-')}"
            job(name, ns, up, "until pg_isready -q; do sleep 1; done; psql -tAc 'SELECT version()'; "
                "psql -v ON_ERROR_STOP=1 -c 'ALTER TABLE items ADD COLUMN IF NOT EXISTS migrated_to text'; "
                f"psql -c \"UPDATE items SET migrated_to='{version}'\"", image, owner)
            if job_done(ns, up):
                new.update(phase="Ready", version=version)
                event(db, "Upgraded", f"now running {version} (Job {up} verified it)")
    else:
        new["phase"] = "Ready" if ready and job_done(ns, f"{name}-init") else "Provisioning"
        if ready and not running:
            new["version"] = version
        if new["phase"] == "Ready" and phase != "Ready":
            event(db, "Ready", f"postgres {version} is ready")
    if any(status.get(k) != v for k, v in new.items()):
        api("PATCH", base + "/status", {"status": new}, "application/merge-patch+json")


def main():
    log(f"sampledb-operator started, resync every {RESYNC}s")
    while True:
        code, lst = api("GET", f"/apis/{G}/{V}/{PLURAL}")
        if code != 200:
            log("list failed", code, lst.get("message"))
        for db in lst.get("items", []):
            try:
                reconcile(db)
            except Exception as e:  # keep going: one broken object must not stop the loop
                log(f"  [{db['metadata']['name']}] reconcile error: {e!r}")
        time.sleep(RESYNC)


if __name__ == "__main__":
    main()
