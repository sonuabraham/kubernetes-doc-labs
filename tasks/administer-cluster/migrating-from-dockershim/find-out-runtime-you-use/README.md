# Find Out What Container Runtime is Used on a Node – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/administer-cluster/migrating-from-dockershim/find-out-runtime-you-use/

> Compares two real nodes: the default **`minikube`** cluster (containerd) and the throwaway **`rt-lab`** profile (Docker Engine via **cri-dockerd**, started by [../start-rt-lab.sh](../start-rt-lab.sh)). [../node.sh](../node.sh) runs commands on a node (`P=minikube` for the containerd one).

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **CONTAINER-RUNTIME column** | `kubectl get nodes -o wide` shows `.status.nodeInfo.containerRuntimeVersion` as `<runtime>://<version>`. The kubelet reports it from the CRI `Version` call. |
| **CRI endpoint** | The kubelet is a gRPC **client**. The runtime (or an adapter) is the **server** on a Unix socket. |
| **dockershim** | The adapter that used to be built into the kubelet. It was removed in v1.24. `docker://` on a ≥1.24 node therefore means an **external** adapter (cri-dockerd), so you're *not* affected by the removal. |
| **Where the endpoint is set** | Either the `--container-runtime-endpoint` flag or `containerRuntimeEndpoint` in the kubelet config file. Modern kubeadm/minikube use the **config file**, so the docs' cmdline check shows nothing. Follow `--config`. |
| **`--container-runtime`** | Gone since v1.27. A current kubelet refuses to start with it. |

---

## Step 0
```bash
cd tasks/administer-cluster/migrating-from-dockershim
./start-rt-lab.sh
cd find-out-runtime-you-use
```

## Lab 1 – Runtime per node
```bash
kubectl --context rt-lab get nodes -o wide
#   NAME     STATUS   ROLES           VERSION   ...   CONTAINER-RUNTIME
#   rt-lab   Ready    control-plane   v1.37.0   ...   docker://29.7.2
kubectl --context minikube get nodes -o wide
#   minikube Ready    control-plane   v1.37.0   ...   containerd://2.3.4
kubectl --context rt-lab get nodes -o custom-columns=NAME:.metadata.name,RUNTIME:.status.nodeInfo.containerRuntimeVersion
```

## Lab 2 – Which endpoint does the kubelet use?
The docs' command, on both nodes:
```bash
for p in rt-lab minikube; do echo "== $p"; P=$p ../node.sh 'tr \\0 " " < /proc/"$(pgrep kubelet)"/cmdline | tr " " "\n" | grep -E "container-runtime|^--config"
  grep containerRuntimeEndpoint /var/lib/kubelet/config.yaml'; done
#   == rt-lab
#   --config=/var/lib/kubelet/config.yaml                         <- no --container-runtime(-endpoint) flag at all...
#   containerRuntimeEndpoint: unix:///var/run/cri-dockerd.sock    <- ...it's in the config file: cri-dockerd = Docker Engine, NOT dockershim
#   == minikube
#   --config=/var/lib/kubelet/config.yaml
#   containerRuntimeEndpoint: unix:///run/containerd/containerd.sock
```
Ask each socket directly with `crictl`. The Docker node has **both** daemons, because Docker Engine runs its containers through containerd:
```bash
../node.sh 'crictl --runtime-endpoint unix:///var/run/cri-dockerd.sock version
  crictl --runtime-endpoint unix:///run/containerd/containerd.sock version'
#   RuntimeName:  docker       RuntimeVersion:  29.7.2   RuntimeApiVersion:  v1
#   RuntimeName:  containerd   RuntimeVersion:  v2.3.4   RuntimeApiVersion:  v1
```
The flag the page mentions for ≤1.23 clusters no longer exists:
```bash
../node.sh '/var/lib/minikube/binaries/v1.37.0/kubelet --container-runtime=remote --version'
#   "command failed" err="failed to parse kubelet flag: unknown flag: --container-runtime"
```

---

## Useful commands
```bash
kubectl get nodes -o custom-columns=NAME:.metadata.name,RUNTIME:.status.nodeInfo.containerRuntimeVersion
crictl --runtime-endpoint <socket> version | info
grep containerRuntimeEndpoint /var/lib/kubelet/config.yaml
```

## Cleanup
Keep `rt-lab` for the other labs in [..](../). When finished: `minikube delete -p rt-lab`.
