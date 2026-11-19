# Configuring Redis using a ConfigMap – Hands-on Lab

Based on: https://kubernetes.io/docs/tutorials/configuration/configure-redis-using-configmap/

> Runs on the default **minikube**, namespace `default`.
> - [redis-pod.yaml](redis-pod.yaml) and [example-redis-config.yaml](example-redis-config.yaml) are the docs examples `pods/config/…` **verbatim**.
> - [example-redis-config-empty.yaml](example-redis-config-empty.yaml) is the docs' `cat <<EOF >./example-redis-config.yaml` heredoc, saved
>   under another name.
>
> **Found:**
> - The page writes the empty ConfigMap to `./example-redis-config.yaml` and later runs `kubectl apply -f example-redis-config.yaml` again
>   for the *filled* one. That only works if you first replace the file with the code sample. If you don't, you re-apply the empty
>   config. This lab uses two file names for that reason.
> - Image `redis:8.0.2` (`Redis server v=8.0.2`).
> - (NOT from the docs) The **file** `/redis-master/redis.conf` in the running Pod *did* update, **90 s** after the apply (kubelet sync).
>   `CONFIG GET maxmemory` still said `0`. Redis reads its config file only at startup, so "the Pod needs to be restarted" means the
>   *process* has to re-read the file, not that the volume is stale.
>
> **Note:** the page uses interactive `kubectl exec -it pod/redis -- redis-cli` and then types `CONFIG GET …`. Below, the same commands
> are passed as arguments (`redis-cli CONFIG GET maxmemory`), which prints the reply without the `1)`/`2)` numbering.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| `configMap.items[].key/path` | exposes only the `redis-config` key, as the file `redis.conf` |
| `command: redis-server /redis-master/redis.conf` | Redis loads that file once, at startup |
| ConfigMap update | volume file refreshed after kubelet sync (~1–1.5 min); the running Redis ignores it |
| Pod restart | a bare Pod has no controller: `delete` + `apply` again → new process reads the new file |

## Lab
```bash
kubectl apply -f example-redis-config-empty.yaml    # configmap/example-redis-config created   (redis-config: "")
kubectl apply -f redis-pod.yaml                     # pod/redis created
kubectl get pod/redis configmap/example-redis-config
#   pod/redis   1/1   Running   0   15s
#   configmap/example-redis-config   1   15s
kubectl describe configmap/example-redis-config     # redis-config:  (empty)
kubectl exec -it pod/redis -- redis-cli
  127.0.0.1:6379> CONFIG GET maxmemory              # 1) "maxmemory"         2) "0"
  127.0.0.1:6379> CONFIG GET maxmemory-policy       # 1) "maxmemory-policy"  2) "noeviction"

kubectl apply -f example-redis-config.yaml          # configmap/example-redis-config configured
kubectl describe configmap/example-redis-config
#   redis-config:
#   ----
#   maxmemory 2mb
#   maxmemory-policy allkeys-lru
kubectl exec -it pod/redis -- redis-cli
  127.0.0.1:6379> CONFIG GET maxmemory              # "0"           <- unchanged
  127.0.0.1:6379> CONFIG GET maxmemory-policy       # "noeviction"  <- unchanged

# NOT from the docs: after ~90 s the file in the Pod is new, Redis still isn't
kubectl exec pod/redis -- cat /redis-master/redis.conf     # maxmemory 2mb / maxmemory-policy allkeys-lru
kubectl exec pod/redis -- redis-cli CONFIG GET maxmemory   # 0

kubectl delete pod redis
kubectl apply -f redis-pod.yaml
kubectl exec -it pod/redis -- redis-cli
  127.0.0.1:6379> CONFIG GET maxmemory              # 1) "maxmemory"         2) "2097152"    (2 MiB)
  127.0.0.1:6379> CONFIG GET maxmemory-policy       # 1) "maxmemory-policy"  2) "allkeys-lru"
```

## Cleanup
```bash
kubectl delete pod/redis configmap/example-redis-config     # or ./cleanup.sh
```
