# Windows Containers in Kubernetes – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/windows/intro/

> ⚠️ **minikube can't run Windows nodes.** The page has no YAML. This lab tests what can be tested from a Linux cluster:
> - The API server's **OS-field validation** ([os-field-matrix.sh](os-field-matrix.sh), server dry-run).
> - The **kubelet's OS check** ([00-wrong-os.yaml](00-wrong-os.yaml)).
> - **Scheduling in a mixed cluster**, using two API-only Windows nodes from [../fake-windows-nodes.sh](../fake-windows-nodes.sh): `win-2022` (build 10.0.20348) and `win-2025` (10.0.26100). Nothing actually runs on them.
> - **Image/OS version matching**, read from the registries ([images.sh](images.sh)).

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Mixed clusters** | The control plane is **Linux only**. Windows worker nodes join it. Supported node OS for v1.37: **Windows Server 2022 and 2025**. Only **process isolation** is supported (no Hyper-V isolation). |
| **One OS per Pod** | A Pod's containers all run on one node, so you can't mix Windows and Linux containers in a Pod. |
| **Same API** | Pods, Deployments, StatefulSets, DaemonSets, Jobs, CronJobs, Services, probes, lifecycle hooks, ConfigMaps/Secrets, emptyDir, resource limits, `kubectl exec`, metrics, HPA, quotas and preemption all work. |
| **`spec.os.name: windows`** | Declares the Pod's OS. The API then **rejects 20 Linux-only fields** (hostPID/IPC, SELinux, seccomp, fsGroup, sysctls, runAsUser/Group, capabilities, privileged, readOnlyRootFilesystem…). Only `runAsNonRoot` and `windowsOptions` work in the Pod securityContext. |
| **Not supported on Windows** | HugePages, privileged containers (use **HostProcess** containers), host network for normal Pods, `emptyDir.medium: Memory`, mount propagation, raw block `volumeDevices`, shared process namespace. Some of these the API does **not** check (Lab 1). |
| **Identity & signals** | SIDs and ACLs instead of UID/GID and mode bits. `\` paths. Termination is `CTRL_SHUTDOWN_EVENT` and a 5s registry default, not SIGTERM. |
| **kubelet differences** | No CPU/memory limits on the kubelet itself. `--kube-reserved`/`--system-reserved` only shrink NodeAllocatable. No `PIDPressure`. No OOM eviction. `--windows-priorityclass`. |
| **Version matching** | The container image's Windows **build must match the host's**. Nodes carry `node.kubernetes.io/windows-build`. The pause image is a multi-OS manifest list (`registry.k8s.io/pause:3.6`, or Microsoft's signed `mcr.microsoft.com/oss/kubernetes/pause:3.6`). |
| **Runtimes** | containerd 1.4+ (stable), Mirantis Container Runtime. |

---

## Step 1
```bash
cd concepts/windows/intro
../fake-windows-nodes.sh up
#   NAME       OS-IMAGE                                KERNEL-VERSION         WINDOWS-BUILD
#   minikube   Debian GNU/Linux 12 (bookworm)          7.0.0-38-generic       
#   win-2022   Windows Server 2022 Datacenter (fake)   10.0.20348.1 (amd64)   10.0.20348
#   win-2025   Windows Server 2025 Datacenter (fake)   10.0.26100.1 (amd64)   10.0.26100
kubectl create ns win-intro
```

## Lab 1 – What `spec.os.name: windows` forbids, and what it doesn't
```bash
./os-field-matrix.sh
#   == 1. Fields the page forbids with os.name=windows
#     spec.hostPID                                         REJECTED  spec.hostPID
#     ... all 20 fields from the page: REJECTED
#     containers[*].securityContext.runAsGroup             REJECTED  spec.containers[0].securityContext.runAsGroup
#   == 2. Unsupported on Windows per the page, but not policed by the API
#     spec.hostNetwork                                     ACCEPTED
#     dnsPolicy: ClusterFirstWithHostNet                   ACCEPTED
#     emptyDir medium: Memory                              ACCEPTED
#     volumeMounts mountPropagation                        ACCEPTED
#     volumeDevices (raw block)                            ACCEPTED
#     hugepages-2Mi limit                                  ACCEPTED
#     terminationGracePeriodSeconds: 120                   ACCEPTED
#   == 3. Allowed on Windows
#     securityContext.runAsNonRoot / windowsOptions.runAsUserName / hostProcess   ACCEPTED
#   == 4. The reverse
#     os=linux + windowsOptions                            REJECTED  spec.securityContext.windowsOptions
#     no os field + windowsOptions                         ACCEPTED   <- without spec.os neither list is enforced
```
Set `spec.os.name` on every Pod: it's the only way the API can catch OS-specific mistakes. The items in group 2 fail later, on the node.

## Lab 2 – The kubelet checks the OS too
```bash
kubectl apply -f 00-wrong-os.yaml          # windows Pod bound straight to the Linux node
kubectl get pod wrong-os -n win-intro
#   NAME       READY   STATUS              RESTARTS   AGE
#   wrong-os   0/1     PodOSNotSupported   0          6s
kubectl get events -n win-intro --field-selector reason=PodOSNotSupported
#   Warning   PodOSNotSupported   pod/wrong-os   Failed to admit pod as the OS field doesn't match node OS
```
The Pod's phase is `Failed`. It never restarts. The API accepted it, because the API doesn't know the node's OS.

## Lab 3 – The scheduler ignores `spec.os.name`
[01-no-selector.yaml](01-no-selector.yaml) is a 4-replica Windows Deployment **without** `nodeSelector`. [storm.sh](storm.sh) runs it for 10 seconds, then stops it:
```bash
./storm.sh
#   after 10s (node / phase / count):
#       100 minikube   Failed      <- rejected by the Linux kubelet, replaced by the ReplicaSet, rejected again...
#         1 win-2022   Pending
#         2 win-2025   Pending
#   Failed to admit pod as the OS field doesn't match node OS
```
⚠️ Don't leave this running. The first unbounded attempt produced **252 Failed Pods in 25s**. The ReplicaSet doesn't count Failed Pods, and the Linux node (8 CPUs free) keeps winning the scoring. The fix is a `nodeSelector` and/or taints (see `../user-guide`).

The same problem exists the other way round:
```bash
kubectl get pods -n kube-system -o wide --field-selector spec.nodeName=win-2022
#   csi-hostpathplugin-np99n   0/6   Pending   win-2022    <- Linux DaemonSets with no OS selector target Windows nodes
#   kindnet-f6wvq              0/1   Pending   win-2022
kubectl get ds -n kube-system kube-proxy -o jsonpath='{.spec.template.spec.nodeSelector}'    # {"kubernetes.io/os":"linux"}  <- the right way
```

## Lab 4 – Images must match the host build
```bash
./images.sh
#   == pause image (multi-OS manifest list)
#   registry.k8s.io/pause:3.6        linux/amd64, linux/arm, ..., windows/amd64 10.0.17763.2114, ..., windows/amd64 10.0.20348.169
#   mcr.microsoft.com/oss/kubernetes/pause:3.6   linux/amd64, linux/arm64, windows/amd64 10.0.17763.2300, ..., 10.0.20348.350
#   == Windows base images
#   mcr.microsoft.com/windows/nanoserver:ltsc2022     windows/amd64 10.0.20348.5870    -> win-2022 nodes
#   mcr.microsoft.com/windows/nanoserver:ltsc2025     windows/amd64 10.0.26100.33822   -> win-2025 nodes
#   mcr.microsoft.com/windows/servercore:ltsc2019     windows/amd64 10.0.17763.9487    -> Server 2019: no supported node in v1.37
```
The major.minor.build (`10.0.20348`) is what has to match, and it's what the `windows-build` node label holds. Windows images are **large** (300MB to 10GB+). Each container's `C:` has a 20GB virtual size by default.

Finding: none of the pause tags I checked (3.6, 3.9, 3.10, 3.10.1) has a `10.0.26100` (Server 2025) entry. Check which sandbox image your Windows nodes' containerd is configured with.

---

## Useful commands
```bash
kubectl get nodes -L kubernetes.io/os,node.kubernetes.io/windows-build -o wide
kubectl get pods -A -o wide --field-selector spec.nodeName=<windows-node>
docker manifest inspect -v <image> | jq '.[].Descriptor.platform'
```

## Cleanup
```bash
./cleanup.sh        # force-deletes win-intro (Pods on fake nodes), removes the fake Windows nodes
```
