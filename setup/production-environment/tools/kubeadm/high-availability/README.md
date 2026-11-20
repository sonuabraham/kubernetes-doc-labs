# Creating Highly Available Clusters with kubeadm – Hands-on Lab

Based on: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/high-availability/

> A real **stacked-etcd** HA control plane: **cp1, cp2, cp3** from [../machines.sh](../machines.sh) (kubeadm v1.37.2) behind an **HAProxy**
> load balancer container `k8s-api-lb` ([lb.sh](lb.sh), [haproxy.cfg](haproxy.cfg)). The LB is NOT from the docs; the page says "the
> following example is only one option". [kubeadm-ha-config.yaml](kubeadm-ha-config.yaml) is the page's
> `kubeadm init --control-plane-endpoint "LOAD_BALANCER_DNS:LOAD_BALANCER_PORT" --upload-certs` as a config (endpoint `k8s-api-lb:6443`,
> Pod CIDR for kindnet, swap tolerated).
> cp2 joins with the **uploaded certificates** (`--certificate-key`); cp3 with the page's **manual certificate distribution**
> (`docker cp` instead of `scp`, the page's move script verbatim with `USER=ubuntu`).
>
> **Limits of this host:** 3 control-plane kubelets plus an idle 4th machine exhausted the host's inotify instances (128). cp3's kubelet
> logged `Failed to start cAdvisor: inotify_init: too many open files` and its etcd never started. So the worker machine is stopped
> during this lab, and the "Install workers" step is the same `kubeadm join` as in [../create-cluster-kubeadm](../create-cluster-kubeadm/).
> The external-etcd half of the page is in [../setup-ha-etcd-with-kubeadm](../setup-ha-etcd-with-kubeadm/).
>
> **Found:**
> - **"A connection refused error is expected"** (`nc -zv -w 2 <LOAD_BALANCER_IP> <PORT>` before init) is true only for packet-forwarding LBs.
>   A proxy LB like HAProxy accepts the connection itself: `Connection to k8s-api-lb (172.30.0.6) 6443 port [tcp/*] succeeded!` while its
>   log says `backend 'control-plane' has no server available!`. Check the LB's own health view.
> - **The page's health check advice ("a TCP check on the port the kube-apiserver listens on") misses a hung API server.** With cp1
>   frozen (`docker pause`), the TCP check kept passing (the kernel still completes the handshake). HAProxy never marked cp1 down, and
>   requests that landed on cp1 timed out (`Unable to connect to the server: context deadline exceeded`). An **HTTPS check on `/readyz`**
>   ([haproxy-readyz.cfg](haproxy-readyz.cfg)) marked cp1 DOWN after 6 s (`Layer6 timeout`); then 10/10 requests through the LB succeeded.
> - **A failed control-plane join leaves a stale etcd learner** that `kubeadm reset` doesn't remove (`[reset] No kubeadm config, using
>   etcd pod spec …`). The member list kept `6331ff3737c218aa, unstarted, …, https://172.30.0.5:2380, …, true`. It had to be removed with
>   `etcdctl member remove`; the retried join then took 4 s.
> - The page's CoreDNS note is right: both CoreDNS Pods ran on cp1 after the joins. `kubectl -n kube-system rollout restart deployment coredns`
>   moved them, but only onto nodes that were Ready at that moment (both to cp2 here; cp3 was still NotReady). Repeat once all nodes are Ready.
> - The "deleted in two hours" behaviour is implemented with an owner reference: `kubeadm-certs` is owned by a short-lived bootstrap token
>   (`Secret/bootstrap-token-…`, `kubeadm token list` → TTL 1h at the time, description "Proxy for managing TTL for the kubeadm-certs
>   secret"). When the token expires, garbage collection deletes the certificates.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| Stacked etcd | each control-plane node runs an etcd member; 3 nodes → quorum survives 1 failure |
| `controlPlaneEndpoint` = LB | everything (kubelets, admin.conf, joins) talks to the LB name, never to one node |
| `--upload-certs` | the shared CAs + SA key go encrypted into the `kubeadm-certs` Secret; `--certificate-key` decrypts them on join (2 h) |
| Manual distribution | copy **only** ca.crt/key, sa.key/pub, front-proxy-ca.crt/key, etcd/ca.crt/key; kubeadm makes the rest with node-specific SANs |
| `kubeadm join --control-plane` | new apiserver/controller-manager/scheduler + a new etcd member (added as learner, then promoted) |
| LB health check | decides failover; must detect a *hung* apiserver, not only a closed port |

## Lab 1 – Load balancer
```bash
cd setup/production-environment/tools/kubeadm
minikube stop; docker stop kadm-w1        # (inotify – see above)
./machines.sh up cp1 cp2 cp3              # + prepare-runtime.sh and install-kubeadm/install-debian.sh on each
high-availability/lb.sh up                # k8s-api-lb: 172.30.0.6
high-availability/lb.sh log               # cp1/cp2/cp3 DOWN … backend 'control-plane' has no server available!
./machines.sh x cp1 'nc -zv -w 2 k8s-api-lb 6443'      # … succeeded!   (not "connection refused", see Found)
```

## Lab 2 – First control plane node
```bash
docker cp high-availability/kubeadm-ha-config.yaml kadm-cp1:/root/
./machines.sh x cp1 'kubeadm init --config kubeadm-ha-config.yaml --upload-certs'
#   [upload-certs] Storing the certificates in Secret "kubeadm-certs" in the "kube-system" Namespace
#   [upload-certs] Using certificate key: <64 hex chars>
#   … kubeadm join k8s-api-lb:6443 --token … --discovery-token-ca-cert-hash sha256:… --control-plane --certificate-key …
#   Please note that the certificate-key gives access to cluster sensitive data, keep it secret!
#   As a safeguard, uploaded-certs will be deleted in two hours; …
docker cp kindnet.yaml kadm-cp1:/root/; ./machines.sh x cp1 'KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f kindnet.yaml'
./machines.sh x cp1 'KUBECONFIG=/etc/kubernetes/admin.conf kubectl -n kube-system get secret kubeadm-certs -o jsonpath="{.data}"'
#   keys: ca.crt ca.key etcd-ca.crt etcd-ca.key front-proxy-ca.crt front-proxy-ca.key sa.key sa.pub   (encrypted)
```

## Lab 3 – More control plane nodes
cp2, with the uploaded certificates:
```bash
./machines.sh x cp2 'kubeadm join k8s-api-lb:6443 --token … --discovery-token-ca-cert-hash sha256:… --control-plane --certificate-key … --ignore-preflight-errors=Swap'
#   [download-certs] Downloading the certificates in Secret "kubeadm-certs" …
#   [certs] etcd/server serving cert is signed for DNS names [cp2 localhost] and IPs [172.30.0.4 127.0.0.1 ::1]
#   [etcd] Announced new etcd member joining to the existing etcd cluster
#   [etcd] Waiting for the new etcd member to join the cluster. This can take up to 40s    (a few transient etcd-client warnings)
#   This node has joined the cluster and a new control plane instance was created    (59 s incl. image pulls)
```
cp3, manual certificate distribution (the page's scripts; `docker cp kadm-cp1:/etc/kubernetes/pki/<f> …; docker cp … kadm-cp3:/home/ubuntu/`):
```bash
#   copied: ca.crt ca.key sa.key sa.pub front-proxy-ca.crt front-proxy-ca.key etcd-ca.crt etcd-ca.key  → /home/ubuntu on cp3
./machines.sh x cp3 'USER=ubuntu; mkdir -p /etc/kubernetes/pki/etcd; mv /home/${USER}/ca.crt /etc/kubernetes/pki/ …'   # the page's script
./machines.sh x cp3 'kubeadm join k8s-api-lb:6443 --token … --discovery-token-ca-cert-hash sha256:… --control-plane --ignore-preflight-errors=Swap'
#   (first attempt: inotify exhaustion → "the etcd member 6331ff3737c218aa is not started" → reset, etcdctl member remove, retry)
#   This node has joined the cluster and a new control plane instance was created
etcdctl … member list
#   681ebdf2f082af14, started, cp3, https://172.30.0.5:2380 …
#   96814601d762728f, started, cp2, https://172.30.0.4:2380 …
#   e942f75ad6f00855, started, cp1, https://172.30.0.2:2380 …
kubectl -n kube-system rollout restart deployment coredns           # CoreDNS off cp1
grep server: /etc/kubernetes/admin.conf                              # https://k8s-api-lb:6443
```
Re-upload / key commands from the page:
```bash
kubeadm certs certificate-key                         # deabf9d9877a862abc16…   (32-byte AES key, hex)
kubeadm init phase upload-certs --upload-certs        # [upload-certs] … Using certificate key: <new key>
kubectl -n kube-system get secret kubeadm-certs -o jsonpath='{.metadata.ownerReferences[0].kind}/{.metadata.ownerReferences[0].name}'
#   Secret/bootstrap-token-gochh6       (kubeadm token list: TTL 1h, "Proxy for managing TTL for the kubeadm-certs secret")
```

## Lab 4 – Failover (NOT from the docs)
```bash
docker pause kadm-cp1                     # freeze the whole node
# TCP health check (haproxy.cfg): cp1 never marked DOWN
kubectl --request-timeout=5s get --raw /readyz      # sometimes ok, sometimes "context deadline exceeded" (round-robin onto cp1)
kubectl create configmap written-during-failover --from-literal=k=v      # works (etcd quorum 2/3)
docker unpause kadm-cp1                   # cp1 later reads the ConfigMap: {"k":"v"}

# HTTPS /readyz health check (haproxy-readyz.cfg)
docker pause kadm-cp1
#   +6 s: Server control-plane/cp1 is DOWN, reason: Layer6 timeout …
#   10 requests via the LB: ok=10 failed=0
docker unpause kadm-cp1                   # Server control-plane/cp1 is UP, reason: Layer7 check passed, code: 200
```

## Cleanup
```bash
for m in cp3 cp2 cp1; do ./machines.sh x $m 'kubeadm reset -f'; done
high-availability/lb.sh down
# all lab machines: ./machines.sh down ; minikube start
```
