# Scheduling, Preemption and Eviction – Hands-on Labs

Based on: https://kubernetes.io/docs/concepts/scheduling-eviction/

## Multi-node without more minikube nodes
Scheduling needs several nodes, but this host can't start more minikube node containers: `fs.inotify.max_user_instances=128` is exhausted (a 2nd node's systemd fails with *"Failed to create control group inotify object: Too many open files"*). Raising it needs root (`sudo sysctl fs.inotify.max_user_instances=1024`).

Instead the labs use **fake nodes**, [fake-nodes.sh](fake-nodes.sh):
```bash
./fake-nodes.sh up 3       # Node objects fake-1..3 (labels type=fake, zone-a/b/c), 4 CPU / 8Gi, kept Ready by a heartbeat loop
./fake-nodes.sh down       # stop the heartbeat, delete the nodes
```
- The scheduler can't tell the difference, so filters, scores, spreading, taints and preemption all work on them.
- Pods bound to a fake node never start (no kubelet). Judge results by `spec.nodeName` and events, not `Running`.
- DaemonSets (kube-proxy, kindnet, CSI plugin) also create Pending Pods on them. That's harmless and goes away with `down`.
- Pods on fake nodes must be **force-deleted**, otherwise namespace deletion hangs: every lab cleanup uses `./delete-ns.sh <ns>`.
- If the heartbeat stops, the node lifecycle controller marks them NotReady and taints them, which itself is useful for `../node-pressure-eviction`/taint labs.

## The labs
| Page | Needs | Shows |
|---|---|---|
| [kube-scheduler](kube-scheduler/) | fake nodes | filter and score phases in a -v=10 scheduler's log |
| [running-multiple-schedulers](running-multiple-schedulers/) | fake nodes | HA leader election, profiles in one process, independent instances double-booking a node |
| [assign-pod-node](assign-pod-node/) | fake nodes | nodeSelector, node/pod (anti-)affinity, match/mismatchLabelKeys, nodeName, topology labels, profile-added affinity |
| [pod-overhead](pod-overhead/) | – | RuntimeClass overhead in scheduling and in the pod cgroup |
| [pod-scheduling-readiness](pod-scheduling-readiness/) | – | schedulingGates, gated queue metric, tightening directives |
| [topology-spread-constraints](topology-spread-constraints/) | 5 fake nodes | the docs' node1–node5 scenarios, conflicts, minDomains, default constraints |
| [taint-and-toleration](taint-and-toleration/) | fake nodes | tolerate ≠ attract, NoExecute + tolerationSeconds, unreachable taints |
| [scheduling-framework](scheduling-framework/) | fake nodes | the real plugin list; turning Filter, Score and PostFilter plugins on and off |
| [scheduler-perf-tuning](scheduler-perf-tuning/) | 250 fake nodes | percentageOfNodesToScore: evaluated vs feasible nodes |
| [resource-bin-packing](resource-bin-packing/) | fake nodes | MostAllocated / RequestedToCapacityRatio vs the default |
| [pod-priority-preemption](pod-priority-preemption/) | fake nodes | preemption, non-preempting classes, queue order, PDB-aware victims |
| [node-pressure-eviction](node-pressure-eviction/) | `evict-lab` profile | real MemoryPressure: who gets evicted |
| [api-eviction](api-eviction/) | – | Eviction API, PDB 429, stuck evictions and unhealthyPodEvictionPolicy |
| [node-declared-features](node-declared-features/) | fake nodes | features declared by the node, scheduler filtering, RestartAllContainers |
| [gang-scheduling](gang-scheduling/) | `wl-lab` + fake nodes | quorum in PreEnqueue, minCount, gang of gangs |
| [podgroup-scheduling](podgroup-scheduling/) | `wl-lab` + fake nodes | Pod-by-Pod deadlock vs the PodGroup cycle |
| [workload-aware-preemption](workload-aware-preemption/) | `wl-lab` + fake nodes | cluster-wide victims, disruption modes, Pod vs PodGroup importance |
| [topology-aware-scheduling](topology-aware-scheduling/) | `wl-lab` + 6 fake nodes | zone-confined gangs, MostAllocated placement scoring |

`wl-lab` = `../workloads/workload-api/start-wl-lab.sh`. On another context, run the fake nodes with `CTX=wl-lab ./fake-nodes.sh up N` (the heartbeat is pinned to that context).
