# Coordinated Leader Election – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/cluster-administration/coordinated-leader-election/

> The page has no YAML. The lab runs on a throwaway profile **`cle-lab`** ([start-cle-lab.sh](start-cle-lab.sh)) with the gate and API group enabled. [candidate.sh](candidate.sh) is a toy leader-election client that speaks the LeaseCandidate protocol, so you can watch the API server pick a leader.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Classic leader election** | HA components (kube-controller-manager, kube-scheduler, CSI sidecars…) share one **Lease**. Whoever manages to write its identity into an expired/absent Lease wins (optimistic concurrency on `resourceVersion`). The winner renews; the others watch. Whoever is fastest wins. |
| **The problem** | During an upgrade, a **new** binary can win leadership while older API servers or peers are still around, which breaks version-skew rules. |
| **Coordinated leader election** (beta, off by default) | Candidates don't grab the Lease. They **register** a `LeaseCandidate` (`coordination.k8s.io/v1beta1`) carrying `binaryVersion`, `emulationVersion` and `strategy`. A controller **inside kube-apiserver** picks the leader and writes the Lease. |
| **Enable** | API server: `--feature-gates=CoordinatedLeaderElection=true` **and** `--runtime-config=coordination.k8s.io/v1beta1=true`. kube-controller-manager and kube-scheduler then use it automatically (with `--leader-elect=true`). |
| **OldestEmulationVersion** | The only built-in strategy: lowest **emulation version**, then lowest **binary version**, then oldest **creationTimestamp**. |
| **Lease fields** | `holderIdentity`, `acquireTime`, `renewTime`, `leaseDurationSeconds`, `leaseTransitions`. New with CLE: `strategy` and `preferredHolder`. |
| **Ping / ack** | Before an election the controller sets `spec.pingTime` on candidates. Live candidates answer by bumping `renewTime`. Only candidates that acked within **5s** are eligible. |
| **preferredHolder** | When a better candidate appears, the controller **doesn't evict** the leader. It sets `preferredHolder`, and the current leader is expected to step down. The Lease then expires (5s) and goes to the better candidate. |

---

## Step 1 – Start the profile
```bash
cd concepts/cluster-administration/coordinated-leader-election
./start-cle-lab.sh
C="--context cle-lab"
kubectl $C get --raw /metrics | grep 'name="CoordinatedLeaderElection"'
#   kubernetes_feature_enabled{name="CoordinatedLeaderElection",stage="BETA"} 1
```
minikube runs the controller-manager and scheduler with `--leader-elect=false`, so the script also turns leader election back on for both.

## Lab 1 – The real components register as candidates
```bash
kubectl $C get leasecandidates -n kube-system
#   NAME                                           LEASENAME                 BINARYVERSION   EMULATIONVERSION
#   cle-lab_584e8022-...                           kube-scheduler            1.37.0          1.37.0
#   cle-lab_c784d89d-...                           kube-controller-manager   1.37.0          1.37.0
#   (Warning: coordination.k8s.io/v1beta1 LeaseCandidate is deprecated in v1.36+, unavailable in v1.39+)
kubectl $C get lease kube-scheduler -n kube-system -o yaml | sed -n '/^spec/,$p'
#   holderIdentity: cle-lab_584e8022-...   leaseDurationSeconds: 15   leaseTransitions: 0
#   strategy: OldestEmulationVersion       acquireTime: null            <- written by the API server, not grabbed
kubectl $C logs -n kube-system kube-apiserver-cle-lab | grep leaderelection_controller
#   Created lease kube-system/kube-scheduler for "cle-lab_584e8022-..."
```
Compare with the main cluster, which has no LeaseCandidate API and no scheduler or controller-manager Lease (leader election is off). Classic election is still visible in add-on leases:
```bash
kubectl --context minikube get lease -n kube-system -o custom-columns=NAME:.metadata.name,HOLDER:.spec.holderIdentity,TRANS:.spec.leaseTransitions
#   snapshot-controller-leader   snapshot-controller-7d8dd4dd5d-q6q5p   0      <- holder = pod name
kubectl --context minikube get leasecandidates -A     # error: the server doesn't have a resource type "leasecandidates"
```

## Lab 2 – An election you can watch
Two toy candidates compete for Lease `cle-demo/demo-leader`: `demo-new` (emulation **1.37.0**) and `demo-old` (emulation **1.36.0**).
```bash
kubectl $C create ns cle-demo
CTX=cle-lab ./candidate.sh demo-new 1.37.0          # terminal 1
CTX=cle-lab ./candidate.sh demo-old 1.36.0          # terminal 2, ~10s later
```
Measured:
```
19:15:30 [demo-new] registered as candidate (emulation 1.37.0, binary 1.37.0)
19:15:30 [demo-new] I AM THE LEADER                                         <- the only candidate
19:15:41 [demo-old] registered as candidate (emulation 1.36.0, binary 1.37.0)
19:15:41 [demo-new] ack ping 2026-11-12T08:15:41.252317Z                    <- the controller checks who is alive
19:15:42 [demo-new] preferredHolder=demo-old -> stepping down (no more renewals)
19:15:45 [demo-old] I AM THE LEADER                                         <- the Lease expired and went to the older version
19:15:46 [demo-new] follower (leader: demo-old)
```
API server log:
```
Lease cle-demo/demo-leader holder changed from "demo-new" to "demo-old"     <- actually sets preferredHolder
Lease cle-demo/demo-leader expired, resetting it and setting holder to "demo-old"
```
A **lower** emulation version beats an earlier arrival. During an upgrade the not-yet-upgraded instance stays leader until every candidate is new.

## Lab 3 – Leader crash and failover
```bash
# Ctrl-C terminal 2 (demo-old, the leader) at 19:16:07
#   19:16:15 [demo-new] ack ping ...        <- Lease expired (5s) -> election; demo-old is pinged too but never answers
#   19:16:20 [demo-new] I AM THE LEADER     <- after the 5s ack window, only acked candidates are eligible
```
That's about 13s from the crash to the new leader (5s lease plus a 5s ping window, plus polling). `demo-old`'s LeaseCandidate **stays** with a stale `renewTime`. Because it still ranks best, the controller keeps re-pinging (`demo-new` acked again at :23 and :30) until the candidate is deleted. The apiserver's leasecandidate GC removes candidates that haven't renewed for **30 min**.
```bash
kubectl $C get leasecandidate -n cle-demo -o custom-columns=NAME:.metadata.name,EMU:.spec.emulationVersion,RENEW:.spec.renewTime,PING:.spec.pingTime
#   demo-new   1.37.0   08:16:30.63   08:16:30.16    <- acked
#   demo-old   1.36.0   08:15:40.99   08:16:15.13    <- ping newer than renew: dead
```
Restart terminal 2 (`./candidate.sh demo-old 1.36.0`). Within ~10s it takes leadership back through `preferredHolder` again.

## What the page says vs. what CLE does
The page describes the **classic** race ("candidate instances attempt to update the Lease with their identity… optimistic concurrency"). With the gate on, the toy candidates **never write `holderIdentity`**. Only the API server's `leaderelection_controller` does. The candidates just register, ack pings, renew while leading, and honour `preferredHolder`.

---

## Useful commands
```bash
kubectl get leasecandidates -A
kubectl get lease <name> -n kube-system -o yaml        # holderIdentity, preferredHolder, strategy, renewTime
kubectl logs -n kube-system kube-apiserver-<node> | grep leaderelection_controller
```

## Notes from testing
- This host's `date` ignores `%6N` and prints 9 decimals, which `MicroTime` rejects ("cannot parse "191Z" as "Z07:00""). candidate.sh trims to 6 decimals.
- An earlier version of candidate.sh used `read a b` on `"{.spec.pingTime} {.spec.renewTime}"`. With no `pingTime`, the renewTime shifted into `ping`, so the toy "acked" every second. It now uses a `|` separator.

## Cleanup
```bash
./cleanup.sh        # stops toy candidates, deletes cle-demo, stops cle-lab, switches back to minikube
```
