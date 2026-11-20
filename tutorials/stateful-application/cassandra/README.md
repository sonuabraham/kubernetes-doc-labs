# Example: Deploying Cassandra with a StatefulSet – Hands-on Lab

Based on: https://kubernetes.io/docs/tutorials/stateful-application/cassandra/

> Runs on the default **minikube** (8 CPUs / plenty of memory here, so the page's `minikube start --memory 5120 --cpus=4` wasn't needed),
> namespace `default`. [cassandra-service.yaml](cassandra-service.yaml) and [cassandra-statefulset.yaml](cassandra-statefulset.yaml) are the
> docs examples **verbatim**. [cassandra-statefulset-fixed.yaml](cassandra-statefulset-fixed.yaml) is NOT from the docs: one line changed, see below.
>
> **Found:**
> - **With the docs manifest the ring never gets past `cassandra-0`.** The Pod runs and Cassandra is up (`nodetool status` → `UN`), but the
>   readiness probe (`/ready-probe.sh`, which runs `nodetool status`) fails every time:
>   `Readiness probe failed: command timed out: "/bin/bash -c /ready-probe.sh" timed out after 5s`. After 10 min it was still `0/1`, so
>   with `OrderedReady` cassandra-1 is never created. `nodetool` starts a whole JVM and took **14–16 s** here: JDK 8 sees 8 CPUs, but the
>   container is limited to `500m` (`cpu.max 50000 100000`).
>   [cassandra-statefulset-fixed.yaml](cassandra-statefulset-fixed.yaml) only changes `timeoutSeconds: 5` → `30`. With it, all 3 Pods
>   were Ready after **213 s**. (On a cluster with fewer cores per node the JVM may be fast enough, which is why the page works for some.)
> - **The cleanup sleeps 500 s for nothing.** It sleeps `terminationGracePeriodSeconds` (500), but the Pods were gone after **17 s**
>   (the `preStop` `nodetool drain` finished quickly). [cleanup.sh](cleanup.sh) waits for the Pods instead.
> - **The cleanup leaves the StorageClass `fast` behind.** It comes from `cassandra-statefulset.yaml` but has no `app=cassandra` label.
>   cleanup.sh deletes it.
> - `kubectl get statefulset cassandra` prints `READY` (e.g. `0/3`), not the page's old `DESIRED / CURRENT` columns.
> - The `fast` StorageClass uses `k8s.io/minikube-hostpath`, so it works on minikube unchanged (`parameters.type: pd-ssd` is ignored).
>   On another cluster, change the provisioner.
> - `gcr.io/google-samples/cassandra:v13` still pulls (106 MB).

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| Headless Service `cassandra` | DNS for the members; port 9042 (CQL) |
| `CASSANDRA_SEEDS=cassandra-0.cassandra.default.svc.cluster.local` | every new member contacts the stable name of Pod 0 to join the ring |
| `OrderedReady` + readiness probe | the next Pod is only created when the previous one is Ready. A probe that never passes stalls the ring |
| `preStop: nodetool drain` + `terminationGracePeriodSeconds: 500` | flush data before the Pod stops |
| `volumeClaimTemplates` (`storageClassName: fast`) | one PVC per member; kept after scale-down / delete |

## Lab
```bash
kubectl apply -f cassandra-service.yaml
kubectl get svc cassandra                     # cassandra   ClusterIP   None   <none>   9042/TCP

kubectl apply -f cassandra-statefulset.yaml   # statefulset.apps/cassandra created, storageclass.storage.k8s.io/fast created
kubectl get pods -l="app=cassandra"           # after 10 min: cassandra-0   0/1   Running   <- stuck, see "Found"
kubectl describe pod cassandra-0 | grep Unhealthy
#   Warning  Unhealthy  … (x33 over 9m14s)  kubelet  Readiness probe failed: command timed out: "/bin/bash -c /ready-probe.sh" timed out after 5s
time kubectl exec cassandra-0 -- nodetool status >/dev/null     # ~15 s

# start over with the fixed probe timeout
kubectl delete sts cassandra; kubectl delete pvc -l app=cassandra
kubectl apply -f cassandra-statefulset-fixed.yaml
kubectl get statefulset cassandra             # cassandra   0/3 …  (Pods come one after the other)
kubectl get pods -l="app=cassandra"
#   cassandra-0   1/1   Running   3m37s
#   cassandra-1   1/1   Running   2m51s
#   cassandra-2   1/1   Running   91s           (all Ready after 213 s)
kubectl exec -it cassandra-0 -- nodetool status
#   Datacenter: DC1-K8Demo
#   --  Address      Load        Tokens  Owns (effective)  Host ID                               Rack
#   UN  10.244.0.71  104.56 KiB  32      75.5%             bc73e663-2939-4e6e-adc3-c302087f8413  Rack1-K8Demo
#   UN  10.244.0.72  103.83 KiB  32      64.6%             cadfa8c3-bd4c-4d40-81ce-c9130a9fdaa6  Rack1-K8Demo
#   UN  10.244.0.73  65.86 KiB   32      59.8%             9c6a9fbe-a68b-4bad-9157-3a0383b65354  Rack1-K8Demo

kubectl edit statefulset cassandra            # replicas: 3 → 4
#   non-interactive (NOT from the docs): kubectl patch statefulset cassandra -p '{"spec":{"replicas":4}}'
kubectl get statefulset cassandra             # cassandra   4/4
kubectl exec cassandra-0 -- nodetool status   # 4 × UN; ownership rebalanced to ~48–53 % each
```

## Cleanup
Docs:
```bash
grace=$(kubectl get pod cassandra-0 -o=jsonpath='{.spec.terminationGracePeriodSeconds}') \
  && kubectl delete statefulset -l app=cassandra \
  && echo "Sleeping ${grace} seconds" 1>&2 \
  && sleep $grace \
  && kubectl delete persistentvolumeclaim -l app=cassandra
kubectl delete service -l app=cassandra
#   Sleeping 500 seconds      (the Pods were gone after 17 s)
kubectl delete storageclass fast            # NOT in the docs, but needed
```
Faster, same result: `./cleanup.sh`.
