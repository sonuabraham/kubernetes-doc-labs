# Configuring swap memory on Kubernetes nodes – Hands-on Lab

Based on: https://kubernetes.io/docs/tutorials/cluster-management/provision-swap-memory/

> The page has two parts: make swap on the node (`fallocate`, `mkswap`, `swapon`, optionally `cryptsetup`), then set the kubelet's swap
> configuration. On minikube (docker driver) the node is a container on the host kernel:
> - **Swap is the host's.** The node already sees the host's 8 GiB swap file (`free -h` → `Swap: 8.0Gi`). The page itself says
>   provisioning is only needed "if swap is not enabled". Running `swapon`/`cryptsetup` in the privileged node would change the
>   **host** kernel, so this lab doesn't. The node image has no `swapon`, `mkswap` or `cryptsetup` anyway (only `fallocate`).
> - The kubelet part runs on the throwaway profile **`swap-lab`** (from
>   [concepts/…/swap-memory-management](../../../concepts/cluster-administration/swap-memory-management/)). The default minikube is
>   stopped meanwhile (two clusters exhaust inotify on this host).
>
> **Found:**
> - **The page's kubelet fragment is indented by one space on every line.** Pasted verbatim at the end of the config file it breaks the
>   YAML: `expected <block end>, but found '<block mapping start>' … line 4, column 2`. Remove the leading space
>   ([kubelet-swap-fragment.yaml](kubelet-swap-fragment.yaml) is the fragment exactly as shown on the page).
> - minikube's kubelet config already has `failSwapOn: false`. Without `memorySwap` the behaviour is **NoSwap**: a Burstable Pod gets
>   `memory.swap.max = 0`.
> - The page stops at "you can run Pods that use swap memory as needed". [swap-demo.yaml](swap-demo.yaml) (NOT from the docs) shows it:
>   a Burstable Pod using more memory than its **limit** survives by swapping, up to its proportional swap share.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| Node swap | swap must exist on the node (file or partition, optionally encrypted with `cryptsetup … -d /dev/urandom`) and be on at boot (fstab / systemd unit) |
| `failSwapOn: false` | the kubelet starts even though swap is on (default `true` → kubelet refuses) |
| `memorySwap.swapBehavior` | `NoSwap` (default: workloads get no swap) or `LimitedSwap` |
| LimitedSwap | only **Burstable** Pods (not high-priority), each container `memory.swap.max = request / node RAM × node swap` |
| Restart | kubelet reads its config file only at start: `systemctl restart kubelet.service` |
| `node.status.nodeInfo.swap.capacity` | how much swap the kubelet found |

## Lab 1 – Swap on the node (docs: verify)
```bash
minikube stop
minikube start -p swap-lab
minikube -p swap-lab ssh -- free -h
#   Mem:   30Gi   14Gi   2.9Gi …
#   Swap:  8.0Gi  284Mi  7.7Gi          <- the host's swap, visible in the node
minikube -p swap-lab ssh -- swapon -s   # bash: line 1: swapon: command not found   (not in the node image)
```
The page's commands to create swap, for a real (VM / bare-metal) node, unencrypted:
`fallocate --length 4GiB /swapfile; chmod 600 /swapfile; mkswap /swapfile; swapon /swapfile`.
Encrypted: `cryptsetup --type plain --cipher aes-xts-plain64 --key-size 256 -d /dev/urandom open /swapfile cryptswap; mkswap /dev/mapper/cryptswap; swapon /dev/mapper/cryptswap`.
The key comes from `/dev/urandom`, so the swap contents can't be read after a reboot. That's the point; the device has to be re-created at every boot.

## Lab 2 – Configure the kubelet
Starting point (NOT from the docs: `memorySwap` removed from `/var/lib/kubelet/config.yaml`, kubelet restarted):
```bash
kubectl get --raw /api/v1/nodes/swap-lab/proxy/configz | python3 -c 'import json,sys; k=json.load(sys.stdin)["kubeletconfig"]; print(k["failSwapOn"], k.get("memorySwap"))'
#   False {}                                     <- NoSwap
# a Burstable Pod (request 512Mi, limit 1Gi):  cat /sys/fs/cgroup/memory.swap.max  → 0
```
Docs: add the fragment (without the leading space) and restart the kubelet:
```bash
minikube -p swap-lab ssh
  sudo vi /var/lib/kubelet/config.yaml       # failSwapOn: false
                                             # memorySwap:
                                             #     swapBehavior: LimitedSwap
  sudo systemctl restart kubelet.service
  systemctl is-active kubelet                # active
  exit
kubectl get --raw /api/v1/nodes/swap-lab/proxy/configz | python3 -c '…'      # False {'swapBehavior': 'LimitedSwap'}
kubectl get node swap-lab -o jsonpath='{.status.nodeInfo.swap}'              # {"capacity":8589930496}
```

## Lab 3 – A Pod that uses swap (NOT from the docs)
```bash
kubectl apply -f swap-demo.yaml
kubectl get pods
#   swap-fits      1/1   Running     0   18s
#   swap-too-big   0/1   OOMKilled   0   18s
kubectl logs swap-fits                       # allocated 680 MiB     (limit is 600Mi!)
kubectl exec swap-fits -- sh -c 'cat /sys/fs/cgroup/memory.max /sys/fs/cgroup/memory.swap.max /sys/fs/cgroup/memory.current /sys/fs/cgroup/memory.swap.current'
#   629145600 (600Mi)   141504512 (swap share)   583159808   141295616   <- RAM at the limit, the rest swapped out
# swap-too-big needed ~200 MiB of swap > 141 MB → OOMKilled, exit 137
```
Swap share: 536870912 (512Mi request) / 32589910016 (node RAM) × 8589930496 (node swap) ≈ 141.5 MB.

## Cleanup
```bash
./cleanup.sh     # delete the demo Pods, minikube stop -p swap-lab (keeps LimitedSwap), minikube start
```
