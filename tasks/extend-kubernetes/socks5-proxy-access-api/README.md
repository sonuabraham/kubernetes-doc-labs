# Use a SOCKS5 Proxy to Access the Kubernetes API – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/extend-kubernetes/socks5-proxy-access-api/

> Runs against the default **minikube** cluster. The **minikube node plays the remote server / SSH bastion**: SSH as `docker` with
> minikube's key on the port Docker publishes for the node's sshd. Files (not from the docs): [start-tunnel.sh](start-tunnel.sh)
> (= the docs' `ssh -D 1080 -q -N user@host`), [make-kubeconfig.sh](make-kubeconfig.sh) (a kubeconfig with the docs' `proxy-url` field).
> Generated files (`tunnel.pid`, `kubeconfig-socks5`) are gitignored.
>
> To show traffic really goes through the bastion, the lab uses server names that **only the node can resolve or reach**:
> `https://localhost:8443` (the API server on the node's loopback) and `https://control-plane.minikube.internal:8443` (only in the node's `/etc/hosts`).
>
> **Found (kubectl v1.35):**
> 1. `proxy-url: socks5h://…` in a kubeconfig is **rejected**: `unsupported scheme "socks5h", must be http, https, or socks5`.
> 2. `socks5h` isn't needed with kubectl anyway: with plain `socks5://`, Go's SOCKS dialer sends the **host name** to the proxy, so the
>    bastion resolves it (no DNS leak), the same as `socks5h` via `HTTPS_PROXY`.
> 3. The docs' "`https://localhost:6443` refers to localhost on the proxy server" holds for `proxy-url`, but **not** for `HTTPS_PROXY`:
>    Go never proxies requests to `localhost`/`127.0.0.1` from the environment variable, so they go to your own machine.
> 4. With the tunnel down, the error names the **API server** (`The connection to the server 192.168.58.2:8443 was refused`), although it's
>    the proxy port that refused.

## Key ideas (read first)

| Piece | Meaning |
|---|---|
| `ssh -D 1080 -N` | SSH client opens a SOCKS5 listener on `localhost:1080`; connections leave from the remote host |
| `HTTPS_PROXY=socks5://localhost:1080` | every kubectl context (and curl…) goes through it |
| `proxy-url` in a `cluster` entry | only that context uses it |
| `exec`, `port-forward`, `logs -f` | work over SOCKS since kubectl 1.24 |

---

## Lab 1 – Tunnel and env var (docs)
```bash
cd tasks/extend-kubernetes/socks5-proxy-access-api
./start-tunnel.sh                         # SOCKS5 proxy on localhost:1080
HTTPS_PROXY=socks5://localhost:1080 kubectl get pods -n kube-system -l k8s-app=kube-dns
#   coredns-559f6c778d-fsjkx   1/1   Running   …
```

## Lab 2 – Prove it goes through the bastion (not from the docs)
```bash
getent hosts control-plane.minikube.internal           # (nothing on your machine)
minikube ssh -- getent hosts control-plane.minikube.internal     # 192.168.58.2  control-plane.minikube.internal
S=--server=https://control-plane.minikube.internal:8443
kubectl $S get ns default
#   Unable to connect to the server: dial tcp: lookup control-plane.minikube.internal on 127.0.0.53:53: no such host
HTTPS_PROXY=socks5://localhost:1080  kubectl $S get ns default     # default   Active   <- resolved on the bastion
HTTPS_PROXY=socks5h://localhost:1080 kubectl $S get ns default     # default   Active   (same: Found #2)
HTTPS_PROXY=socks5://localhost:1080 kubectl --server=https://localhost:8443 get ns default
#   The connection to the server localhost:8443 was refused …        <- localhost is never proxied via HTTPS_PROXY (Found #3)
```

## Lab 3 – `proxy-url` in kubeconfig (docs)
```bash
./make-kubeconfig.sh
#   proxy-url: socks5://localhost:1080
#   server: https://localhost:8443           <- localhost OF THE NODE
kubectl --kubeconfig kubeconfig-socks5 get pods -A | head -3              # works: proxy-url does proxy localhost
kubectl --kubeconfig kubeconfig-socks5 -n kube-system exec etcd-minikube -- etcd --version     # etcd Version: 3.7.0   (exec over SOCKS)
# same file without proxy-url:   The connection to the server localhost:8443 was refused
# with proxy-url socks5h://…:    error: invalid 'proxy-url' "socks5h://localhost:1080" for cluster "minikube": unsupported scheme "socks5h", must be http, https, or socks5
kill $(cat tunnel.pid)
HTTPS_PROXY=socks5://localhost:1080 kubectl get ns default
#   The connection to the server 192.168.58.2:8443 was refused …     <- really the proxy (Found #4)
```

## Cleanup
```bash
./cleanup.sh
unset https_proxy HTTPS_PROXY
```
