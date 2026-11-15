# Set Bind Mount Options on Volume Mounts – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/configure-pod-container/configure-bind-mount-options/

> `VolumeBindMountOptions` is **alpha (off)** in 1.37. Lab 2 uses the throwaway profile `volopt-lab`
> ([../configure-emptydir-volume-mode/start-volopt-lab.sh](../configure-emptydir-volume-mode/start-volopt-lab.sh)).
> Files: [bind-mount-options.yaml](bind-mount-options.yaml) (docs, **verbatim**),
> [bind-mount-options-fixed.yaml](bind-mount-options-fixed.yaml) (image pinned: `registry.k8s.io/busybox` = `:latest` can't be pulled by
> containerd ≥ 2.1, see [../configure-emptydir-volume-mode](../configure-emptydir-volume-mode/)).
>
> **Result on this machine:** the Pod **can't run** even with the gate on. containerd 2.3.4 doesn't advertise the CRI
> `mount_options` capability, so the kubelet doesn't declare the feature, and the scheduler and kubelet both refuse the Pod.
> That's the page's "the container runtime must also support `mount_options`" prerequisite, and you can see Kubernetes enforce it.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **`volumeMounts[].bindMountOptions`** | Extra flags for the bind mount into the container: only `noexec`, `nodev`, `nosuid`. Hardening for writable volumes such as `/tmp`. |
| **Needs** | the gate on the API server **and** kubelet, **plus** a runtime that implements CRI `Mount.mount_options`. |
| **Node declared features** | The kubelet publishes what it supports in `node.status.declaredFeatures`. A Pod using the field *requires* `VolumeBindMountOptions`, so the scheduler filters nodes on it and the kubelet rejects it if missing. |

---

## Step 0
```bash
cd tasks/configure-pod-container/configure-bind-mount-options
kubectl get --raw /metrics | grep 'name="VolumeBindMountOptions"'     # stage="ALPHA" 0
```

## Lab 1 – Default cluster: field dropped, binaries run
```bash
kubectl apply -f bind-mount-options-fixed.yaml
kubectl get pod bind-mount-options-demo -o json | jq -c .spec.containers[0].volumeMounts[0]
#   {"mountPath":"/tmp","name":"tmp-volume"}                     <- bindMountOptions dropped
kubectl exec bind-mount-options-demo -- sh -c 'mount | grep " /tmp "; cp /bin/ls /tmp/ls && /tmp/ls / | head -2'
#   /dev/nvme0n1p5 on /tmp type ext4 (rw,relatime,stripe=64)     <- no noexec
#   bin
#   dev                                                          <- executed fine
kubectl delete pod bind-mount-options-demo --now
```

## Lab 2 – With the gate (profile volopt-lab)
```bash
minikube stop; ../configure-emptydir-volume-mode/start-volopt-lab.sh
K="kubectl --context volopt-lab"
$K apply -f bind-mount-options-fixed.yaml
$K get pod bind-mount-options-demo -o json | jq -c .spec.containers[0].volumeMounts[0]
#   {"bindMountOptions":["noexec","nosuid"],"mountPath":"/tmp","name":"tmp-volume"}     <- kept now
$K get pod bind-mount-options-demo                 # Pending
$K describe pod bind-mount-options-demo | grep FailedScheduling
#   0/1 nodes are available: 1 node(s) didn't match Pod's required features. …
$K get node volopt-lab -o json | jq -c .status.declaredFeatures
#   ["ExtendWebSocketsToKubelet","InPlacePodLevelResourcesVerticalScaling","InPlacePodVerticalScalingInitContainers","RestartAllContainersOnContainerExits"]
$K get --raw /api/v1/nodes/volopt-lab/proxy/configz | jq -c .kubeletconfig.featureGates
#   {"EmptyDirVolumeMode":true,"VolumeBindMountOptions":true}      <- the kubelet HAS the gate…
minikube -p volopt-lab ssh -- sudo crictl info | jq -c .features
#   {"supplemental_groups_policy":true}                            <- …but containerd doesn't offer mount options
```
Skip the scheduler with `nodeName`, and the kubelet refuses it instead:
```bash
$K delete pod bind-mount-options-demo --now
$K create -f <(kubectl create --dry-run=client -o json -f bind-mount-options-fixed.yaml | jq '.spec.nodeName="volopt-lab"')
$K get pod bind-mount-options-demo -o jsonpath='{.status.reason}: {.status.message}{"\n"}'
#   PodFeatureUnsupported: Pod was rejected: Pod requires node features that are not available: VolumeBindMountOptions
```
API validation (works without a capable runtime):
| `bindMountOptions` | Result |
|---|---|
| `[noexec, nodev, nosuid]` | accepted |
| `[ro]` | `Unsupported value: "ro": supported values: "nodev", "noexec", "nosuid"` |
| `[noexec, noexec]` | `Duplicate value: "noexec"` |

On a runtime with support, the docs' checks would show `noexec,nosuid` in `mount | grep /tmp`, and
`cp /bin/ls /tmp/ls && /tmp/ls` would fail with `sh: /tmp/ls: Permission denied`.
```bash
minikube delete -p volopt-lab; minikube start
```

## Useful commands
```bash
kubectl get nodes -o custom-columns=NAME:.metadata.name,FEATURES:.status.declaredFeatures
```

## Cleanup
```bash
./cleanup.sh
```
