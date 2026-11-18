# Configure DNS for a Cluster – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/access-application-cluster/configure-dns-cluster/

> The docs page is two sentences: clusters ship a DNS addon (CoreDNS, installed by kubeadm since 1.11), and the configuration is
> covered in [Customizing DNS Service](../../administer-cluster/dns-custom-nameservers/), which has the full lab (stub domains, upstreams,
> on a throwaway profile). This lab only **checks the addon is there and how Pods are wired to it** on the default minikube cluster.
> File: [dns-check.yaml](dns-check.yaml) (not from the docs).
>
> **Gotcha:** `busybox nslookup kubernetes.default` gives `NXDOMAIN` because busybox's nslookup ignores the `search` list.
> Use the full name, `getent`, or `dig +search`.

## Key ideas (read first)

| Piece | Where |
|---|---|
| CoreDNS | Deployment `kube-system/coredns` (label `k8s-app=kube-dns`) |
| Service | `kube-system/kube-dns` (old name kept), fixed ClusterIP `10.96.0.10`, ports 53/UDP, 53/TCP, 9153 (metrics) |
| Config | ConfigMap `kube-system/coredns`, key `Corefile` |
| Pod wiring | kubelet `clusterDNS` + `clusterDomain` → each Pod's `/etc/resolv.conf` (search list, `ndots:5`) |

---

## Lab 1 – The addon
```bash
cd tasks/access-application-cluster/configure-dns-cluster
kubectl -n kube-system get deploy coredns -o wide       # registry.k8s.io/coredns/coredns:v1.14.6   selector k8s-app=kube-dns
kubectl -n kube-system get svc kube-dns                 # ClusterIP 10.96.0.10   53/UDP,53/TCP,9153/TCP
kubectl get --raw /api/v1/nodes/minikube/proxy/configz | jq -c '.kubeletconfig | {clusterDNS, clusterDomain, resolvConf}'
#   {"clusterDNS":["10.96.0.10"],"clusterDomain":"cluster.local","resolvConf":"/etc/resolv.conf"}
kubectl -n kube-system get cm coredns -o jsonpath='{.data.Corefile}'
#   .:53 { log errors health ready kubernetes cluster.local in-addr.arpa ip6.arpa {pods insecure … ttl 30} prometheus :9153
#          hosts { 192.168.58.1 host.minikube.internal fallthrough }      <- minikube's addition
#          forward . /etc/resolv.conf  cache 30 {…}  loop reload loadbalance }
```

## Lab 2 – What a Pod sees
```bash
kubectl apply -f dns-check.yaml && kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/dns-check
kubectl logs dns-check
#   search default.svc.cluster.local svc.cluster.local cluster.local
#   nameserver 10.96.0.10
#   options ndots:5
#   10.96.0.1       kubernetes.default.svc.cluster.local     <- short name + search list
#   10.96.0.10      kube-dns.kube-system.svc.cluster.local
#   192.168.58.1    host.minikube.internal                   <- the hosts block
#   15.197.167.90   kubernetes.io                            <- forwarded upstream
kubectl run dnscheck --image=busybox:1.36 --restart=Never --command -- nslookup kubernetes.default
kubectl logs dnscheck                                   # ** server can't find kubernetes.default: NXDOMAIN   <- busybox quirk
```
To change the Corefile (stub domains, upstream servers), follow [dns-custom-nameservers](../../administer-cluster/dns-custom-nameservers/).

## Cleanup
```bash
./cleanup.sh
```
