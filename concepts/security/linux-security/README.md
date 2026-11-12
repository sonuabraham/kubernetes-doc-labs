# Security for Linux Nodes – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/security/linux-security/

> A short page with no YAML: **memory-backed volumes and swap**. [00-secret-pod.yaml](00-secret-pod.yaml) mounts a Secret and a `medium: Memory` emptyDir so you can check how they're protected on your node.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **tmpfs** | Secret volumes and `emptyDir.medium: Memory` are tmpfs: RAM, never the node's disk... |
| **...unless swap** | With swap on, tmpfs pages can be **swapped out to disk**, so Secret data could persist on a swap device. |
| **noswap** | Kernel **6.3+** supports the tmpfs `noswap` mount option (or a backport). The kubelet uses it when swap is enabled, so memory-backed volumes stay in RAM. |
| **Recommendation** | Kernel ≥ 6.3 if swap is on. Otherwise no swap, or encrypted swap. See `../../cluster-administration/swap-memory-management`. |

---

## Lab 1 – Is swap on, and how is it configured?
```bash
cd concepts/security/linux-security
minikube ssh -- "uname -r; free -m | grep -i swap"
#   7.0.0-38-generic                                  <- the HOST kernel (docker driver shares it)
#   Swap:  8191  3  8188                              <- swap IS available on this node
kubectl get --raw /api/v1/nodes/minikube/proxy/configz | jq -c '.kubeletconfig | {failSwapOn, memorySwap}'
#   {"failSwapOn":false,"memorySwap":{}}               <- kubelet allowed to run with swap; swapBehavior default (NoSwap)
```

## Lab 2 – Memory-backed volumes get noswap
```bash
kubectl apply -f 00-secret-pod.yaml ; kubectl wait --for=condition=Ready pod/sec -n linsec-demo
kubectl exec sec -n linsec-demo -- sh -c 'mount | grep -E " /s | /m "'
#   tmpfs on /s type tmpfs (ro,relatime,size=31826084k,inode64,noswap)    <- Secret
#   tmpfs on /m type tmpfs (rw,relatime,size=31826084k,inode64,noswap)    <- emptyDir medium: Memory
kubectl exec sec -n linsec-demo -- cat /sys/fs/cgroup/memory.swap.max
#   0                                                  <- and the container itself may not swap (NoSwap behaviour)
```
On a kernel older than 6.3 (no backport) with swap on, `noswap` would be missing and Secret contents could reach the swap device. Check this on real nodes, especially long-lived VMs with old distro kernels.

---

## Useful commands
```bash
kubectl get nodes -o custom-columns=NAME:.metadata.name,KERNEL:.status.nodeInfo.kernelVersion
kubectl get --raw /api/v1/nodes/<n>/proxy/configz | jq '.kubeletconfig | {failSwapOn, memorySwap}'
```

## Cleanup
```bash
./cleanup.sh
```
