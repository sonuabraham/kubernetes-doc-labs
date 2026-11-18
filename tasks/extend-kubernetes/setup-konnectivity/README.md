# Set up Konnectivity service – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/extend-kubernetes/setup-konnectivity/

> Changes kube-apiserver, so it runs on a **throwaway profile `konn-lab`** (single node; the docs recommend two workers, but a second
> profile node exhausts this host's inotify limit). [konn-lab.sh](konn-lab.sh) `start` stops the default minikube first; `delete` brings it back.
> Files (docs, **verbatim**): [egress-selector-configuration.yaml](egress-selector-configuration.yaml), [konnectivity-server.yaml](konnectivity-server.yaml),
> [konnectivity-agent.yaml](konnectivity-agent.yaml), [konnectivity-rbac.yaml](konnectivity-rbac.yaml). Adapted (one change each, marked):
> [konnectivity-server-minikube.yaml](konnectivity-server-minikube.yaml) (certs hostPath `/var/lib/minikube/certs`),
> [konnectivity-agent-minikube.yaml](konnectivity-agent-minikube.yaml) (`--proxy-server-host` = node IP instead of `35.225.206.7`).
>
> **Found:**
> 1. `SERVER=$(kubectl config view -o jsonpath='{.clusters..server}')` returns **every** cluster in your kubeconfig
>    (`https://192.168.202.2:8443 https://192.168.49.2:8443` here), which gives a broken konnectivity-server kubeconfig. Add `--minify`.
> 2. With the agents gone, you can't read the konnectivity-server's own logs with kubectl either (logs go through the tunnel). Use
>    `crictl logs` on the node.
> 3. The v0.0.37 images still pull (from both `registry.k8s.io` and `us.gcr.io/k8s-artifacts-prod`), but they are old; check the
>    apiserver-network-proxy releases for current ones.

## Key ideas (read first)

| Piece | Role |
|---|---|
| EgressSelectorConfiguration `name: cluster` | traffic from kube-apiserver **to the cluster** (kubelets, Pods, Services, webhooks) goes through the proxy |
| `proxyProtocol: GRPC`, `transport: uds` | API server ↔ konnectivity-server over a Unix socket on the control-plane node |
| konnectivity-server | static Pod, hostNetwork; agents connect to it on `:8132`; authenticates agents by SA token with audience `system:konnectivity-server` |
| konnectivity-agent | DaemonSet; keeps an outbound tunnel open and dials targets **from inside** the node network |
| Why | control plane needs no inbound route to the nodes (e.g. managed control planes) |

---

## Lab 1 – Configure (docs steps)
```bash
cd tasks/extend-kubernetes/setup-konnectivity
./konn-lab.sh start
./konn-lab.sh configure
#   ## kubeconfig for konnectivity-server   User "system:konnectivity-server" set. … Context "system:konnectivity-server@kubernetes" created.
#   ## RBAC + konnectivity server (static Pod) first …   clusterrolebinding…/system:konnectivity-server created, serviceaccount/konnectivity-agent created
#   ## kube-apiserver: --egress-selector-config-file + konnectivity-uds volume
#   "--egress-selector-config-file=/etc/kubernetes/konnectivity-server/egress-selector-configuration.yaml"
#   ## agents   daemonset.apps/konnectivity-agent created
K="kubectl --context konn-lab"
$K -n kube-system logs konnectivity-server-konn-lab | grep -E 'Agent connected|DIAL_REQ' | head -2
#   "Agent connected" agentID="a370df9b-…"
#   "Received DIAL_REQ" dialID=… dialAddress="192.168.202.2:10250"           <- apiserver -> kubelet, through the tunnel
```

## Lab 2 – What goes through the tunnel (not from the docs)
```bash
$K run web --image=nginx:1.27
$K logs web; $K exec web -- nginx -v                     # kubelet :10250
$K get --raw "/api/v1/namespaces/default/pods/web:80/proxy/" | grep -o '<title>.*</title>'     # Pod IP :80
$K -n kube-system logs konnectivity-server-konn-lab | grep DIAL_REQ | tail -3 | grep -o 'dialAddress="[^"]*"'
#   dialAddress="192.168.202.2:10250"
#   dialAddress="192.168.202.2:10250"
#   dialAddress="10.244.0.4:80"
$K -n kube-system delete ds konnectivity-agent
$K get pods                                   # web   1/1   Running        <- etcd-backed reads don't need the tunnel
$K logs web                                   # Error from server: Get "https://192.168.202.2:10250/containerLogs/default/web/web…": No agent available
$K exec web -- true                           # Error from server: error dialing backend: No agent available
$K -n kube-system logs konnectivity-server-konn-lab        # same error (Found #2)
minikube -p konn-lab ssh -- 'sudo crictl logs $(sudo crictl ps -q --name konnectivity-server) 2>&1 | grep "No agent"'
#   "Failed to get a backend" err="No agent available" dialID=…
# re-apply the agent DaemonSet → logs/exec work again
```

## Cleanup
```bash
./cleanup.sh          # = ./konn-lab.sh delete (deletes konn-lab, starts the default minikube)
```
