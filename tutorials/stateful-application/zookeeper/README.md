# Running ZooKeeper, A Distributed System Coordinator – Hands-on Lab

Based on: https://kubernetes.io/docs/tutorials/stateful-application/zookeeper/

> The page needs **at least four nodes** (required Pod anti-affinity + drains). This host can't run a multi-node minikube (inotify
> instance limit 128; raising it needs sudo). So:
> - [zookeeper.yaml](zookeeper.yaml) (docs, **verbatim**) is applied once on the single node, to show what the anti-affinity does there.
> - [zookeeper-single-node.yaml](zookeeper-single-node.yaml) (NOT from the docs) is the same manifest **without** the `podAntiAffinity`
>   block. All other sections run on it.
> - "Surviving maintenance" can't drain the only node (that would evict the cluster's own system Pods). The PDB part is shown with the
>   **Eviction API**, which is exactly what `kubectl drain` calls per Pod
>   ([evict.sh](../../../tasks/run-application/configure-pdb/evict.sh) from the configure-pdb task lab).
>
> **Found:**
> - **The readiness probe says Ready when the server isn't serving.** `zookeeper-ready` sends `ruok`, and ZooKeeper 3.4 answers `imok` as
>   soon as the process runs, even without quorum. With the docs manifest on one node, zk-0 was `1/1 Running` alone (zk-1 `Pending`), while
>   `stat` said `This ZooKeeper instance is not currently serving requests` and `zkCli.sh create` failed. After recreating the StatefulSet,
>   zk-2 was Ready but `zkCli.sh get /hello` failed with `ConnectionLoss` for a few seconds. That contradicts the page's "for a ZooKeeper
>   server, liveness implies readiness".
> - **`--purge_interval=12` has no effect.** The image's `start-zookeeper` writes `autopurge.purgeInteval=12` (typo) into `zoo.cfg`. The
>   server logs `autopurge.purgeInterval set to 0` and `Purge task is not scheduled`, so old snapshots and logs are never purged.
> - **`kubectl exec zk-2 zkCli.sh get /hello`** (and `kubectl exec zk-0 cat …`, `kubectl exec zk-0 zkCli.sh get /hello`) fail with current
>   kubectl: `error: exec [POD] [COMMAND] is not supported anymore. Use exec [POD] -- [COMMAND] instead`. Add `--`.
> - The "Testing for readiness" snippet shows `initialDelaySeconds: 15`; the manifest has `10`.
> - The page's cleanup has no delete commands (only "uncordon" and "delete the storage"). See [cleanup.sh](cleanup.sh).

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| `zk-hs` (headless, 2888/3888) / `zk-cs` (2181) | server-to-server traffic and leader election / client traffic |
| Ordinal → `myid` | zk-0 → 1, zk-1 → 2, zk-2 → 3; `zoo.cfg` lists `server.N=zk-(N-1).zk-hs.default.svc.cluster.local:2888:3888` |
| Quorum | 2 of 3 servers must be up to write |
| PVC per server | data (and `myid`) survive Pod and StatefulSet deletion |
| `podAntiAffinity` required, per hostname | never two servers on one node → one node failure costs at most one server |
| `zk-pdb` `maxUnavailable: 1` | an eviction (drain) that would take a second server down is refused |
| Liveness = `zookeeper-ready` | a broken check → container restarted |

## Lab 1 – The docs manifest on a single node
```bash
kubectl apply -f zookeeper.yaml
kubectl get pods -l app=zk
#   zk-0   1/1   Running   0   55s
#   zk-1   0/1   Pending   0   21s
kubectl describe pod zk-1 | grep FailedScheduling
#   0/1 nodes are available: 1 node(s) didn't match pod anti-affinity rules. preemption: … No preemption victims found
kubectl exec zk-0 -- sh -c 'echo ruok | nc localhost 2181'     # imok      <- why zk-0 is "Ready"
kubectl exec zk-0 -- sh -c 'echo stat | nc localhost 2181'     # This ZooKeeper instance is not currently serving requests
kubectl delete -f zookeeper.yaml; kubectl delete pvc -l app=zk
```

## Lab 2 – Create the ensemble (single-node variant)
```bash
kubectl get pods -w -l app=zk           # terminal 2
kubectl apply -f zookeeper-single-node.yaml
#   watch: zk-0 Pending → Running 0/1 → 1/1 (14 s), then zk-1 (13 s), then zk-2 (12 s)   (OrderedReady)
for i in 0 1 2; do kubectl exec zk-$i -- hostname; done            # zk-0 zk-1 zk-2
for i in 0 1 2; do echo "myid zk-$i";kubectl exec zk-$i -- cat /var/lib/zookeeper/data/myid; done   # 1 2 3
for i in 0 1 2; do kubectl exec zk-$i -- hostname -f; done         # zk-N.zk-hs.default.svc.cluster.local
kubectl exec zk-0 -- cat /opt/zookeeper/conf/zoo.cfg
#   … autopurge.snapRetainCount=3
#   autopurge.purgeInteval=12            <- typo, see "Found"
#   server.1=zk-0.zk-hs.default.svc.cluster.local:2888:3888
#   server.2=zk-1.zk-hs.default.svc.cluster.local:2888:3888
#   server.3=zk-2.zk-hs.default.svc.cluster.local:2888:3888
kubectl logs zk-0 | grep purgeInterval  # autopurge.purgeInterval set to 0 … Purge task is not scheduled.
# NOT from the docs – who leads:
for i in 0 1 2; do kubectl exec zk-$i -- sh -c 'echo stat | nc localhost 2181' | grep Mode; done
#   Mode: follower / Mode: leader / Mode: follower
```

## Lab 3 – Sanity test and durable storage
```bash
kubectl exec zk-0 -- zkCli.sh create /hello world       # Created /hello
kubectl exec zk-1 -- zkCli.sh get /hello                # world  cZxid = 0x100000002 …   (written on zk-0, read on zk-1)
kubectl delete statefulset zk
kubectl apply -f zookeeper-single-node.yaml
kubectl exec zk-2 zkCli.sh get /hello                   # error: exec [POD] [COMMAND] is not supported anymore …
kubectl exec zk-2 -- zkCli.sh get /hello                # right after "rollout complete": ConnectionLoss (not serving yet);
                                                        # a few seconds later: world   <- data survived
kubectl get pvc -l app=zk                               # datadir-zk-0/1/2   Bound   10Gi   standard
```

## Lab 4 – Configuration, logging, non-root user
```bash
kubectl get sts zk -o yaml              # the start-zookeeper flags in command: are the single source of config
kubectl exec zk-0 -- cat /usr/etc/zookeeper/log4j.properties
#   zookeeper.root.logger=CONSOLE … log4j.appender.CONSOLE=org.apache.log4j.ConsoleAppender   (logs go to stdout)
kubectl logs zk-0 --tail 20
kubectl exec zk-0 -- ps -elf            # UID zookeep+ for PID 1 (sh) and PID 7 (java)   <- runAsUser: 1000
kubectl exec -ti zk-0 -- ls -ld /var/lib/zookeeper/data  # drwxr-xr-x 4 zookeeper zookeeper …   <- fsGroup: 1000
```

## Lab 5 – Update and roll back
```bash
kubectl patch sts zk --type='json' -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/cpu", "value":"0.3"}]'
kubectl rollout status sts/zk           # statefulset rolling update complete 3 pods at revision zk-7758b8787c...
kubectl rollout history sts/zk          # REVISION 1, 2
kubectl rollout undo sts/zk             # statefulset.apps/zk rolled back   → zk-0 cpu request 500m again; history now 2, 3
```

## Lab 6 – Process failure and liveness
```bash
kubectl exec zk-0 -- pkill java
#   watch: 20:13:01 zk-0 0/1 Error → 20:13:03 Running, RESTARTS 1 → 20:13:13 1/1   (restartPolicy Always restarts the container)
kubectl exec zk-0 -- rm /opt/zookeeper/bin/zookeeper-ready
#   watch: 20:13:43 zk-0 0/1 (readiness failing: "sh: 1: zookeeper-ready: not found")
#          20:14:13 RESTARTS 2 (liveness failed 3×) → 20:14:25 1/1   (the script is back: fresh container filesystem)
```

## Lab 7 – Node failure and maintenance (single node: Eviction API instead of drain)
```bash
for i in 0 1 2; do kubectl get pod zk-$i --template {{.spec.nodeName}}; echo ""; done    # minikube ×3 (no anti-affinity here)
kubectl get pdb zk-pdb                  # zk-pdb   N/A   1   1     (MAX UNAVAILABLE 1, ALLOWED DISRUPTIONS 1)
EV=../../../tasks/run-application/configure-pdb/evict.sh
$EV zk-0                                # {"kind":"Status",…,"status":"Success","code":201}
$EV zk-1                                #   refused (TooManyRequests): Cannot evict pod as it would violate the pod's disruption budget.
kubectl get pdb zk-pdb                  # ALLOWED DISRUPTIONS 0   (zk-0 is Terminating / being recreated)
#   43 s later zk-0 is back and Ready → ALLOWED DISRUPTIONS 1
$EV zk-1                                # Success
kubectl exec zk-0 -- zkCli.sh get /hello    # world   <- the ensemble kept quorum the whole time
```
On a 4-node cluster, `kubectl drain` does the same per Pod. The second drain then **waits** (retrying the refused eviction) until the
evicted server is Ready on another node. Once only three schedulable nodes remain and anti-affinity applies, the third drain hangs:
zk-0 stays `Pending` until a node is uncordoned.

## Cleanup
```bash
./cleanup.sh     # delete Services, PDB, StatefulSet; then the PVCs (PVs are deleted with them: reclaim policy Delete)
```
