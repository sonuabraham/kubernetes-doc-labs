# Set Permissions on an emptyDir Volume – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/configure-pod-container/configure-emptydir-volume-mode/

> `EmptyDirVolumeMode` is **alpha (off)** in 1.37. Lab 1 shows the default cluster, Lab 2 uses the throwaway profile
> `volopt-lab` from [start-volopt-lab.sh](start-volopt-lab.sh), which is shared with [../configure-bind-mount-options](../configure-bind-mount-options/).
> Files: [emptydir-volume-mode.yaml](emptydir-volume-mode.yaml) (docs, **verbatim**),
> [emptydir-volume-mode-fixed.yaml](emptydir-volume-mode-fixed.yaml) (image pinned, not from the docs).
>
> **Docs problem:** `image: registry.k8s.io/busybox` (= `:latest`) is an old schema-1 image. containerd ≥ 2.1 refuses it:
> `ErrImagePull … media type "application/vnd.docker.distribution.manifest.v1+prettyjws" is no longer supported since containerd v2.1`.
> Only the `1.27.2` tag of that repository is a modern image.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **`emptyDir.mode`** | Permission bits of the volume's directory, `0`…`01777` (octal). Without it: `0777`. |
| **`01777`** | `drwxrwxrwt`: everyone can create files, but only the owner can delete them (the sticky bit, like `/tmp` on Linux). |
| **No setuid/setgid** | Values above `01777` (e.g. `02777` setgid) are rejected. |
| **Gate off** | The API server **drops** the field silently, and you get `0777`. |

---

## Step 0
```bash
cd tasks/configure-pod-container/configure-emptydir-volume-mode
kubectl get --raw /metrics | grep 'name="EmptyDirVolumeMode"'     # stage="ALPHA" 0
```

## Lab 1 – Default cluster: the field disappears
```bash
kubectl apply -f emptydir-volume-mode.yaml
kubectl get pod emptydir-mode-demo -o json | jq -c .spec.volumes[0]
#   {"emptyDir":{},"name":"tmp-volume"}                <- "mode: 01777" was dropped
kubectl get pod emptydir-mode-demo                     # ErrImagePull / ImagePullBackOff (docs problem above)
kubectl delete pod emptydir-mode-demo --now
kubectl apply -f emptydir-volume-mode-fixed.yaml
kubectl exec emptydir-mode-demo -- ls -ld /tmp
#   drwxrwxrwx    2 root  root  4096 … /tmp             <- default 0777, no sticky bit
kubectl delete pod emptydir-mode-demo --now
```

## Lab 2 – With the gate (profile volopt-lab)
```bash
minikube stop                     # two clusters exhaust this host's inotify instances
./start-volopt-lab.sh
K="kubectl --context volopt-lab"
$K apply -f emptydir-volume-mode-fixed.yaml
$K get pod emptydir-mode-demo -o json | jq -c .spec.volumes[0]
#   {"emptyDir":{"mode":1023},"name":"tmp-volume"}     <- 1023 = 01777 octal (JSON has no octal)
$K exec emptydir-mode-demo -- ls -ld /tmp
#   drwxrwxrwt    2 root  root  4096 … /tmp             <- the "t"
```
Validation (server-side dry runs with other values):
| `mode` | Result |
|---|---|
| `01777`, `0700` | accepted |
| `02777`, `07777` | `emptyDir.mode: Invalid value: 1535: must be a number between 0 and 01777 (octal), both inclusive` |
```bash
minikube delete -p volopt-lab; minikube start
```

## Useful commands
```bash
kubectl exec <pod> -- stat -c '%A %a %n' <mountPath>
```

## Cleanup
```bash
./cleanup.sh
```
