# Using NodeLocal DNSCache in Kubernetes Clusters – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/administer-cluster/nodelocaldns/

> This follows the page's steps on a throwaway profile **`nld-lab`** (kube-proxy in **iptables** mode):
> - [nodelocaldns-sample.yaml](nodelocaldns-sample.yaml) is the upstream sample manifest the page links to, downloaded unchanged.
> - [nodelocaldns.yaml](nodelocaldns.yaml) is the same file after the docs' `sed`.
> - [kube-dns-stubdomains.yaml](kube-dns-stubdomains.yaml) is the docs' stubDomains ConfigMap, **verbatim**.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **What** | A DaemonSet (`node-local-dns`, image `k8s-dns-node-cache`) runs a caching CoreDNS on **every node**, on the host network. Pods' DNS queries are answered on their own node and cache misses go to CoreDNS. |
| **Why** | No conntrack entries/DNAT for most DNS traffic (avoids conntrack races and UDP drops), fewer hops, cache hits stay local, TCP upstream connections. Metrics are per node. |
| **Addresses** | A link-local listen IP (e.g. `169.254.20.10`). In iptables mode it *also* binds the kube-dns ClusterIP, so Pods need no change to `resolv.conf`. In IPVS mode only the link-local IP is used, and the kubelet's `clusterDNS` must point to it. |
| **Placeholders** | You substitute `__PILLAR__LOCAL__DNS__`, `__PILLAR__DNS__DOMAIN__`, `__PILLAR__DNS__SERVER__`. The Pod fills `__PILLAR__CLUSTER__DNS__` (the `kube-dns-upstream` Service) and `__PILLAR__UPSTREAM__SERVERS__` itself. |
| **Memory** | Cache usage depends on the query pattern (10000 entries ≈ 30 MB per server block). An OOM-killed cache leaves its packet-filter rules behind, which means a brief DNS outage. |

---

## Step 0
```bash
cd tasks/administer-cluster/nodelocaldns
minikube start -p nld-lab --memory 2200 --cpus 2 --kubernetes-version v1.37.0 && kubectl config use-context nld-lab
kubectl -n kube-system get cm kube-proxy -o jsonpath='{.data.config\.conf}' | grep ^mode          # mode: iptables
curl -sSLo nodelocaldns-sample.yaml https://raw.githubusercontent.com/kubernetes/kubernetes/master/cluster/addons/dns/nodelocaldns/nodelocaldns.yaml
grep -n image: nodelocaldns-sample.yaml        # registry.k8s.io/dns/k8s-dns-node-cache:1.27.1
```

## Lab 1 – Configure and enable (the docs' steps, iptables mode)
```bash
cp nodelocaldns-sample.yaml nodelocaldns.yaml
coredns=`kubectl get svc kube-dns -n kube-system -o jsonpath={.spec.clusterIP}`
domain=cluster.local
localdns=169.254.20.10
sed -i "s/__PILLAR__LOCAL__DNS__/$localdns/g; s/__PILLAR__DNS__DOMAIN__/$domain/g; s/__PILLAR__DNS__SERVER__/$coredns/g" nodelocaldns.yaml
grep -oE "__PILLAR__[A-Z_]+__" nodelocaldns.yaml | sort -u
#   __PILLAR__CLUSTER__DNS__   __PILLAR__UPSTREAM__SERVERS__        <- left for the node-local-dns Pods to fill in
kubectl create -f nodelocaldns.yaml
#   serviceaccount/node-local-dns  service/kube-dns-upstream  configmap/node-local-dns  daemonset.apps/node-local-dns  service/node-local-dns  created
kubectl -n kube-system get po -l k8s-app=node-local-dns -o wide        # node-local-dns-...  Running  192.168.193.2 (hostNetwork)
kubectl -n kube-system logs ds/node-local-dns | grep -E "Added interface|:53 on"
#   [INFO] Added interface - nodelocaldns
#   .:53 on 169.254.20.10   cluster.local.:53 on 169.254.20.10 ...
#   .:53 on 10.96.0.10      cluster.local.:53 on 10.96.0.10 ...        <- also the kube-dns ClusterIP
minikube ssh -p nld-lab -- 'ip -4 addr show nodelocaldns'
#   nodelocaldns: <BROADCAST,NOARP> ... inet 169.254.20.10/32 ... inet 10.96.0.10/32
```
(In the first seconds the cache logged `dial tcp 10.111.13.164:53: connect: connection refused`. That's the new `kube-dns-upstream` Service before kube-proxy had programmed it. It stops by itself.)

## Lab 2 – Are Pods really served by the node-local cache?
```bash
kubectl run dnsq --image=busybox:1.36 --restart=Never -- sleep 3600
kubectl exec dnsq -- cat /etc/resolv.conf | grep nameserver        # nameserver 10.96.0.10   <- unchanged
NLD=$(kubectl -n kube-system get po -l k8s-app=node-local-dns -o jsonpath='{.items[0].metadata.name}')
for i in 1 2 3 4 5; do kubectl exec dnsq -- nslookup kubernetes.default.svc.cluster.local >/dev/null; done
kubectl get --raw "/api/v1/namespaces/kube-system/pods/$NLD:9253/proxy/metrics" | grep ^coredns_dns_requests_total
#   coredns_dns_requests_total{...,server="dns://10.96.0.10:53",...}     <- 10 requests (5 x A+AAAA) answered by the NODE-LOCAL cache
kubectl exec dnsq -- nslookup kubernetes.default.svc.cluster.local 169.254.20.10      # also answers on the link-local IP
```
The page describes `NOTRACK` packet-filter rules for this. On this node neither `iptables -t raw -S` (nft backend) nor `iptables-legacy` nor `nft list ruleset` showed rules mentioning the two addresses, yet the metrics prove the Pod's queries reached the local cache.

## Lab 3 – Stub domains via the `kube-dns` ConfigMap
```bash
kubectl apply -f kube-dns-stubdomains.yaml         # {"abc.com" : ["1.2.3.4"], "my.cluster.local" : ["2.3.4.5"]}
kubectl -n kube-system logs $NLD | grep "custom stubdomains" | tail -1
#   [INFO] Updated Corefile with 2 custom stubdomains and upstream servers /etc/resolv.conf
kubectl -n kube-system logs $NLD | grep -A5 "^abc.com:53"
#   abc.com:53 {  errors  cache 30  bind 169.254.20.10 10.96.0.10  forward . 1.2.3.4  }     <- generated server block
```

## Lab 4 – Disable it
```bash
kubectl delete -f nodelocaldns.yaml
minikube ssh -p nld-lab -- 'ip link show nodelocaldns'
#   nodelocaldns: <BROADCAST,NOARP> ...      <- the dummy interface was still there right after the DaemonSet was deleted
kubectl config use-context minikube
```
In IPVS mode you'd also revert the kubelet's `clusterDNS`.

---

## Useful commands
```bash
kubectl -n kube-system logs ds/node-local-dns
kubectl get --raw /api/v1/namespaces/kube-system/pods/<node-local-dns-pod>:9253/proxy/metrics | grep coredns_
ip addr show nodelocaldns
```

## Cleanup
```bash
minikube delete -p nld-lab ; kubectl config use-context minikube
```
