# Expose Pod Information to Containers Through Files – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/inject-data-application/downward-api-volume-expose-pod-information/

> Runs on the default **minikube** cluster, `default` namespace. Files: [dapi-volume.yaml](dapi-volume.yaml),
> [dapi-volume-resources.yaml](dapi-volume-resources.yaml) (docs, **verbatim**), [dapi-volume-extras.yaml](dapi-volume-extras.yaml) (not from the docs).
> The same information as environment variables: [environment-variable-expose-pod-information](../environment-variable-expose-pod-information/).
>
> **Found:** the `annotations` file holds more than `build`/`builder`. `kubectl apply` adds
> `kubectl.kubernetes.io/last-applied-configuration` (the whole manifest), and the kubelet adds `kubernetes.io/config.seen`/`config.source`.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| Volume vs. env | Files can also hold **whole maps** (`metadata.labels`, `metadata.annotations`), which env vars can't |
| Live updates | Label/annotation changes reach the files within seconds; env vars never change |
| Atomic swap | Files sit in a timestamped dir; `..data` symlink is renamed atomically to a new one |
| `subPath` | A `subPath` mount of the volume is **frozen** at container start |
| `resourceFieldRef` | Needs `containerName` in a volume; `divisor` + round-up as for env; no limit -> node allocatable |
| Read-only | The volume is mounted read-only; `defaultMode` / per-item `mode` set file permissions |

---

## Lab 1 – Pod fields (docs)
```bash
cd tasks/inject-data-application/downward-api-volume-expose-pod-information
kubectl apply -f dapi-volume.yaml
kubectl logs kubernetes-downwardapi-volume-example --tail=7
#   cluster="test-cluster1"
#   rack="rack-22"
#   zone="us-est-coast"
#
#   build="two"
#   builder="john-doe"
#   kubectl.kubernetes.io/last-applied-configuration="{\"apiVersion\":\"v1\",…}\n"   <- not in the docs' output
#   kubernetes.io/config.seen="2026-11-15T11:22:37.075936996Z"
kubectl exec kubernetes-downwardapi-volume-example -- ls -laR /etc/podinfo
#   drwxr-xr-x  ..2026_11_15_11_22_37.2262485557
#   lrwxrwxrwx  ..data -> ..2026_11_15_11_22_37.2262485557
#   lrwxrwxrwx  annotations -> ..data/annotations
#   lrwxrwxrwx  labels -> ..data/labels
#   /etc/podinfo/..2026_11_15_11_22_37.2262485557:
#   -rw-r--r--  annotations   (1120 bytes, mostly last-applied-configuration)
#   -rw-r--r--  labels
```
Use `kubectl create` instead of `apply` if you don't want the last-applied annotation in the file.

## Lab 2 – Container fields (docs)
```bash
kubectl apply -f dapi-volume-resources.yaml
for f in cpu_limit cpu_request mem_limit mem_request; do
  echo "$f=$(kubectl exec kubernetes-downwardapi-volume-example-2 -- cat /etc/podinfo/$f)"; done
#   cpu_limit=250      <- 250m / divisor 1m
#   cpu_request=125
#   mem_limit=64       <- 64Mi / divisor 1Mi
#   mem_request=32
```

## Lab 3 – Live updates, subPath, modes (not from the docs)
```bash
kubectl create -f dapi-volume-extras.yaml
kubectl exec dapi-volume-extras -- sh -c 'cd /etc/podinfo; for f in version owner meta/name cpu_limit mem_limit_mi; do echo "$f: $(cat $f)"; done; ls -l ..data/meta/'
#   version: v1                 <- metadata.labels['version']
#   owner: team-a               <- metadata.annotations['owner']
#   meta/name: dapi-volume-extras   <- paths may contain sub-directories
#   cpu_limit: 8                <- no CPU limit: node allocatable
#   mem_limit_mi: 32
#   -r--r--r--  name            <- defaultMode 0444
#   -r--------  uid             <- per-item mode 0400
kubectl label pod dapi-volume-extras version=v2 --overwrite
kubectl annotate pod dapi-volume-extras owner=team-b --overwrite
kubectl exec dapi-volume-extras -- sh -c 'cat /etc/podinfo/version /etc/podinfo/owner; echo ---; cat /etc/labels-subpath'
#   v2                          <- updated within a few seconds (no restart)
#   team-b
#   ---
#   app="dapi-demo"
#   version="v1"                <- the subPath mount never updates
kubectl exec dapi-volume-extras -- touch /etc/podinfo/x
#   touch: /etc/podinfo/x: Read-only file system
```

## Useful commands
```bash
kubectl exec <pod> -- readlink /etc/podinfo/..data      # current timestamped dir
kubectl explain pod.spec.volumes.downwardAPI.items
```

## Cleanup
```bash
./cleanup.sh
```
