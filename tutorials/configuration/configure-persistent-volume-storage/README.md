# Configure a Pod to Use a PersistentVolume for Storage – Hands-on Lab

Based on: https://kubernetes.io/docs/tutorials/configuration/configure-persistent-volume-storage/

> Runs on the default single-node **minikube**, namespace `default`. `pv-volume.yaml`, `pv-claim.yaml`, `pv-pod.yaml`, `pv-duplicate.yaml`
> and `nginx.conf` are the docs examples `pods/storage/…` **verbatim**. [pv-gid.yaml](pv-gid.yaml) completes the page's
> `pv.beta.kubernetes.io/gid` snippet (NOT from the docs apart from the metadata).
>
> **Found:**
> - **`cat <<EOF > /mnt/data/nginx.conf` fails on the node:** `bash: line 1: /mnt/data/nginx.conf: Permission denied`. `minikube ssh` logs
>   in as `docker`, and `/mnt/data` was made with `sudo` (owned by root). The page uses `sudo` everywhere except here.
>   Use `minikube cp nginx.conf minikube:/mnt/data/nginx.conf` or `sudo tee`.
> - **If the file is missing, the Pod crash-loops.** The kubelet creates the missing `subPath` source as a **directory**
>   (`drwxr-xr-x … nginx.conf`) and then can't bind it onto the file `/etc/nginx/nginx.conf`:
>   `error mounting … to rootfs at "/etc/nginx/nginx.conf": … not a directory` → `CrashLoopBackOff`. Remove that directory
>   (`sudo rmdir /mnt/data/nginx.conf`) before you copy the file.
> - `apt update && apt install curl` isn't needed: the `nginx` image (nginx 1.31.9, Debian 13 trixie) already has `/usr/bin/curl`.
> - The PVC asks for 3Gi but shows `CAPACITY 10Gi`: a claim binds to a whole PV.
>
> **Note:** `minikube ssh` doesn't forward stdin, so node commands are passed as one string: `minikube ssh '…'`.

## Key ideas (read first)

| Object | Who makes it | Here |
|---|---|---|
| PersistentVolume | cluster admin | `task-pv-volume`: hostPath `/mnt/data`, 10Gi, RWO, `storageClassName: manual`, reclaim `Retain` |
| PersistentVolumeClaim | developer | `task-pv-claim`: 3Gi RWO from class `manual` → binds to the PV |
| Pod | developer | mounts the **claim**; it never names the PV |
| `subPath` | – | mount one directory/file *inside* the volume; same volume mounted twice |
| `pv.beta.kubernetes.io/gid` | admin | the GID is added to every container's supplemental groups (not visible in the Pod spec) |

## Lab 1 – PV → PVC → Pod
```bash
minikube ssh                                              # node shell
  sudo mkdir /mnt/data
  sudo sh -c "echo 'Hello from Kubernetes storage' > /mnt/data/index.html"
  cat /mnt/data/index.html                                # Hello from Kubernetes storage
  exit
kubectl apply -f pv-volume.yaml
kubectl get pv task-pv-volume
#   task-pv-volume   10Gi   RWO   Retain   Available           manual   <unset>   0s
kubectl apply -f pv-claim.yaml
kubectl get pv task-pv-volume
#   task-pv-volume   10Gi   RWO   Retain   Bound   default/task-pv-claim   manual   <unset>   3s
kubectl get pvc task-pv-claim
#   task-pv-claim   Bound   task-pv-volume   10Gi   RWO   manual   <unset>   3s
kubectl apply -f pv-pod.yaml
kubectl get pod task-pv-pod                               # 1/1 Running
kubectl exec -it task-pv-pod -- /bin/bash
  apt update; apt install curl                            # optional, curl is already there
  curl http://localhost/                                  # Hello from Kubernetes storage
  exit
kubectl delete pod task-pv-pod
```

## Lab 2 – The same PV mounted twice (`subPath`)
```bash
minikube ssh 'sudo mkdir /mnt/data/html && sudo mv /mnt/data/index.html /mnt/data/html/index.html'

# docs (in the node shell) – fails:
minikube ssh 'cat <<EOF > /mnt/data/nginx.conf
…
EOF'
#   bash: line 1: /mnt/data/nginx.conf: Permission denied
# works:
minikube cp nginx.conf minikube:/mnt/data/nginx.conf
minikube ssh 'grep keepalive /mnt/data/nginx.conf'        # keepalive_timeout  60;

kubectl apply -f pv-duplicate.yaml
kubectl get pod test                                      # 1/1 Running
kubectl exec -it test -- /bin/bash
  curl http://localhost/                                  # Hello from Kubernetes storage
  cat /etc/nginx/nginx.conf | grep keepalive_timeout      #     keepalive_timeout  60;
  exit
```
What happens if you start `test` before the file exists (NOT from the docs; that's what happens after the failed heredoc):
```bash
kubectl get pod test                                      # 0/1 CrashLoopBackOff
kubectl get events --field-selector involvedObject.name=test,reason=Failed
#   … error mounting "…/volume-subpaths/task-pv-volume/test/1" to rootfs at "/etc/nginx/nginx.conf": … not a directory
minikube ssh 'ls -la /mnt/data'                           # drwxr-xr-x … nginx.conf    <- kubelet made a directory
kubectl delete pod test --now; minikube ssh 'sudo rmdir /mnt/data/nginx.conf'    # then copy the file and re-apply
```

## Lab 3 – GID annotation (NOT from the docs: [pv-gid.yaml](pv-gid.yaml))
```bash
minikube ssh 'sudo mkdir -p /mnt/data-gid && sudo chgrp 1234 /mnt/data-gid && sudo chmod 2770 /mnt/data-gid'
kubectl apply -f pv-gid.yaml                              # pv1 (annotated gid 1234) + pv1-claim + Pod gid-demo (runAsUser 1000)
kubectl exec gid-demo -- id                               # uid=1000 gid=0(root) groups=0(root),1234
kubectl exec gid-demo -- sh -c 'touch /data/f && ls -ln /data'    # -rw-r--r-- 1 1000 1234 … f   <- write allowed via group 1234
kubectl get pod gid-demo -o jsonpath='{.spec.securityContext}'    # {"runAsUser":1000}   <- 1234 isn't in the Pod spec
```

## Cleanup
Docs: `kubectl delete pod test`, `kubectl delete pvc task-pv-claim`, `kubectl delete pv task-pv-volume`, then on the node `sudo rm` the
files and `sudo rmdir` the directories. All of this, plus the GID demo:
```bash
./cleanup.sh
```
