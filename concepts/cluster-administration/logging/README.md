# Logging Architecture – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/cluster-administration/logging/

> The docs' 6 manifests are **verbatim**: [counter-pod.yaml](counter-pod.yaml), [counter-pod-err.yaml](counter-pod-err.yaml), [two-files-counter-pod.yaml](two-files-counter-pod.yaml), [two-files-counter-pod-streaming-sidecar.yaml](two-files-counter-pod-streaming-sidecar.yaml), [fluentd-sidecar-config.yaml](fluentd-sidecar-config.yaml), [two-files-counter-pod-agent-sidecar.yaml](two-files-counter-pod-agent-sidecar.yaml). Three of them are all named `counter`, so they run in separate namespaces: `log-basic`, `log-stream`, `log-agent`.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Container logs** | Whatever a container writes to **stdout/stderr**. The runtime stores it in files on the node (`/var/log/pods/<ns>_<pod>_<uid>/<container>/N.log`, symlinked from `/var/log/containers`) in CRI format: `timestamp stream P/F message`. |
| **kubectl logs** | The kubelet serves those files. `--previous` for the last crashed instance. Logs are **gone when the Pod is deleted**. |
| **Log streams** | Reading stdout and stderr separately (`?stream=Stderr`) needs `PodLogsQuerySplitStreams` (alpha). |
| **Rotation** | The kubelet rotates (`containerLogMaxSize`, default 10Mi; `containerLogMaxFiles`, 5). |
| **System component logs** | journald (kubelet, runtime) or files/stdout (static control-plane Pods). See `../system-logs`. |
| **Cluster-level logging** (not built in) | **Node agent** DaemonSet (most common), **streaming sidecar** (the sidecar tails a file to its own stdout), **agent sidecar** (a full agent per Pod: costly), or the app ships logs itself. |

---

## Lab 1 – Basic logs (docs counter)
```bash
cd concepts/cluster-administration/logging
for n in log-basic log-stream log-agent; do kubectl create ns $n; done
kubectl apply -n log-basic -f counter-pod.yaml -f counter-pod-err.yaml
kubectl logs counter -n log-basic --tail=2          # 3: Thu Nov 12 07:53:49 UTC 2026 ...
kubectl get --raw "/api/v1/namespaces/log-basic/pods/counter-err/log?stream=Stderr"
#   The PodLogOptions "counter-err" is invalid: stream: Forbidden: may not be specified    <- PodLogsQuerySplitStreams is alpha, off
```

## Lab 2 – Where the logs live on the node
```bash
U=$(kubectl get pod counter-err -n log-basic -o jsonpath='{.metadata.uid}')
minikube ssh -- "sudo tail -2 /var/log/pods/log-basic_counter-err_$U/count/0.log"
#   2026-11-12T07:53:58.401693112Z stderr F 12: err
#   2026-11-12T07:53:58.401768344Z stdout F 12: Thu Nov 12 07:53:58 UTC 2026        <- both streams, one file, tagged
minikube ssh -- "ls /var/log/containers | grep counter"      # counter_log-basic_count-<id>.log -> /var/log/pods/...
kubectl get --raw /api/v1/nodes/minikube/proxy/configz | jq -c '.kubeletconfig | {containerLogMaxSize, containerLogMaxFiles}'
#   {"containerLogMaxSize":"10Mi","containerLogMaxFiles":5}
```
A node agent (DaemonSet) tails exactly these files. The stream tag is how it tells stdout from stderr.

## Lab 3 – Streaming sidecars (docs)
```bash
kubectl apply -n log-stream -f two-files-counter-pod-streaming-sidecar.yaml
kubectl logs counter -n log-stream count-log-1 --tail=1     # 5: Thu Nov 12 07:53:51 UTC 2026
kubectl logs counter -n log-stream count-log-2 --tail=1     # Thu Nov 12 07:53:51 UTC 2026 INFO 5
```
The app writes two files ([two-files-counter-pod.yaml](two-files-counter-pod.yaml) alone wouldn't show anything in `kubectl logs`). Two tiny sidecars `tail -F` them to their own stdout, so each format becomes a separate, collectable stream.

## Lab 4 – Agent sidecar (docs fluentd)
```bash
kubectl apply -n log-agent -f fluentd-sidecar-config.yaml -f two-files-counter-pod-agent-sidecar.yaml
kubectl get pod counter -n log-agent                         # 2/2 Running
kubectl logs counter -n log-agent -c count-agent --tail=1
#   [info]: adding match pattern="**" type="google_cloud"     <- and nothing after that
```
The 2017-era `fluentd-gcp:1.30` image starts, but its only output is **Google Cloud Logging**, which needs GCP metadata/credentials, so it never ships anything here. That's also why the page calls this pattern resource-heavy and logs from it invisible to `kubectl logs`.

---

## Useful commands
```bash
kubectl logs <pod> [-c container] [--previous] [--since=10m] [--timestamps] [-f]
kubectl logs -l app=x --all-containers --prefix
minikube ssh -- sudo ls /var/log/pods
```

## Cleanup
```bash
./cleanup.sh
```
