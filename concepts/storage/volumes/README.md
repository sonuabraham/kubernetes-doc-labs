# Volumes – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/storage/volumes/

> All 12 YAML blocks from the page are here **verbatim** (`01-…` to `12-…`), plus [image-volumes.yaml](image-volumes.yaml) and [rro.yaml](rro.yaml). Several docs Pods share the name `test-pd`, so each goes into its own namespace. [00-prereqs.yaml](00-prereqs.yaml) creates the ConfigMaps, Secrets and PVC the docs Pods reference (namespace `vol-demo`).

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Why volumes** | Container files are ephemeral (lost on restart) and not shared. Volumes give containers in a Pod shared, longer-lived storage. |
| **Ephemeral vs persistent** | Ephemeral volume types live and die with the **Pod**. Persistent ones (PVs) outlive it. Both survive **container** restarts. |
| **How** | `spec.volumes` (what) + `containers[].volumeMounts` (where). Each container mounts independently. |
| **configMap / secret / downwardAPI / projected** | Expose API data as files (see `../projected-volumes`, `../../configuration`). |
| **emptyDir** | Created empty when the Pod is assigned to a node, deleted with the Pod. `medium: Memory` → tmpfs (counts as memory). `sizeLimit` caps usage (enforced by **eviction** for disk). `mode` needs `EmptyDirVolumeMode` (alpha). |
| **hostPath** | A node file or dir in the Pod: a **security risk**, avoid. Types `DirectoryOrCreate`, `FileOrCreate`, `Directory`, `File`, `Socket`, `CharDevice`, `BlockDevice`. |
| **image** | Mounts an OCI image/artifact read-only (`ImageVolume`, on in v1.37). |
| **local** | A disk on a specific node, as a PV with **nodeAffinity**. No dynamic provisioning. |
| **nfs / iscsi / fc** | Network storage. The data survives the Pod. |
| **persistentVolumeClaim** | Use a PV through a claim (see `../persistent-volumes`). |
| **Removed / deprecated** | gitRepo (disabled), gcePersistentDisk, portworxVolume, flexVolume. In-tree plugins migrated to **CSI** drivers. |
| **subPath / subPathExpr** | Mount one sub-directory of a volume. `subPathExpr` expands env vars such as `$(POD_NAME)`. |
| **Read-only** | `readOnly: true` (sub-mounts stay writable). `recursiveReadOnly: Enabled` makes sub-mounts read-only too (stable). |
| **Mount propagation** | `None`, `HostToContainer`, `Bidirectional`. |

## Step 1
```bash
cd concepts/storage/volumes
kubectl apply -f 00-prereqs.yaml
for ns in vol-ed1 vol-ed2 vol-ed3 vol-nfs; do kubectl create namespace $ns; done
```

## Lab 1 – configMap volume (docs `configmap-pod`)
```bash
kubectl apply -f 01-configmap-pod.yaml -n vol-demo
kubectl exec configmap-pod -n vol-demo -- cat /etc/config/log_level.conf      # INFO   (key log_level → file log_level.conf)
```

## Lab 2 – emptyDir: disk, memory, mode
```bash
kubectl apply -f 02-emptydir-sizelimit.yaml -n vol-ed1
kubectl apply -f 03-emptydir-memory.yaml -n vol-ed2
kubectl get pod test-pd -n vol-ed1
#   ImagePullBackOff - "registry.k8s.io/test-webserver" is published in the old Docker schema-1 format:
#   not implemented: media type "application/vnd.docker.distribution.manifest.v1+prettyjws"  (containerd 2.x refuses it)
```
The docs image doesn't run on containerd 2. Run the same manifests with a working image:
```bash
for n in 1 2; do kubectl delete pod test-pd -n vol-ed$n --ignore-not-found; done
sed 's#registry.k8s.io/test-webserver#nginx:1.27#' 02-emptydir-sizelimit.yaml | kubectl apply -n vol-ed1 -f -
sed 's#registry.k8s.io/test-webserver#nginx:1.27#' 03-emptydir-memory.yaml   | kubectl apply -n vol-ed2 -f -
kubectl exec test-pd -n vol-ed1 -- df -h /cache       # /dev/nvme… 240G   <- node disk; the 500Mi limit is enforced by eviction, not the mount
kubectl exec test-pd -n vol-ed2 -- mount | grep /cache # tmpfs on /cache type tmpfs (rw,size=512000k,noswap)   <- RAM, 500Mi
kubectl apply -f 04-emptydir-mode.yaml -n vol-ed3 --dry-run=server -o jsonpath='{.spec.volumes[0]}{"\n"}'
#   {"emptyDir":{},"name":"cache-volume"}    <- "mode: 01777" DROPPED: EmptyDirVolumeMode is alpha and off
```

## Lab 3 – hostPath (docs `test-webserver`)
```bash
kubectl apply -f 05-hostpath-fileorcreate.yaml -n vol-demo        # same test-webserver image problem; the volumes are still set up:
minikube ssh -- ls -la /var/local/aaa/                              # 1.txt created by FileOrCreate, dir by DirectoryOrCreate
```

## Lab 4 – image volume
```bash
kubectl apply -f image-volumes.yaml ; kubectl wait --for=condition=Ready pod/image-volume
kubectl exec image-volume -- ls /volume              # dir file    <- contents of the OCI artifact quay.io/crio/artifact:v2
kubectl exec image-volume -- touch /volume/x         # Read-only file system
```
[06-image-volume-status-excerpt.yaml](06-image-volume-status-excerpt.yaml) shows the `status.containerStatuses[].volumeMounts[].imageRef` digest field, which needs `ImageVolumeWithDigest` (alpha, off here).

## Lab 5 – local PV, NFS, Portworx (environment-specific)
```bash
kubectl apply -f 07-local-pv.yaml                    # PV only; nodeAffinity → "example-node" (doesn't exist), so nothing could use it
kubectl apply -f 08-nfs-pod.yaml -n vol-nfs          # ContainerCreating - my-nfs-server.example.com doesn't exist
kubectl apply -f 09-portworx-pod.yaml -n vol-demo
kubectl get events -n vol-demo --field-selector involvedObject.name=test-portworx-volume-pod,type=Warning -o custom-columns=M:.message | tail -1
#   AttachVolume.Attach failed for volume "pxd.portworx.com-pxvol" : timed out waiting for external-attacher of pxd.portworx.com CSI driver
```
That last one is **CSI migration** in action: the in-tree `portworxVolume` is translated to the `pxd.portworx.com` CSI driver, which isn't installed.

## Lab 6 – subPath (docs LAMP) and subPathExpr
```bash
kubectl apply -f 10-lamp-subpath.yaml -n vol-demo ; kubectl wait --for=condition=Ready pod/my-lamp-site -n vol-demo --timeout=300s
kubectl exec my-lamp-site -c php -n vol-demo -- ls /var/www/html ; kubectl exec my-lamp-site -c mysql -n vol-demo -- ls /var/lib/mysql | head -3
#   ONE PVC, two sub-directories: html/ for php, mysql/ for MySQL
kubectl apply -f 11-subpathexpr.yaml -n vol-demo
minikube ssh -- "sudo ls /var/log/pods | grep pod1"       # vol-demo_pod1_… - the dir named after $(POD_NAME)
```

## Lab 7 – Read-only vs recursive read-only (docs `rro`)
The docs manifest assumes a tmpfs mounted at `/mnt/tmpfs` **on the node**. Create it first:
```bash
minikube ssh -- "sudo mkdir -p /mnt/tmpfs && sudo mount -t tmpfs tmpfs /mnt/tmpfs"
kubectl apply -f rro.yaml ; kubectl wait --for=condition=Ready pod/rro
kubectl exec rro -- sh -c 'for d in /mnt-rro /mnt-ro /mnt-rw; do touch $d/tmpfs/w 2>/dev/null && echo "$d/tmpfs writable" || echo "$d/tmpfs NOT writable"; done'
#   /mnt-rro/tmpfs NOT writable    <- recursiveReadOnly: Enabled
#   /mnt-ro/tmpfs writable         <- plain readOnly: the SUB-mount stays writable!
#   /mnt-rw/tmpfs writable
```

## Lab 8 – Per-file ownership (docs, alpha)
```bash
kubectl apply -f 12-volume-user-fields.yaml -n vol-demo --dry-run=server
#   spec.volumes[0].name: Invalid value: "volA": a lowercase RFC 1123 label must consist of ...
```
The docs example is **invalid as written**: volume names must be lowercase (`vola`, …). It also needs `AtomicWriteVolumeUserFields` (alpha, off), so `defaultUser`/`user` would be dropped anyway.

---

## Useful commands
```bash
kubectl explain pod.spec.volumes --recursive | less
kubectl exec <pod> -- mount | grep <path> ; kubectl exec <pod> -- df -h <path>
kubectl get pod <pod> -o jsonpath='{.spec.volumes}'
```

## Cleanup
```bash
./cleanup.sh       # namespaces, local PV, default-ns docs pods, the node tmpfs and /var/local/aaa
```
