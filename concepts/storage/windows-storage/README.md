# Windows Storage – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/storage/windows-storage/

> ⚠️ **Needs Windows nodes**, which minikube can't run. The page has no YAML. This lab shows what's checkable from a Linux-only cluster: how a Windows Pod's storage spec is validated, and where each unsupported feature gets caught. For real practice use a cluster with a Windows Server 2022 node pool (AKS, EKS, GKE) plus a CSI driver with Windows support (e.g. Azure Disk/File, SMB CSI) and CSI Proxy on the nodes.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Container filesystem** | A layered NTFS-based driver. Paths resolve inside the container only. |
| **Mounts** | Directory targets only with Docker (files OK with containerd). No projecting back to the host. **Read-only volumes: yes. Read-only root filesystem: no** (the registry and SAM need write access). |
| **Permissions** | The SAM isn't shared with the host, so there's no uid/gid mapping and no user masks. Permissions resolve inside the container. |
| **Not supported** | subPath mounts (including for Secrets), host mount projection, read-only rootfs, **block devices**, `emptyDir.medium: Memory`, uid/gid and Linux permissions (so Secret `defaultMode`), **NFS**, online resize (resizefs). |
| **Plugins** | **CSI** (node side via **CSI Proxy**), FlexVolume (deprecated). In-tree: `azureFile`, `vsphereVolume` (both migrated to CSI). |

## The demo app
| File | What |
|---|---|
| [00-windows-pod.yaml](00-windows-pod.yaml) | Windows Pod (`os.name: windows` + `nodeSelector kubernetes.io/os: windows`) using only **supported** storage: a whole PVC, a read-only ConfigMap volume, a disk emptyDir |
| [01-unsupported.yaml](01-unsupported.yaml) | Seven Windows Pods, each using one **unsupported** feature (and **no** nodeSelector) |

---

## Lab 1 – A supported spec still needs a Windows node
```bash
cd concepts/storage/windows-storage
kubectl apply -f 00-windows-pod.yaml
kubectl get events -n winstor-demo --field-selector involvedObject.name=win-app -o custom-columns=M:.message | tail -1
#   0/1 nodes are available: 1 node(s) didn't match Pod's node affinity/selector.
kubectl get pvc win-data -n winstor-demo      # Bound - provisioning (Immediate) doesn't care about the Pod's OS
```
With `Immediate` binding, the volume was created for a Pod that may never run here. On mixed clusters, use a **WaitForFirstConsumer** class so the volume is provisioned where the Windows Pod is scheduled (and by a driver that has a Windows node plugin).

## Lab 2 – Where each unsupported feature is caught
```bash
kubectl apply -f 01-unsupported.yaml
```
| Pod | Feature | Result |
|---|---|---|
| `ro-rootfs` | `readOnlyRootFilesystem: true` | **API rejects**: `readOnlyRootFilesystem: Forbidden: cannot be set for a windows pod` |
| `fsgroup` | `securityContext.fsGroup` | **API rejects**: `fsGroup: Forbidden: cannot be set for a windows pod` |
| `memory-emptydir` | `emptyDir.medium: Memory` | accepted by the API |
| `subpath` | `subPath` | accepted by the API |
| `secret-defaultmode` | Secret `defaultMode: 0400` | accepted by the API |
| `block-device` | `volumeDevices` | accepted by the API |
| `nfs` | `nfs:` volume | accepted by the API |

`os.name: windows` lets the API server reject **Linux-only securityContext** fields up front. The volume-level limitations aren't API-validated: on a real Windows node they fail at **mount time** (or are silently ignored, like `defaultMode`).

And since these Pods have no nodeSelector:
```bash
kubectl get pods -n winstor-demo
#   block-device         0/1   PodOSNotSupported
#   memory-emptydir      0/1   PodOSNotSupported   ...
kubectl get pod nfs -n winstor-demo -o jsonpath='{.status.reason}: {.status.message}{"\n"}'
#   PodOSNotSupported: Pod was rejected: Failed to admit pod as the OS field doesn't match node OS
```
The scheduler placed them on the Linux node, and the **kubelet refused** them because of `os.name`. Always pair `os.name` with `nodeSelector: {kubernetes.io/os: windows}` (or a RuntimeClass that carries it, see `../../containers/runtime-class`).

---

## Useful commands
```bash
kubectl get nodes -L kubernetes.io/os,node.kubernetes.io/windows-build
kubectl get csidriver ; kubectl get csinode <windows-node> -o jsonpath='{.spec.drivers[*].name}'
kubectl explain pod.spec.os
```

## Cleanup
```bash
./cleanup.sh
```
