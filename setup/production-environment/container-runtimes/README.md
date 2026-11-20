# Container Runtimes – Hands-on Lab

Based on: https://kubernetes.io/docs/setup/production-environment/container-runtimes/

> The page is about installing and configuring a CRI runtime on a node. minikube can run all three runtimes the page covers, so
> [inspect-runtime.sh](inspect-runtime.sh) (NOT from the docs) starts a throwaway profile per runtime (`--container-runtime=…`), prints what
> the page talks about, runs a test Pod and deletes the profile. Stop the default `minikube` first (inotify limit).
>
> **Found:**
> - **Which containerd config keys apply depends on the config file's `version`, not on the containerd version.** minikube runs
>   containerd **2.3.4** with a `version = 2` file (1.x schema: `[plugins."io.containerd.grpc.v1.cri"…]`), which containerd 2 migrates on
>   load (`containerd config dump` → `version = 4`). containerd 2.3's own `containerd config default` is **`version = 4`**. There the
>   runc options are under `plugins.'io.containerd.cri.v1.runtime'` (as the page says for 2.x) and its default is `SystemdCgroup = false`
>   (so setting it really is needed).
> - **The page's pause-image override is the 1.x form only:** `[plugins."io.containerd.grpc.v1.cri"] sandbox_image = …`. In a
>   version 3/4 file the setting is `[plugins.'io.containerd.cri.v1.images'.pinned_images] sandbox = 'registry.k8s.io/pause:3.10.2'`.
> - The page's example pause tag is `3.10`; the runtimes here use **`registry.k8s.io/pause:3.10.2`**.
> - The minikube node has no `sysctl` command. `cat /proc/sys/net/ipv4/ip_forward` → `1` on all three (Docker sets it on the host).

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| CRI v1 | since v1.26 the kubelet only talks CRI **v1**; otherwise the node doesn't register |
| cgroup driver | kubelet and runtime must agree; with systemd as init + cgroup v2 use **`systemd`**. Newer runtimes report it via the `RuntimeConfig` RPC and the kubelet picks it up |
| containerd | socket `/run/containerd/containerd.sock`; `SystemdCgroup = true` in the runc options |
| CRI-O | socket `/var/run/crio/crio.sock`; `cgroup_manager` (default `systemd`), `conmon_cgroup = "pod"` required with `cgroupfs` |
| Docker Engine | needs the **cri-dockerd** adapter; socket `/run/cri-dockerd.sock`; pause image via `--pod-infra-container-image` |
| IPv4 forwarding | `net.ipv4.ip_forward = 1` (`/etc/sysctl.d/k8s.conf`) |

## Lab
```bash
cd setup/production-environment/container-runtimes
minikube stop
./inspect-runtime.sh containerd
./inspect-runtime.sh cri-o
./inspect-runtime.sh docker
minikube start
```
Results (Kubernetes v1.37.0, minikube v1.39.0):

| | containerd | CRI-O | Docker + cri-dockerd |
|---|---|---|---|
| `nodeInfo.containerRuntimeVersion` | `containerd://2.3.4` | `cri-o://1.35.7` | `docker://29.7.2` |
| `crictl version` RuntimeApiVersion | `v1` | `v1` | `v1` |
| kubelet `containerRuntimeEndpoint` | `unix:///run/containerd/containerd.sock` | `unix:///var/run/crio/crio.sock` | `unix:///var/run/cri-dockerd.sock` |
| kubelet `cgroupDriver` | `systemd` | `systemd` | `systemd` |
| runtime cgroup setting | `SystemdCgroup = true` (config `version = 2`) | `cgroup_manager = "systemd"`, `conmon_cgroup = "pod"` | `docker info` CgroupDriver `systemd` |
| pause image | `sandbox_image = "registry.k8s.io/pause:3.10.2"` | `pause_image = "registry.k8s.io/pause:3.10.2"` | `cri-dockerd … --pod-infra-container-image=registry.k8s.io/pause:3.10.2` |
| `ip_forward` | 1 | 1 | 1 |
| test Pod | Running | Running | Running |

cri-dockerd runs as `cri-docker.service` + `cri-docker.socket` (`ExecStart=/usr/bin/cri-dockerd --container-runtime-endpoint fd:// --pod-infra-container-image=… --network-plugin=cni --hairpin-mode=hairpin-veth`).

containerd: the page's two config forms vs. the real files:
```bash
minikube ssh -- containerd config default | head -1                    # version = 4
minikube ssh -- containerd config default | grep -nE "SystemdCgroup|pinned_images|sandbox ="
#   [plugins.'io.containerd.cri.v1.images'.pinned_images]   sandbox = 'registry.k8s.io/pause:3.10.2'
#   [plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runc] … SystemdCgroup = false
minikube ssh -- sudo containerd config dump | grep -E "^version|SystemdCgroup"    # version = 4 … SystemdCgroup = true   (minikube's v2 file, migrated)
```

## Cleanup
Each run deletes its profile (`rt-containerd`, `rt-cri-o`, `rt-docker`). Nothing else changes.
