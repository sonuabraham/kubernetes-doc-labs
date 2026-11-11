# Garbage Collection – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/architecture/garbage-collection/

> Cluster: the **`arch-lab`** profile (see [../README.md](../README.md)). Owner references, finalizers and invalid cross-namespace owners are covered in `../../overview/working-with-objects/owners-dependents` and `.../finalizers`. This lab focuses on **what gets cleaned up, by whom, and when**.

## Key ideas (read first)

| What is collected | By | When |
|---|---|---|
| Dependents of a deleted owner | garbage collector (kube-controller-manager) | Cascading deletion: background (default), foreground, or orphan |
| Terminated / orphaned pods | PodGC controller | Pods bound to a **node that no longer exists**. Terminated pods above `--terminated-pod-gc-threshold` (default 12500) |
| Finished Jobs | TTL-after-finished controller | `ttlSecondsAfterFinished` |
| Dynamically provisioned PVs | PV controller | When the PVC is deleted and `reclaimPolicy: Delete` |
| Stale CSRs | CSR cleaner | Pending > 24h, approved/denied > 1h |
| Nodes | cloud-controller-manager (or similar addon) | The VM is gone |
| Node Leases | – | With their Node |
| Dead containers | **kubelet**, every **minute** | `MinAge`, `MaxPerPodContainer`, `MaxContainers` |
| Unused images | **kubelet**, every **5 minutes** | Disk above `imageGCHighThresholdPercent` → delete oldest-used until `imageGCLowThresholdPercent`, **or** unused longer than `imageMaximumGCAge` |

| Cascading mode | What happens |
|---|---|
| **Background** (default) | The owner is deleted **immediately**, and the GC removes dependents afterwards. |
| **Foreground** | The owner gets `deletionTimestamp` plus the `foregroundDeletion` finalizer and **stays visible** until all dependents with `blockOwnerDeletion=true` are gone. |
| **Orphan** | The owner gets the `orphan` finalizer, dependents are kept, and their ownerReferences are removed. |

Don't use external GC tools on nodes. They can remove containers the kubelet still expects.

## The demo app
Namespace `gc-demo`. [01-deployment.yaml](01-deployment.yaml) is a Deployment `web` (3 pods that take **20s to terminate**, so you can watch timelines). [02-job-ttl.yaml](02-job-ttl.yaml), [03-pod-on-missing-node.yaml](03-pod-on-missing-node.yaml), [04-pvc-delete.yaml](04-pvc-delete.yaml) and [05-crashloop.yaml](05-crashloop.yaml) cover one GC case each.

---

## Step 1
```bash
cd concepts/architecture/garbage-collection
kubectl config use-context arch-lab
kubectl apply -f 00-namespace.yaml
c(){ echo "deploy=$(kubectl get deploy web -n gc-demo --no-headers 2>/dev/null|wc -l) rs=$(kubectl get rs -n gc-demo --no-headers 2>/dev/null|wc -l) pods=$(kubectl get pods -n gc-demo -l app=web --no-headers 2>/dev/null|wc -l)"; }
```

## Lab 1 – The three cascading deletion modes
**Foreground**
```bash
kubectl apply -f 01-deployment.yaml ; kubectl rollout status deploy/web -n gc-demo
kubectl delete deploy web -n gc-demo --cascade=foreground --wait=false
for i in 1 2 3 4 5; do sleep 4; echo "+$((i*4))s $(c)"; done
kubectl get deploy web -n gc-demo -o jsonpath='{.metadata.finalizers} {.metadata.deletionTimestamp}{"\n"}'   # run while it is still there
```
Expected:
```
+4s  deploy=1 rs=1 pods=3      <- owner still VISIBLE ("deletion in progress"), finalizers ["foregroundDeletion"]
+16s deploy=1 rs=1 pods=3
+20s deploy=0 rs=0 pods=0      <- pods gone (20s grace) -> RS gone -> Deployment gone
```
**Background** (the default)
```bash
kubectl apply -f 01-deployment.yaml ; kubectl rollout status deploy/web -n gc-demo
kubectl delete deploy web -n gc-demo --wait=false
sleep 3 ; c        # deploy=0 rs=0 pods=3   <- owner gone at once; pods cleaned up in the background
```
**Orphan**
```bash
kubectl apply -f 01-deployment.yaml ; kubectl rollout status deploy/web -n gc-demo
kubectl delete deploy web -n gc-demo --cascade=orphan --wait=false -v=8 2>&1 | grep -A3 'Request Body' | grep -o '{.*}'
#   {"propagationPolicy":"Orphan"}           <- the --cascade flag is just this field in the DELETE body
c                  # deploy=0 rs=1 pods=3
kubectl get rs -n gc-demo -o jsonpath='{.items[0].metadata.ownerReferences}{"\n"}'     # (empty) - orphaned
kubectl delete rs -n gc-demo -l app=web    # clean up the orphans
```

## Lab 2 – Finished Jobs (TTL-after-finished)
```bash
kubectl apply -f 02-job-ttl.yaml
kubectl get job,pods -n gc-demo -l batch.kubernetes.io/job-name=short-lived -w     # Complete ... then ~15s later both vanish
```

## Lab 3 – Pods bound to a missing node (PodGC)
```bash
kubectl apply -f 03-pod-on-missing-node.yaml
kubectl get pod ghost -n gc-demo             # Pending, NODE node-that-was-deleted
sleep 45 ; kubectl get pod ghost -n gc-demo  # NotFound - the pod garbage collector removed it
```
The same thing happens to a real node's pods when its Node object is deleted (`../cloud-controller` Lab 4).

## Lab 4 – Dynamically provisioned PVs (reclaimPolicy Delete)
```bash
kubectl apply -f 04-pvc-delete.yaml ; sleep 5
PV=$(kubectl get pvc scratch -n gc-demo -o jsonpath='{.spec.volumeName}')
kubectl get pv $PV -o jsonpath='{.spec.persistentVolumeReclaimPolicy}{"\n"}'     # Delete (from StorageClass "standard")
kubectl delete pvc scratch -n gc-demo
kubectl get pv $PV                          # NotFound - deleted together with the claim
```
Set `persistentVolumeReclaimPolicy: Retain` on the PV first and it survives as `Released`.

## Lab 5 – Kubelet: dead containers
```bash
kubectl apply -f 05-crashloop.yaml ; sleep 60
kubectl get pod crasher -n gc-demo                               # RESTARTS 3+
minikube ssh -p arch-lab -n arch-lab -- "sudo crictl ps -a --name '^c$' --state exited"
#   ONE exited container, although it has crashed several times   <- MaxPerPodContainer (default 1) - older ones were collected
```
The last dead container is kept so `kubectl logs crasher --previous` works.

## Lab 6 – Kubelet: unused images (imageMaximumGCAge)
This takes ~8 minutes. Turn on age-based image GC on the control-plane kubelet:
```bash
minikube ssh -p arch-lab -n arch-lab -- "sudo grep -E 'imageGC|imageM' /var/lib/kubelet/config.yaml"
#   imageGCHighThresholdPercent: 100      <- minikube effectively disables disk-based image GC
#   imageMaximumGCAge: 0s                 <- age-based GC off
#   imageMinimumGCAge: 0s                 <- 0 = default (2m)
minikube ssh -p arch-lab -n arch-lab -- "sudo sed -i 's/^imageMaximumGCAge: .*/imageMaximumGCAge: 3m/' /var/lib/kubelet/config.yaml && sudo systemctl restart kubelet"
minikube ssh -p arch-lab -n arch-lab -- "sudo crictl pull docker.io/library/alpine:3.19 && sudo crictl images | grep alpine"   # an image no pod uses
```
Wait for the next GC pass (every 5 minutes after the kubelet restart). Then:
```bash
minikube ssh -p arch-lab -n arch-lab -- "sudo crictl images | grep alpine"        # gone
minikube ssh -p arch-lab -n arch-lab -- "sudo journalctl -u kubelet --since -10min | grep 'Removing image'"
#   image_gc_manager.go] "Removing image to free bytes" imageID="sha256:83b2b670…" size=3429495   (and other unused images too)
```
What you'll trip over:
- `imageMaximumGCAge` must be **greater** than `imageMinimumGCAge`. With `2m` the kubelet refuses to start: `imageMaximumGCAge 2m0s must be greater than imageMinimumGCAge 2m0s`.
- The age resets when the kubelet restarts (docs note), so the countdown starts from the restart.
- **Every** unused image on that node is a candidate, not just alpine. Pods then pull again on their next start.
- On `arch-lab` a kubelet restart can fail with `Too many open files` (inotify limit, see [../README.md](../README.md)).

---

## Useful commands
```bash
kubectl delete <kind> <name> --cascade=background|foreground|orphan
kubectl get <kind> <name> -o jsonpath='{.metadata.finalizers} {.metadata.deletionTimestamp}'
kubectl get pod -A --field-selector status.phase=Failed      # candidates for terminated-pod GC
minikube ssh -- sudo crictl images ; minikube ssh -- sudo crictl ps -a
```

## Cleanup
```bash
./cleanup.sh        # deletes gc-demo and resets imageMaximumGCAge to 0s (restarts the kubelet)
```
