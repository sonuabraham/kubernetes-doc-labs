# Use an Image Volume With a Pod – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/configure-pod-container/image-volumes/

> Runs on the default **minikube** cluster: `ImageVolume` is **GA** in 1.37 and containerd 2.3 supports it.
> Files: [image-volumes.yaml](image-volumes.yaml), [image-volumes-subpath.yaml](image-volumes-subpath.yaml) (docs, **verbatim**).
> Concepts: [concepts/storage/volumes](../../../concepts/storage/volumes/) (`image` volume).

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **`volumes[].image`** | Mounts the content of an OCI image or **artifact** (`reference`) read-only into containers. It is pulled like a container image, with the same `pullPolicy` semantics and pull secrets. |
| **Uses** | ML models, static content, binaries or config shipped separately from the app image and versioned in a registry. |
| **Read-only** | Always. Writes fail with `Read-only file system`. |
| **Immutable** | The `reference` of a running Pod can't change. Roll out a new Pod instead. |
| **subPath / subPathExpr** | Supported since 1.33: mount just one directory of the image. |

```
quay.io/crio/artifact:v2  (1.6 kB OCI artifact: /file = "2", /dir/file = "1")
        │ pulled by containerd like an image
        ▼
Pod image-volume ── /volume (ro)            -> /volume/file, /volume/dir/file
                 └─ /volume (ro, subPath dir) -> /volume/file = "1"
```

---

## Step 0
```bash
cd tasks/configure-pod-container/image-volumes
kubectl get --raw /metrics | grep 'name="ImageVolume"'      # stage="" 1  (GA)
```

## Lab 1 – Mount an artifact (docs)
```bash
kubectl apply -f image-volumes.yaml
kubectl exec image-volume -- cat /volume/dir/file      # 1
kubectl exec image-volume -- cat /volume/file          # 2
kubectl exec image-volume -- sh -c 'mount | grep " /volume "'
#   overlay on /volume type overlay (ro,relatime,lowerdir=/var/lib/containerd/…snapshots/1261/fs:…)
minikube ssh -- "sudo crictl images | grep artifact"
#   quay.io/crio/artifact   v2   3906a75569c2d   1.6kB      <- stored like any other image
```

## Lab 2 – Read-only and immutable (not from the docs)
```bash
kubectl exec image-volume -- touch /volume/x
#   touch: cannot touch '/volume/x': Read-only file system
kubectl patch pod image-volume --type=json -p '[{"op":"replace","path":"/spec/volumes/0/image/reference","value":"quay.io/crio/artifact:v1"}]'
#   The Pod "image-volume" is invalid: spec: Forbidden: pod updates may not change fields other than …
#   -    "Reference": "quay.io/crio/artifact:v2",
#   +    "Reference": "quay.io/crio/artifact:v1",
```

## Lab 3 – subPath (docs)
```bash
kubectl delete pod image-volume --now
kubectl apply -f image-volumes-subpath.yaml
kubectl exec image-volume -- cat /volume/file     # 1   <- /dir/file of the artifact
kubectl exec image-volume -- ls /volume           # file
```

## Useful commands
```bash
kubectl get pod <p> -o jsonpath='{.spec.volumes[?(@.image)]}'
minikube ssh -- sudo crictl images
```

## Cleanup
```bash
./cleanup.sh
```
