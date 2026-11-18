# Communicate Between Containers in the Same Pod Using a Shared Volume – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/access-application-cluster/communicate-containers-same-pod-shared-volume/

> Runs on the default **minikube** cluster, `default` namespace. Files: [two-container-pod.yaml](two-container-pod.yaml) (docs, **verbatim**),
> [two-container-pod-init.yaml](two-container-pod-init.yaml) (not from the docs).
>
> **Found:**
> 1. The docs' Pod stays **`1/2 NotReady`** forever: a regular container that exits (debian) makes the Pod unready, so a Service would never
>    send it traffic. Use an init container (or a native sidecar) for one-shot helpers (Lab 2).
> 2. The sample YAML shows `containerStatuses` under `spec:` and the debian container in `lastState`. Really it is under `status:`, with
>    `state.terminated` (`restartPolicy: Never`, so there is no "last" state).
> 3. Current `nginx` images already contain `curl`, but not `ps` (`exec: "ps": executable file not found`). The docs' `apt-get install procps` is still needed for that.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| `emptyDir` | created empty when the Pod starts, shared by all containers that mount it, **deleted with the Pod** |
| Mount paths | each container chooses its own (`/pod-data` vs `/usr/share/nginx/html`), same files |
| Other channel | containers also share the network namespace (`localhost`) |

---

## Lab 1 – The docs' Pod
```bash
cd tasks/access-application-cluster/communicate-containers-same-pod-shared-volume
kubectl apply -f two-container-pod.yaml
kubectl get pod two-containers                     # two-containers   1/2   NotReady   0   4s   … stays so
kubectl get pod two-containers --output=yaml       # status.containerStatuses:
#   - image: docker.io/library/debian:latest     name: debian-container   state: terminated: exitCode: 0  reason: Completed
#   - image: docker.io/library/nginx:latest      name: nginx-container    state: running
kubectl exec -it two-containers -c nginx-container -- /bin/bash
  curl localhost                                   # Hello from the debian container
  ps aux                                           # bash: ps: command not found  → apt-get update && apt-get install procps
  cat /proc/1/cmdline | tr '\0' ' '                # nginx: master process nginx -g daemon off;
  exit
```

## Lab 2 – Init container + live sidecar (not from the docs)
```bash
kubectl apply -f two-container-pod-init.yaml
kubectl get pod two-containers-init                # 2/2   Running   <- Ready (nginx + the "clock" sidecar)
kubectl exec two-containers-init -c nginx-container -- sh -c 'curl -s localhost; curl -s localhost/time.txt; sleep 2; curl -s localhost/time.txt'
#   Hello from the debian init container
#   12:12:32
#   12:12:34                                       <- the sidecar keeps writing, nginx serves the new content
```

## Lab 3 – The volume lives only as long as the Pod (docs "Discussion")
```bash
kubectl exec two-containers -c nginx-container -- sh -c 'echo extra > /usr/share/nginx/html/extra.txt; ls /usr/share/nginx/html'
#   extra.txt  index.html
kubectl delete pod two-containers && kubectl apply -f two-container-pod.yaml
kubectl exec two-containers -c nginx-container -- ls /usr/share/nginx/html
#   index.html                                     <- new emptyDir; only what debian writes again
```

## Cleanup
```bash
./cleanup.sh
```
