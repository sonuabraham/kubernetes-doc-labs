# Configure a Pod to Use a Volume for Storage – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/configure-pod-container/configure-volume-storage/

> Runs on the default **minikube** cluster, in the `default` namespace as in the docs.
> File: [redis.yaml](redis.yaml) (docs, **verbatim**). The docs' interactive shell steps are shown as one-shot
> `kubectl exec` commands so you can paste them. `kubectl exec -it redis -- /bin/bash` works too.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **Container filesystem** | Lives as long as the *container*. A restart starts from the image again. |
| **`emptyDir`** | A directory created when the Pod is put on a node and deleted with the **Pod**. It survives container restarts. On disk it is `/var/lib/kubelet/pods/<pod-uid>/volumes/kubernetes.io~empty-dir/<name>`. |
| **`restartPolicy: Always`** | The Pod default. When redis exits, the kubelet restarts the container *in the same Pod*, so the emptyDir is still there. |
| **Not for durable data** | Pod deleted or node lost means the data is gone. Use a PersistentVolume for that (see [concepts/storage](../../../concepts/storage/)). |

```
Pod redis (uid U) ──────────────────────────────────────────── deleted ⇒ emptyDir deleted
 ├─ container redis #0  fs: image + /tmp/not-in-volume  ✗ lost on restart
 ├─ container redis #1  (after kill)
 └─ volume redis-storage (emptyDir) → /data/redis/test-file  ✓ kept across restarts
        = node:/var/lib/kubelet/pods/U/volumes/kubernetes.io~empty-dir/redis-storage
```

---

## Step 0
```bash
cd tasks/configure-pod-container/configure-volume-storage
kubectl apply -f redis.yaml
kubectl get pod redis --watch          # Ctrl-C once 1/1 Running
```

## Lab 1 – Write a file into the volume (and one outside it)
```bash
kubectl exec redis -- sh -c 'cd /data/redis && echo Hello > test-file && echo lost > /tmp/not-in-volume'
kubectl exec redis -- sh -c 'apt-get update -qq; apt-get install -y -qq procps; ps aux'   # the docs' procps install
#   USER   PID  …  COMMAND
#   redis    1  …  redis-server *:6379        <- PID 1 in the container
```
The same file seen from the node:
```bash
U=$(kubectl get pod redis -o jsonpath='{.metadata.uid}')
minikube ssh -- "sudo ls -l /var/lib/kubelet/pods/$U/volumes/kubernetes.io~empty-dir/redis-storage/"
#   -rw-r--r-- 1 root root 6 Nov 15 02:52 test-file
```

## Lab 2 – Kill redis, watch the restart
```bash
kubectl exec redis -- kill 1           # the docs: kill <pid>; redis is PID 1
kubectl get pod redis
#   redis   1/1   Running   1 (6s ago)   14s        <- RESTARTS 1 (the --watch window shows Completed → Running)
kubectl exec redis -- sh -c 'ls /data/redis; cat /data/redis/test-file; ls /tmp; which ps || echo "ps: gone"'
#   test-file
#   Hello            <- kept: it is in the emptyDir
#                    <- /tmp is empty: /tmp/not-in-volume was in the old container's filesystem
#   ps: gone         <- so was the procps package installed in Lab 1
```

## Lab 3 – Delete the Pod: the emptyDir goes with it (not from the docs)
```bash
U=$(kubectl get pod redis -o jsonpath='{.metadata.uid}')
kubectl delete pod redis
minikube ssh -- "sudo ls /var/lib/kubelet/pods/$U/volumes"
#   kubernetes.io~empty-dir  kubernetes.io~projected      <- right after the delete: the kubelet cleans up asynchronously
sleep 5; minikube ssh -- "sudo ls /var/lib/kubelet/pods/$U/volumes"
#   ls: cannot access '/var/lib/kubelet/pods/…/volumes': No such file or directory
```

## Useful commands
```bash
kubectl get pod redis -o jsonpath='{.status.containerStatuses[0].restartCount}{"\n"}'
kubectl get pod redis -o jsonpath='{.status.containerStatuses[0].lastState}{"\n"}'
```

## Cleanup
```bash
./cleanup.sh     # kubectl delete pod redis
```
