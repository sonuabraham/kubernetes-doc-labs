# Swap Memory Management – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/cluster-administration/swap-memory-management/

> The page's shell snippets need a node with swap configured. This host has 8Gi of swap, so a throwaway profile **`swap-lab`** ([start-swap-lab.sh](start-swap-lab.sh)) sets `memorySwap.swapBehavior: LimitedSwap`. [01-pods.yaml](01-pods.yaml) has one Pod per QoS class plus a high-priority Burstable Pod.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Linux + cgroup v2 only** | Swap support is stable. The node must have swap enabled and `failSwapOn: false`. |
| **swapBehavior** | `NoSwap` (default: the kubelet runs on a swap node but workloads get `memory.swap.max=0`) or `LimitedSwap`. |
| **LimitedSwap** | Only **Burstable** Pods (not high-priority ones) may swap, each container proportionally: `(containerMemoryRequest / nodeTotalMemory) × totalPodsSwapAvailable`. |
| **Observability** | `node.status.nodeInfo.swap.capacity`, `kubectl top --show-swap`, kubelet Summary API swap stats, NFD label `feature.node.kubernetes.io/memory-swap`. |
| **Risks** | Memory-backed volumes must be `noswap` (see `../../security/linux-security`). Eviction is based on memory without counting swap. I/O latency. |
| **Good practice** | No swap for system daemons (`MemorySwapMax=0` on systemd slices), I/O protection, no swap on control-plane nodes, a dedicated disk, taint/label swap nodes for swap-aware scheduling. |

---

## Step 1
```bash
cd concepts/cluster-administration/swap-memory-management
./start-swap-lab.sh
#   {"failSwapOn":false,"memorySwap":{"swapBehavior":"LimitedSwap"}}
kubectl --context swap-lab get node swap-lab -o jsonpath='{.status.nodeInfo.swap}'    # {"capacity":8589930496}
```

## Lab – Who may swap, and how much
```bash
kubectl --context swap-lab apply -f 01-pods.yaml
for p in default/besteffort default/burstable default/guaranteed kube-system/burstable-critical; do
  echo "$p: $(kubectl --context swap-lab exec -n ${p%/*} ${p#*/} -- cat /sys/fs/cgroup/memory.swap.max)"; done
#   default/besteffort:               0
#   default/burstable:                141504512        <- 512Mi request
#   default/guaranteed:               0
#   kube-system/burstable-critical:   0                <- high priority: kept in RAM
```
Check the formula with the node's numbers (`free -b`: Mem 32589910016, Swap 8589930496):
```
536870912 / 32589910016 × 8589930496 = 141,506,491   vs  memory.swap.max 141,504,512   (≈2 KB apart: the kubelet's own reading of total memory)
```
`kubectl top node --show-swap` needs metrics-server, which isn't enabled in this profile. On the main cluster (NoSwap) it shows `SWAP 0Mi`.

```bash
./cleanup.sh       # stops swap-lab
```

---

## Useful commands
```bash
kubectl get nodes -o custom-columns=NAME:.metadata.name,SWAP:.status.nodeInfo.swap.capacity
kubectl get --raw /api/v1/nodes/<n>/proxy/configz | jq '.kubeletconfig | {failSwapOn, memorySwap}'
kubectl exec <pod> -- cat /sys/fs/cgroup/memory.swap.max /sys/fs/cgroup/memory.swap.current
kubectl top node --show-swap ; kubectl top pod --show-swap
```
