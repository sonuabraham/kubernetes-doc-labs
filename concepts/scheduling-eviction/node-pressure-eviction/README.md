# Node-pressure Eviction – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/scheduling-eviction/node-pressure-eviction/

> The docs' two KubeletConfigurations are **verbatim**: [kubeletconfig-minimum-reclaim.yaml](kubeletconfig-minimum-reclaim.yaml) and [kubeletconfig-system-reserved.yaml](kubeletconfig-system-reserved.yaml). Real eviction needs a real kubelet under real pressure, so this runs on a separate profile **`evict-lab`** ([start-evict-lab.sh](start-evict-lab.sh)) whose `memory.available` hard threshold sits just below what the node currently has free.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Node-pressure eviction** | The **kubelet** proactively fails Pods (phase `Failed`, reason `Evicted`) to reclaim memory, disk or PIDs before the node starves. Not API-initiated: PDBs and `terminationGracePeriodSeconds` aren't honoured for hard thresholds. |
| **Signals** | `memory.available`, `nodefs.available`, `nodefs.inodesFree`, `imagefs.*`, `containerfs.*`, `pid.available`. |
| **Hard threshold** | Immediate eviction (`evictionHard`). **Soft**: only after `evictionSoftGracePeriod`, with a max Pod grace period. |
| **Defaults (Linux)** | `memory.available<100Mi`, `nodefs.available<10%`, `imagefs.available<15%`, `nodefs.inodesFree<5%`. |
| **Node conditions → taints** | `MemoryPressure` / `DiskPressure` / `PIDPressure` → `node.kubernetes.io/memory-pressure:NoSchedule` etc. `evictionPressureTransitionPeriod` stops the condition oscillating. |
| **Reclaim order** | Node-level first (container and image GC for disk), then Pods. |
| **Pod selection** | 1) usage **above requests**? 2) **priority** 3) usage relative to requests. So BestEffort and over-request Burstable Pods go first, Guaranteed last. |
| **evictionMinimumReclaim** | Reclaim a bit more than the threshold to avoid repeated evictions. |
| **OOM killer** | If the kernel OOMs before the kubelet reacts, `oom_score_adj` by QoS decides. |
| **Good practice** | Reserve memory (`systemReserved`/`kubeReserved`) above the eviction threshold (docs example: 1.5Gi reserve + 500Mi threshold). |

---

## Step 1 – A node close to its threshold
```bash
cd concepts/scheduling-eviction/node-pressure-eviction
./start-evict-lab.sh                 # THRESHOLD=29Gi by default - set it ~1Gi below your node's memory.available
#   {"evictionHard":{"memory.available":"29Gi"},"evictionPressureTransitionPeriod":"30s"}
```
`--extra-config=kubelet.eviction-hard=…` wasn't applied to the existing profile, so the script edits `/var/lib/kubelet/config.yaml` on that throwaway node and restarts the kubelet. The docker-driver node reports the **host's** memory (~30Gi available here).

## Lab – Who gets evicted
```bash
kubectl --context evict-lab apply -f 01-pods.yaml        # besteffort, burstable (64Mi request), guaranteed, hog (BestEffort, 1.5Gi)
#   MemoryPressure after 2s
kubectl --context evict-lab get node evict-lab -o jsonpath='{.spec.taints}'
#   [{"effect":"NoSchedule","key":"node.kubernetes.io/memory-pressure",...}]
kubectl --context evict-lab get pods -o custom-columns=POD:.metadata.name,QOS:.status.qosClass,PHASE:.status.phase,REASON:.status.reason
#   besteffort   BestEffort   Failed    Evicted
#   burstable    Burstable    Running
#   guaranteed   Guaranteed   Running
#   hog          BestEffort   Failed    Evicted
kubectl --context evict-lab get pod hog -o jsonpath='{.status.message}'
#   The node was low on resource: memory. Threshold quantity: 29Gi, available: 29827504Ki.
#   Container hog was using 1580520Ki, request is 0, has larger consumption of memory.
kubectl --context evict-lab get events --field-selector involvedObject.kind=Node -o custom-columns=R:.reason,M:.message
#   EvictionThresholdMet       Attempting to reclaim memory
#   NodeHasInsufficientMemory  Node evict-lab status is now: NodeHasInsufficientMemory
```
The hog was evicted first (usage over its 0 request, and the largest). The idle `besteffort` Pod was evicted **too**: host memory kept hovering just under 29Gi, so the kubelet kept reclaiming within the BestEffort tier. Burstable and Guaranteed Pods (usage below requests) survived. 45s later, with available back at 29.8Gi, `MemoryPressure` was still True: the 30s transition period has to pass without crossing the threshold.

```bash
minikube stop -p evict-lab ; kubectl config use-context minikube
```

---

## Useful commands
```bash
kubectl get --raw /api/v1/nodes/<n>/proxy/stats/summary | jq '.node.memory, .node.fs'
kubectl get --raw /api/v1/nodes/<n>/proxy/configz | jq '.kubeletconfig | {evictionHard, evictionSoft, evictionMinimumReclaim}'
kubectl get pods -A --field-selector status.phase=Failed -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,REASON:.status.reason
kubectl describe node <n> | grep -A8 Conditions
```

## Cleanup
```bash
./cleanup.sh       # stops evict-lab (minikube delete -p evict-lab to remove it)
```
