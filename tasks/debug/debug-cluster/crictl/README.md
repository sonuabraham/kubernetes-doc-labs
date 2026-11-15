# Debugging Kubernetes nodes with crictl – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/debug/debug-cluster/crictl/

> minikube's node already has `crictl` (v1.35.0) configured for containerd, so everything runs with `minikube ssh -- sudo crictl …`.
> The docs' example Pods (`nginx` with label `run=nginx`, and `sh`) are created with `kubectl run`.
>
> **Found:** in crictl v1.35.0, the docs' `crictl images nginx` (and `crictl images docker.io/library/nginx`) **ignores the repository
> filter** and lists every image. Pipe through `grep` instead.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **crictl** | A CLI for the **CRI**, the same gRPC API the kubelet uses to talk to containerd/CRI-O. It sees *what the node really runs*, including Pods the API server no longer knows about. |
| **Endpoint** | `/etc/crictl.yaml` (`runtime-endpoint`, `image-endpoint`, `timeout`, `debug`), env vars, or `--runtime-endpoint`. |
| **Read-only habits** | `pods`, `ps`, `images`, `inspect`, `inspectp`, `logs`, `stats` are safe. `stop`, `rm`, `rmp` work against the kubelet, which reconciles right back. |
| **Pod vs container** | `crictl pods` = sandboxes (the pause container + network namespace). `crictl ps` = app containers. |

---

## Step 0 – Something to look at (docs' Pods)
```bash
cd tasks/debug/debug-cluster/crictl
kubectl run nginx --image=nginx                                     # label run=nginx, as in the docs
kubectl run sh --image=busybox:1.36 -- sh -c 'echo started; sleep 3600'
NIP=$(kubectl get pod nginx -o jsonpath='{.status.podIP}')
kubectl exec sh -- sh -c "for i in 1 2 3; do wget -qO /dev/null http://$NIP/; done"     # some nginx log lines
minikube ssh                                                        # then the commands below with sudo
```

## Lab 1 – Configuration (docs)
```bash
sudo crictl --version              # crictl version v1.35.0
cat /etc/crictl.yaml               # runtime-endpoint: unix:///run/containerd/containerd.sock
sudo crictl --config /nonexistent ps
#   level=warning msg="Config \"/nonexistent\" does not exist, trying next: \"/usr/local/bin/crictl.yaml\""
#   level=fatal msg="load config file: stat /usr/local/bin/crictl.yaml: no such file or directory"
```

## Lab 2 – Pods (docs)
```bash
sudo crictl pods | head -4
#   POD ID         CREATED          STATE      NAME                          NAMESPACE         ATTEMPT   RUNTIME
#   7952a8b78500d  2 seconds ago    Ready      sh                            default           0         (default)
#   30b51addcbe93  2 seconds ago    Ready      nginx                         default           0         (default)
#   b6a90f47b0da2  2 minutes ago    NotReady   prometheus-6bc65bfd44-tqhms   monitoring-demo   0         <- deleted from the API, sandbox not yet GC'd
sudo crictl pods --name nginx          # 30b51addcbe93 … nginx default
sudo crictl pods --label run=nginx     # the same Pod, by the label kubectl run set
```

## Lab 3 – Images (docs)
```bash
sudo crictl images nginx | wc -l       # 94   <- every image: the filter is ignored in v1.35.0
sudo crictl images | grep -E '^docker.io/library/nginx '
#   docker.io/library/nginx   1.14.2   295c7be079025   44.7MB
#   …
#   docker.io/library/nginx   latest   c05939e13a616   63.9MB
sudo crictl images -q | head -2        # sha256:fb8656c965b9… (IDs only)
```

## Lab 4 – Containers, exec, logs (docs)
```bash
sudo crictl ps --name '^(nginx|sh)$'
#   CONTAINER      IMAGE          CREATED        STATE     NAME    ATTEMPT   POD ID         POD     NAMESPACE
#   d2b0c52d2e5e9  c05939e13a616  1 second ago   Running   nginx   0         30b51addcbe93  nginx   default
#   160d2f2a67e41  b116e15507444  2 seconds ago  Running   sh      0         7952a8b78500d  sh      default
C=$(sudo crictl ps --name '^nginx$' -q)
sudo crictl exec $C ls /               # bin boot dev docker-entrypoint.d …
sudo crictl logs --tail=1 $C           # 10.244.0.85 - - [15/Nov/2026:05:59:27 +0000] "GET / HTTP/1.1" 200 896 "-" "Wget" "-"
```

## Lab 5 – Beyond the page (not from the docs)
```bash
sudo crictl stats --label io.kubernetes.pod.namespace=default
#   CONTAINER      NAME   CPU %  MEM       DISK      INODES  SWAP
#   160d2f2a67e41  sh     0.00   376.8kB   36.86kB   12      0B
#   d2b0c52d2e5e9  nginx  0.00   7.791MB   94.21kB   19      0B
sudo crictl inspect -o go-template --template 'pid={{.info.pid}} image={{.status.image.image}} started={{.status.startedAt}}' $C
#   pid=33409 image=docker.io/library/nginx:latest started=2026-11-15T05:59:27.086171097Z     <- the host PID: nsenter -t 33409 …
sudo crictl stop $C; sudo crictl rm $C          # remove it behind the kubelet's back …
sleep 12; sudo crictl ps --name '^nginx$'      # 85dad3a1dc6b4 … Running nginx … POD ID 30b51addcbe93   <- new container, same sandbox
exit
kubectl get pod nginx                          # nginx 1/1 Running RESTARTS 1
```

## Useful commands
```bash
sudo crictl pods --namespace kube-system --state NotReady
sudo crictl ps -a --pod <pod-id>
sudo crictl inspectp <pod-id> | jq '.status.network'
sudo crictl logs --since 5m <container-id>
```

## Cleanup
```bash
./cleanup.sh       # kubectl delete pod nginx sh
```
