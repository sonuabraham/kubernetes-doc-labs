# Manage HugePages – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/manage-hugepages/scheduling-hugepages/

> Runs on the default **minikube** cluster. Files (docs, **verbatim**): [huge-pages-two-sizes.yaml](huge-pages-two-sizes.yaml) (2Mi + 1Gi),
> [huge-pages-one-size.yaml](huge-pages-one-size.yaml) (`medium: HugePages`). Not from the docs: [hugepages.sh](hugepages.sh) (pre-allocate / free),
> [hugepages-user.yaml](hugepages-user.yaml) (a Python Pod that really maps huge pages).
>
> ⚠️ The minikube node is a container on **your** kernel: `vm.nr_hugepages` is the host's setting and the pages are taken from host RAM
> (128 × 2 MiB = 256 MiB here). Always run [cleanup.sh](cleanup.sh), which sets it back to 0.
>
> **Notes from testing:**
> - Only **2 MiB** pages can be allocated here (`sysctl vm.nr_hugepages` works in the node). 1 GiB pages need
>   `/sys/kernel/mm/hugepages/…` (read-only in the node) or the kernel command line (the docs' GRUB line), so the two-size Pod stays Pending.
> - "A pod may use `medium: HugePages` only if it requests huge pages of one size" is **not checked by the API server**: such a Pod is accepted.
> - The pages are taken from node memory: allocatable `memory` dropped by exactly 256Mi.

## Key ideas (read first)

| Rule | Tested result |
|---|---|
| Resource name `hugepages-<size>` | node reports `hugepages-2Mi: 256Mi` after allocation + kubelet restart |
| No overcommit, requests == limits | `must be equal to hugepages-2Mi limit of 20Mi` |
| Must also request cpu or memory | `Forbidden: HugePages require cpu or memory` |
| Multiples of the page size | `3Mi is not positive integer multiple of hugepages-2Mi` |
| Per-container/Pod limit | Pod cgroup `hugetlb.2MB.max = 104857600`; mapping past it → `ENOMEM` |
| Volume | `emptyDir.medium: HugePages` / `HugePages-<size>` → a `hugetlbfs` mount |
| Quota | `requests.hugepages-2Mi` in a ResourceQuota |

---

## Lab 1 – Pre-allocate (docs prerequisites)
```bash
cd tasks/manage-hugepages/scheduling-hugepages
./hugepages.sh alloc 128          # sysctl vm.nr_hugepages=128 in the node, then kubelet restart (docs note)
#   HugePages_Total: 128 HugePages_Free: 128 Hugepagesize: 2048 kB
#   {"hugepages-1Gi":"0","hugepages-2Mi":"256Mi"}
kubectl describe node minikube | sed -n '/^Capacity/,/^System Info/p' | grep -E 'hugepages|memory'
#   Capacity:    hugepages-1Gi 0   hugepages-2Mi 256Mi   memory 31826084Ki
#   Allocatable: hugepages-1Gi 0   hugepages-2Mi 256Mi   memory 31563940Ki     <- 256Mi less memory
```

## Lab 2 – The docs' Pods
```bash
kubectl apply -f huge-pages-two-sizes.yaml
kubectl get events --field-selector involvedObject.name=huge-pages-example,reason=FailedScheduling
#   0/1 nodes are available: 1 Insufficient hugepages-1Gi.
kubectl delete pod huge-pages-example
kubectl apply -f huge-pages-one-size.yaml          # Running (fedora:latest, ~2 min to pull)
kubectl exec huge-pages-example -- mount | grep hugepages
#   nodev on /hugepages type hugetlbfs (rw,relatime,pagesize=2M)
minikube ssh -- "sudo cat /sys/fs/cgroup/kubepods.slice/kubepods-burstable.slice/kubepods-burstable-pod<uid>.slice/hugetlb.2MB.max"
#   104857600                                        <- the 100Mi limit, on the Pod cgroup
```

## Lab 3 – Use them, and hit the limit (not from the docs)
```bash
kubectl apply -f hugepages-user.yaml               # limit hugepages-2Mi: 100Mi; maps 40 MiB, then 80 MiB more
kubectl logs hugepages-user
#   a: 40 MiB mapped and touched
#   OSError: [Errno 12] Cannot allocate memory     <- 40 + 80 > 100 Mi
minikube ssh -- grep HugePages_Free /proc/meminfo   # 108 while "a" is mapped (20 pages × 2 MiB), 128 again after exit
```
(`dd`/`cat` can't write to hugetlbfs, only `mmap` can, which is why the docs' fedora Pod just sleeps.)

## Lab 4 – API rules (docs list, tested with server dry runs)
```
limits {hugepages-2Mi: 10Mi} only                        → Forbidden: HugePages require cpu or memory
requests 10Mi, limits 20Mi                               → must be equal to hugepages-2Mi limit of 20Mi
limits 3Mi                                               → 3Mi is not positive integer multiple of hugepages-2Mi
two sizes + emptyDir medium: HugePages                   → pod/hp4 created (server dry run)   <- not validated by the API
ResourceQuota requests.hugepages-2Mi=50Mi + Pod 100Mi    → exceeded quota: hp-quota, requested: requests.hugepages-2Mi=100Mi …
```

## Cleanup
```bash
./cleanup.sh          # Pods, quota, vm.nr_hugepages=0 + kubelet restart
```
