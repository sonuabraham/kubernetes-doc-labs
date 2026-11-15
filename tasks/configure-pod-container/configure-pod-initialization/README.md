# Configure Pod Initialization – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-initialization/

> Runs on the default **minikube** cluster, in the `default` namespace as in the docs (needs internet access for `info.cern.ch`).
> Files: [init-containers.yaml](init-containers.yaml) (docs, **verbatim**). Not from the docs: [init-order-and-failure.yaml](init-order-and-failure.yaml).
> Concepts: [concepts/workloads/pods/init-containers](../../../concepts/workloads/pods/init-containers/).

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **Init container** | Runs **to completion before** any app container starts. Several run strictly **one after another**. |
| **Shared volume** | The usual hand-off: the init container writes into an `emptyDir`, and the app reads it. |
| **Failure** | Non-zero exit means it is retried (with `restartPolicy: Always`, with back-off). The app containers never start: `Init:Error` / `Init:CrashLoopBackOff`. |
| **`dnsPolicy: Default`** | The docs' Pod uses the **node's** resolver (`/etc/resolv.conf` of the node), not CoreDNS. Fine for fetching an internet URL, but cluster Service names won't resolve. |

```
init-demo:  [install: wget info.cern.ch → /work-dir/index.html] ──exit 0──► [nginx: serves /usr/share/nginx/html]
                             └────────────── emptyDir "workdir" ───────────────┘
```

---

## Step 0
```bash
cd tasks/configure-pod-container/configure-pod-initialization
```

## Lab 1 – The docs' Pod
```bash
kubectl apply -f init-containers.yaml
kubectl get pod init-demo           # Init:0/1, then a few seconds later:
#   init-demo   1/1   Running   0   5s
kubectl logs init-demo -c install | tail -1
#   index.html   100% |*******************************|   646   0:00:00 ETA
kubectl exec init-demo -- sh -c 'head -c 300 /usr/share/nginx/html/index.html'
```
```html
<html><head></head><body><header>
<title>http://info.cern.ch</title>
</header>
<h1>http://info.cern.ch - home of the first website</h1>
…
```
The docs' `apt-get install curl; curl localhost` inside the container shows the same page. Reading the file is enough to prove the hand-off.

## Lab 2 – `dnsPolicy: Default` vs the default `ClusterFirst`
```bash
kubectl exec init-demo -- cat /etc/resolv.conf
#   nameserver 192.168.58.1                <- the minikube node's resolver (docker network gateway)
#   options edns0 trust-ad ndots:0
kubectl apply -f init-order-and-failure.yaml
kubectl exec init-order -- cat /etc/resolv.conf
#   search default.svc.cluster.local svc.cluster.local cluster.local
#   nameserver 10.96.0.10                  <- CoreDNS
#   options ndots:5
```

## Lab 3 – Ordering and failure (not from the docs)
```bash
sleep 30; kubectl get pod init-order init-fail
#   init-order   1/1   Running      0
#   init-fail    0/1   Init:Error   2 (29s ago)       <- alternates with Init:CrashLoopBackOff
kubectl logs init-order
#   first  04:26:46
#   second 04:26:50      <- only after "first" finished (3 s sleep)
#   app    04:26:54      <- only after all init containers
kubectl logs init-fail -c check-db
#   waiting for db... giving up
kubectl get pod init-fail -o json | jq -c '{init:.status.initContainerStatuses[0].restartCount, app:.status.containerStatuses[0].state}'
#   {"init":2,"app":{"waiting":{"reason":"PodInitializing"}}}
```
For debugging this, see [debug-init-containers](../../debug/debug-application/debug-init-containers/).

## Useful commands
```bash
kubectl get pod <p> -o jsonpath='{range .status.initContainerStatuses[*]}{.name}{" "}{.state}{"\n"}{end}'
kubectl logs <p> -c <init-container-name> [--previous]
```

## Cleanup
```bash
./cleanup.sh
```
