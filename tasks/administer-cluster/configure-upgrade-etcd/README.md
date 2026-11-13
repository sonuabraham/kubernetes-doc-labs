# Operating etcd clusters for Kubernetes – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/

> Two environments:
> 1. **The cluster's own etcd** on a throwaway profile **`etcd-lab`**: a single member, a kubeadm static Pod (`registry.k8s.io/etcd:3.7.0-0`) with TLS. [etcdctl.sh](etcdctl.sh) runs `etcdctl`/`etcdutl` **inside** the etcd Pod with the TLS flags from the docs' "Securing communication" example. The image is distroless, so only its data-dir mount (`/var/lib/minikube/etcd`) is shared with the node.
> 2. **The docs' three-member example cluster**, for real: [etcd-docker-cluster.sh](etcd-docker-cluster.sh) runs `member1..3` at `http://10.0.0.1..3` in Docker for the "replace a failed member" procedure.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **etcdctl vs etcdutl** | `etcdctl` talks to a **running** member over the network (`member`, `endpoint`, `snapshot save`, `defrag`, ...). `etcdutl` works on **files** offline (`snapshot status`, `snapshot restore`). |
| **Members** | Odd sizes (3, 5) tolerate (n-1)/2 failures. 5 is recommended for production. The API server lists every member (or a load balancer) in `--etcd-servers`. |
| **Security** | TLS for clients and peers (`--cert-file`, `--key-file`, `--trusted-ca-file`, `--client-cert-auth`). Only the API servers should hold client certificates. |
| **Replace a member** | Remove the failed one first (`member remove <ID>`), then `member add` the new one, then start it with `--initial-cluster-state=existing`. Use unique member names. |
| **Backup** | `etcdctl snapshot save` (consistent, from a live member) or volume snapshots. |
| **Restore** | Stop **all** API servers, `etcdutl snapshot restore` into a **new** data dir (with this member's name and peer URL), point etcd at it, start etcd, then the API servers. Everything written after the snapshot is lost. |
| **Defragmentation** | Compaction marks old revisions free *inside* the DB file. `defrag` gives the space back to the filesystem. Defrag blocks the member, so do one member at a time. |

---

## Step 0
```bash
cd tasks/administer-cluster/configure-upgrade-etcd
minikube start -p etcd-lab --memory 2200 --cpus 2 --kubernetes-version v1.37.0 && kubectl config use-context minikube
K="kubectl --context etcd-lab"
minikube ssh -p etcd-lab -- 'sudo grep -E "image:|data-dir|listen-client|cert-file|trusted-ca" /etc/kubernetes/manifests/etcd.yaml'
#   --cert-file=/var/lib/minikube/certs/etcd/server.crt   --data-dir=/var/lib/minikube/etcd
#   --listen-client-urls=https://127.0.0.1:2379,https://192.168.184.2:2379   image: registry.k8s.io/etcd:3.7.0-0
```

## Lab 1 – Talk to etcd securely
```bash
./etcdctl.sh endpoint health
#   https://127.0.0.1:2379 is healthy: successfully committed proposal: took = 11.37ms
./etcdctl.sh --write-out=table member list
#   | d667201245e8e03a | started | etcd-lab | https://192.168.184.2:2380 | https://192.168.184.2:2379 | false |
./etcdctl.sh --write-out=table endpoint status
#   | https://127.0.0.1:2379 | d667201245e8e03a | 3.7.0 | ... | DB SIZE 836 kB | ... | IS LEADER true | ...
# without a client certificate (only --cacert): command terminated with exit code 1 (client-cert-auth is on)
```

## Lab 2 – Backup: built-in snapshot
```bash
$K create ns before-snapshot && $K -n before-snapshot create configmap marker --from-literal=taken=before
./etcdctl.sh snapshot save /var/lib/minikube/etcd/snapshot.db
#   Snapshot saved at /var/lib/minikube/etcd/snapshot.db
TOOL=etcdutl ./etcdctl.sh --write-out=table snapshot status /var/lib/minikube/etcd/snapshot.db
#   |  HASH   | REVISION | TOTAL KEYS | TOTAL SIZE | VERSION |
#   | b587f01 |      449 |        344 |     963 kB |   3.7.0 |
$K create ns after-snapshot; $K delete ns before-snapshot          # change state after the backup
```

## Lab 3 – Restore
```bash
# 1. stop all API servers (here: move the static Pod manifest away)
minikube ssh -p etcd-lab -- 'sudo bash -c "mkdir -p /etc/kubernetes/off; mv /etc/kubernetes/manifests/kube-apiserver.yaml /etc/kubernetes/off/"'
# 2. restore into a NEW data dir; name + peer URL must match this member's etcd flags
TOOL=etcdutl ./etcdctl.sh --data-dir /var/lib/minikube/etcd/restored snapshot restore /var/lib/minikube/etcd/snapshot.db \
  --name etcd-lab --initial-cluster etcd-lab=https://192.168.184.2:2380 --initial-advertise-peer-urls https://192.168.184.2:2380
#   ... snapshot/v3_snapshot.go:334  restored snapshot {"path": "/var/lib/minikube/etcd/snapshot.db", ...}
# 3. stop etcd, swap the data dir, start etcd, then the API server
minikube ssh -p etcd-lab -- 'sudo bash -c "mv /etc/kubernetes/manifests/etcd.yaml /etc/kubernetes/off/; sleep 15
  mv /var/lib/minikube/etcd /var/lib/minikube/etcd-before-restore; mv /var/lib/minikube/etcd-before-restore/restored /var/lib/minikube/etcd
  mv /etc/kubernetes/off/etcd.yaml /etc/kubernetes/manifests/; sleep 10; mv /etc/kubernetes/off/kube-apiserver.yaml /etc/kubernetes/manifests/"'
until $K get --raw /readyz >/dev/null 2>&1; do sleep 3; done
$K get ns | grep snapshot
#   before-snapshot   Active      <- back;  after-snapshot is gone (written after the backup)
$K -n before-snapshot get cm marker -o jsonpath='{.data}'      # {"taken":"before"}
```

## Lab 4 – Defragmentation
```bash
st(){ ./etcdctl.sh endpoint status -w json | python3 -c 'import json,sys;s=json.load(sys.stdin)[0]["Status"];print("dbSize=%.1fMB inUse=%.1fMB"%(s["dbSize"]/1e6,s["dbSizeInUse"]/1e6))'; }
st                                                                         # dbSize=1.1MB inUse=1.1MB
$K create ns bloat; head -c 700000 /dev/urandom | base64 -w0 > /tmp/blob
for i in $(seq 20); do $K -n bloat create configmap b$i --from-file=data=/tmp/blob; done
st                                                                         # dbSize=24.5MB inUse=23.5MB
$K delete ns bloat
./etcdctl.sh compact <current revision>; st                                # dbSize=24.5MB inUse=20.0MB   <- file doesn't shrink
./etcdctl.sh defrag
#   Finished defragmenting etcd member[https://127.0.0.1:2379]. took 15.06ms
st                                                                         # dbSize=0.5MB inUse=0.5MB
```
(kube-apiserver compacts etcd itself every 5 minutes. Defragmentation is up to you, e.g. a CronJob or the etcd-defrag tool.)

## Lab 5 – Replacing a failed member (the docs' 3-member example)
```bash
./etcd-docker-cluster.sh up                     # member1 10.0.0.1, member2 10.0.0.2, member3 10.0.0.3
E="docker exec member2 etcdctl"
$E --endpoints=http://10.0.0.2,http://10.0.0.3 member list            # the docs' command, verbatim
#   ... dial tcp: address 10.0.0.3: missing port in address   Error: context deadline exceeded
$E --endpoints=http://10.0.0.2:2379,http://10.0.0.3:2379 member list
#   28a24ac78ca45892, started, member2, http://10.0.0.2:2380, http://10.0.0.2:2379, false
#   b21a2f0dc67e5c90, started, member3, http://10.0.0.3:2380, http://10.0.0.3:2379, false
#   df431037320b627d, started, member1, http://10.0.0.1:2380, http://10.0.0.1:2379, false
$E --endpoints=http://10.0.0.1:2379,http://10.0.0.2:2379,http://10.0.0.3:2379 put /k8s/demo hello
./etcd-docker-cluster.sh fail member1          # "the node dies"
$E --endpoints=http://10.0.0.1:2379,http://10.0.0.2:2379,http://10.0.0.3:2379 endpoint health
#   http://10.0.0.1:2379 is unhealthy: failed to commit proposal: context deadline exceeded
#   http://10.0.0.2:2379 is healthy ...   http://10.0.0.3:2379 is healthy ...      <- quorum (2/3) still OK
$E member remove df431037320b627d
#   Member df431037320b627d removed from cluster eabc17cdad249ec0
$E member add member4 --peer-urls=http://10.0.0.4:2380
#   Member e86cd5d8769a8b39 added to cluster eabc17cdad249ec0
#   ETCD_NAME="member4"
#   ETCD_INITIAL_CLUSTER="member2=http://10.0.0.2:2380,member3=http://10.0.0.3:2380,member4=http://10.0.0.4:2380"
#   ETCD_INITIAL_ADVERTISE_PEER_URLS="http://10.0.0.4:2380"
#   ETCD_INITIAL_CLUSTER_STATE="existing"            <- etcdctl prints exactly the env the docs tell you to export
./etcd-docker-cluster.sh member4                # etcd started with those variables
$E -w table --endpoints=http://10.0.0.2:2379,http://10.0.0.3:2379,http://10.0.0.4:2379 endpoint status    # 3 healthy members
docker exec member4 etcdctl get /k8s/demo       # /k8s/demo  hello   <- data replicated to the new member
```
In a Kubernetes cluster you'd also update the API servers' `--etcd-servers` (remove member1, add member4) and restart them, as in the docs' second and last steps.

---

## Useful commands
```bash
etcdctl --endpoints=https://127.0.0.1:2379 --cacert=ca.crt --cert=server.crt --key=server.key endpoint health|status -w table
etcdctl member list -w table ; etcdctl member remove <id> ; etcdctl member add <name> --peer-urls=http://<ip>:2380
etcdctl snapshot save snap.db ; etcdutl snapshot status snap.db -w table ; etcdutl --data-dir <new> snapshot restore snap.db
etcdctl defrag
```

## Cleanup
```bash
./etcd-docker-cluster.sh down
minikube delete -p etcd-lab
```
