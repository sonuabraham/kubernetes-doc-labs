# Using CoreDNS for Service Discovery – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/administer-cluster/coredns/

> The page points to installing, upgrading and tuning CoreDNS. Each point is made concrete on a throwaway profile **`coredns-lab`** (minikube builds clusters with kubeadm). It has no YAML; the commands here are not from the docs. For Corefile customization and debugging, see [../dns-custom-nameservers](../dns-custom-nameservers/) and [../dns-debugging-resolution](../dns-debugging-resolution/).

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **CoreDNS** | The default cluster DNS: a Deployment `coredns` behind the Service `kube-dns`, configured by the `coredns` ConfigMap (Corefile). |
| **Which version** | kubeadm pins one CoreDNS version per kubeadm release (the CoreDNS-k8s_version table). `kubeadm config images list` shows it. |
| **Manual upgrade** | Change the image, but keep the Corefile and check it against the new version's plugins (CoreDNS's "Upgrading_CoreDNS" walkthrough; the `corefile-migration` tool). |
| **kubeadm upgrades** | Reset the CoreDNS **Deployment** to kubeadm's version and spec, but **retain the existing Corefile**. |
| **Tuning** | Size memory/CPU from the cluster size and the query load (Scaling_CoreDNS guide). Watch the Prometheus metrics on `:9153`. Scale replicas, e.g. with [../dns-horizontal-autoscaling](../dns-horizontal-autoscaling/). |

---

## Step 0
```bash
cd tasks/administer-cluster/coredns
minikube start -p coredns-lab --memory 2200 --cpus 2 --kubernetes-version v1.37.0 && kubectl config use-context minikube
K="kubectl --context coredns-lab -n kube-system"; N(){ P=coredns-lab ../kubeadm/node.sh "$1"; }
```

## Lab 1 – Which CoreDNS goes with this Kubernetes?
```bash
N '$KUBEADM config images list --kubernetes-version v1.37.0 | grep -E "coredns|etcd"'
#   registry.k8s.io/coredns/coredns:v1.14.6
#   registry.k8s.io/etcd:3.7.0-0
N '$KUBEADM config images list --kubernetes-version v1.36.0 | grep coredns'
#   registry.k8s.io/coredns/coredns:v1.14.6       <- the kubeadm BINARY decides, not the target version
$K get deploy coredns -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'     # registry.k8s.io/coredns/coredns:v1.14.6
```

## Lab 2 – A custom Corefile, then a manual image change
```bash
$K get cm coredns -o json | python3 -c 'import json,sys;d=json.load(sys.stdin);d["data"]["Corefile"]=d["data"]["Corefile"].replace("host.minikube.internal","host.minikube.internal\n       10.10.10.10 legacy-db.internal");print(json.dumps(d))' | $K replace -f -
kubectl --context coredns-lab run dnsq --image=busybox:1.36 --restart=Never -- sleep 3600
kubectl --context coredns-lab exec dnsq -- nslookup legacy-db.internal      # (after the reload) Address: 10.10.10.10
$K set image deploy/coredns coredns=registry.k8s.io/coredns/coredns:v1.14.2     # "use your own image/version"
$K rollout status deploy/coredns
$K logs deploy/coredns | grep CoreDNS-                                          # CoreDNS-1.14.2
kubectl --context coredns-lab exec dnsq -- nslookup legacy-db.internal      # Address: 10.10.10.10 - same Corefile, other binary
```

## Lab 3 – What a kubeadm upgrade does to CoreDNS
Run only kubeadm's CoreDNS step of `kubeadm upgrade apply`:
```bash
N '$KUBEADM upgrade apply phase addon coredns v1.37.0'
#   [addons] Applied essential addon: CoreDNS
$K get deploy coredns -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'    # .../coredns:v1.14.6  <- Deployment reset
$K get cm coredns -o jsonpath='{.data.Corefile}' | grep legacy-db                       # 10.10.10.10 legacy-db.internal  <- Corefile kept
kubectl --context coredns-lab exec dnsq -- nslookup legacy-db.internal                 # still 10.10.10.10
```
Changes to the Deployment itself (image, resources, replicas) are **not** kept, see [../kubeadm/kubeadm-reconfigure](../kubeadm/kubeadm-reconfigure/) Lab 5 and the kubeadm patches there.

## Lab 4 – Numbers for tuning
```bash
POD=$($K get po -l k8s-app=kube-dns -o jsonpath='{.items[0].metadata.name}')
kubectl --context coredns-lab get --raw "/api/v1/namespaces/kube-system/pods/$POD:9153/proxy/metrics" \
  | grep -E "^coredns_(dns_requests_total|cache_(hits|misses)_total|cache_entries)|^process_resident_memory_bytes"
#   coredns_dns_requests_total{...type="A"...} 6   {...type="AAAA"...} 6      <- query rate per type
#   coredns_cache_hits_total{type="success"} 4   {type="denial"} 4   coredns_cache_misses_total 5
#   coredns_cache_entries{type="success"} 2  {type="denial"} 3
$K get deploy coredns -o jsonpath='{.spec.template.spec.containers[0].resources}{"\n"}'
#   {"limits":{"memory":"170Mi"},"requests":{"cpu":"100m","memory":"70Mi"}}     <- kubeadm defaults; size them from the guide
```

---

## Useful commands
```bash
kubeadm config images list
kubectl -n kube-system set image deploy/coredns coredns=<image>
kubectl -n kube-system get cm coredns -o jsonpath='{.data.Corefile}'
kubectl get --raw /api/v1/namespaces/kube-system/pods/<coredns-pod>:9153/proxy/metrics
```

## Cleanup
```bash
minikube delete -p coredns-lab
```
