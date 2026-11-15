# Developing and debugging services locally using telepresence – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/debug/debug-cluster/local-debugging/

> **Telepresence itself isn't used here.** `telepresence connect` needs a root daemon (it creates a TUN device, so sudo), and
> `intercept` needs its in-cluster traffic manager installed from a third-party chart. Neither is done on this machine.
> Instead, the lab rebuilds the **two ideas the page explains** with plain Kubernetes on minikube, so you can see what such a tool does:
> - **connect**: your laptop reaches cluster Services and their config.
> - **intercept**: cluster traffic for a Service goes to a process on your laptop, and edits take effect immediately.
>
> Files (not from the docs): [app.yaml](app.yaml) (the "remote" app + a caller), [local_app.py](local_app.py) (the service under development,
> on your machine), [intercept.sh](intercept.sh).
> With Telepresence installed, the docs' equivalents are `telepresence connect` and `telepresence intercept hello --port 18765:80`.

## Key ideas (read first)

| Telepresence | What it does | DIY version here |
|---|---|---|
| `telepresence connect` | a VPN-like daemon: cluster DNS names and IPs reachable from the laptop | `kubectl port-forward svc/…` (one Service at a time, no cluster DNS) |
| `telepresence intercept SVC --port L:R` | a traffic-agent **sidecar** in the Pod sends (all, or only "personal") traffic through a tunnel to `localhost:L` | the Service's endpoints swapped to `<laptop>:L` via a manual **EndpointSlice** (all traffic) |
| access to ConfigMaps/Secrets | the agent exports the Pod's env and volumes | `kubectl get cm -o json \| jq …` into an env file |

```
            frontend Pod ──► Service hello ──► EndpointSlice ──► Pods hello (cluster-v1)
   intercept on:                               EndpointSlice ──► 192.168.58.1:18765 = local_app.py on the laptop
```

---

## Step 0
```bash
cd tasks/debug/debug-cluster/local-debugging
kubectl apply -f app.yaml
kubectl logs -n tp-demo frontend -f          # in another terminal: one line every 2 s
#   09:41:57 hello from cluster-v1 on hello-655dfdbbb6-n4zmg
python3 local_app.py & echo $! > .local_app.pid        # the local service (port 18765; 8000 was already taken on this host)
```
Pods can reach your laptop on the minikube docker network: from a Pod, `wget 192.168.58.1:18765` gives
`hello from local-dev-1 on sonu-thinkPad-t14-gen-7 (request from 192.168.58.2)`. The node SNATs Pod traffic to its own IP.

## Lab 1 – "connect": use the cluster from the laptop
```bash
kubectl -n tp-demo port-forward svc/hello 18080:80 &
curl -s localhost:18080                       # hello from cluster-v1 on hello-…
getent hosts hello.tp-demo.svc.cluster.local  # (nothing)  <- cluster DNS isn't available locally; telepresence connect adds that
kubectl -n tp-demo get configmap hello-config -o json | jq -r '.data|to_entries[]|"\(.key)=\(.value)"' > hello.env
cat hello.env                                 # DB_HOST=db.tp-demo.svc.cluster.local  GREETING=hello
kill %1
```

## Lab 2 – "intercept": cluster traffic to your laptop
```bash
./intercept.sh on
#   NAME              ADDRESSTYPE   PORTS   ENDPOINTS
#   hello-intercept   IPv4          18765   192.168.58.1
kubectl logs -n tp-demo frontend --tail=3
#   09:43:05 hello from local-dev-2 on sonu-thinkPad-t14-gen-7 (request from 192.168.58.2)     <- every request, from your machine
```
Now "edit the code and save": restart the local process with a change, and the cluster sees it at once:
```bash
kill $(cat .local_app.pid); VERSION=local-dev-2 python3 local_app.py & echo $! > .local_app.pid
kubectl logs -n tp-demo frontend --tail=1    # … hello from local-dev-2 …
./intercept.sh off
kubectl logs -n tp-demo frontend --tail=1    # … hello from cluster-v1 …
```
Run `local_app.py` under a debugger (`python3 -m pdb local_app.py`, or your IDE) and breakpoints are hit by **cluster** requests.

### What went wrong in the first version (worth knowing)
The first `intercept.sh` only removed the Service selector and added the manual slice. Traffic was then **split** between laptop and Pods:
```bash
kubectl -n tp-demo get endpointslices -l kubernetes.io/service-name=hello -o jsonpath='{range .items[*]}{.metadata.name}({.metadata.labels.endpointslice\.kubernetes\.io/managed-by}) {end}'
#   hello-k484s(endpointslicemirroring-controller.k8s.io) hello-s2fgl(endpointslice-controller.k8s.io)     <- 10 s after removing the selector
```
Without a selector, the endpointslice controller leaves its last slice behind. The old (deprecated) `Endpoints` object also stays, and
the **mirroring** controller copies it into another slice. The script now deletes both before adding its own slice.
`./intercept.sh off` restores the selector, and the controllers rebuild everything.

## Useful commands
```bash
kubectl get endpointslices -n tp-demo -l kubernetes.io/service-name=hello -o wide
minikube ip                                      # the node; the laptop is .1 on the same network
```

## Cleanup
```bash
./cleanup.sh       # stops local_app.py (.local_app.pid) and deletes namespace tp-demo
rm -f hello.env
```
