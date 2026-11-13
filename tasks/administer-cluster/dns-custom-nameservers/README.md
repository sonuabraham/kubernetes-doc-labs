# Customizing DNS Service – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/administer-cluster/dns-custom-nameservers/

> This runs on a throwaway profile **`dns-lab`**, because one of the docs' ConfigMaps breaks external DNS. Files:
> - Docs ConfigMaps, **verbatim**: [00-coredns-default-docs.yaml](00-coredns-default-docs.yaml) (the default Corefile, for reference) and [01-coredns-docs-final.yaml](01-coredns-docs-final.yaml) (stub domain + upstream).
> - [02-consul-dns-server.yaml](02-consul-dns-server.yaml) is extra: a stand-in for the docs' Consul server, a small CoreDNS authoritative for `consul.local`.
> - [03-coredns-stub-working.yaml](03-coredns-stub-working.yaml) is minikube's own Corefile plus the stub stanza.
> - [04-dnsutils.yaml](04-dnsutils.yaml) is the dig client.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **kube-dns Service** | CoreDNS runs behind a Service named `kube-dns` (legacy name) at a fixed ClusterIP (`10.96.0.10`). The kubelet writes that IP into Pods' `resolv.conf` (`clusterDNS` / `--cluster-dns`, domain `clusterDomain`). |
| **dnsPolicy** | `ClusterFirst` (default): CoreDNS + search domains, `ndots:5`. `Default`: inherit the **node's** resolv.conf (or the kubelet's `resolvConf`), so cluster names don't resolve. |
| **Corefile** | ConfigMap `kube-system/coredns`, key `Corefile`. Plugins: `errors`, `health`, `ready`, `kubernetes` (cluster records, `ttl`, `pods insecure/verified/disabled`), `prometheus`, `forward`, `cache`, `loop`, `reload`, `loadbalance`. |
| **reload** | CoreDNS notices ConfigMap changes by itself. The volume update plus reload took **~55–75 s** here (the docs: allow up to 2 minutes). |
| **Stub domain** | An extra server block, `consul.local:53 { forward . <ip> }`, sends one domain to a specific nameserver. `forward . <ip>` in the main block changes the upstream for everything else. Only IPs work there, not FQDNs. |

---

## Step 0
```bash
cd tasks/administer-cluster/dns-custom-nameservers
minikube start -p dns-lab --memory 2200 --cpus 2 --kubernetes-version v1.37.0 && kubectl config use-context minikube
K="kubectl --context dns-lab"
$K -n kube-system get cm coredns -o jsonpath='{.data.Corefile}'
#   .:53 { log errors health{lameduck 5s} ready kubernetes cluster.local ... {pods insecure ... ttl 30} prometheus :9153
#          hosts { 192.168.184.1 host.minikube.internal  fallthrough }        <- minikube's addition
#          forward . /etc/resolv.conf {max_concurrent 1000} cache 30 {...} loop reload loadbalance }
$K -n kube-system get svc kube-dns            # kube-dns   ClusterIP   10.96.0.10   53/UDP,53/TCP,9153/TCP
$K apply -f 02-consul-dns-server.yaml -f 04-dnsutils.yaml
q(){ $K exec dnsutils -- dig +short +time=2 +tries=1 "$@"; }
```

## Lab 1 – Baseline
```bash
q kubernetes.default.svc.cluster.local      # 10.96.0.1
q example.com                               # 104.20.23.154 172.66.147.243
q web.consul.local                          # (nothing - SERVFAIL: the upstream doesn't know .consul.local)
q @10.100.150.1 web.consul.local            # 10.150.0.42   <- the "Consul" server itself works
$K exec dnsutils -- cat /etc/resolv.conf
#   search default.svc.cluster.local svc.cluster.local cluster.local
#   nameserver 10.96.0.10
#   options ndots:5
```

## Lab 2 – Add a stub domain (working version)
```bash
$K apply -f 03-coredns-stub-working.yaml
until q web.consul.local | grep -q 10.150; do sleep 5; done          # ~74 s here
q web.consul.local                         # 10.150.0.42
q db.consul.local                          # 10.150.0.43
q example.com                              # still works
$K -n kube-system logs -l k8s-app=kube-dns | grep -E "Reloading"   # [INFO] Reloading complete
$K -n kube-system logs deploy/consul-dns | tail -1
#   [INFO] 10.244.0.2:60467 - ... "A IN db.consul.local. udp 44 false 4096" NOERROR qr,aa,rd ...     <- forwarded by cluster CoreDNS
```

## Lab 3 – The docs' final ConfigMap, verbatim
```bash
$K apply -f 01-coredns-docs-final.yaml           # forward . 172.16.0.1 ; consul.local -> 10.150.0.1 (both don't exist here)
until ! q host.minikube.internal | grep -q 192; do sleep 5; done
$K exec dnsutils -- dig kubernetes.default.svc.cluster.local | grep -E "status|IN\s+A"
#   status: NOERROR   kubernetes.default.svc.cluster.local. 5 IN A 10.96.0.1     <- TTL 5: this Corefile has no "ttl 30"
$K exec dnsutils -- dig +time=3 +tries=1 example.com | grep status       # SERVFAIL - upstream 172.16.0.1 unreachable
q web.consul.local                                                       # (timeout - 10.150.0.1 unreachable)
$K exec dnsutils -- dig host.minikube.internal | grep status             # SERVFAIL - minikube's hosts block is gone
```
It's a template: put **your** upstream and stub IPs in it, and merge in what your distribution added (here the `hosts` block).

## Lab 4 – Pod records: `pods insecure` vs `pods verified`
```bash
$K apply -f 03-coredns-stub-working.yaml                           # back to insecure
D=$($K get pod dnsutils -o jsonpath='{.status.podIP}' | tr . -)   # 10-244-0-3
q 1-2-3-4.default.pod.cluster.local        # 1.2.3.4     <- insecure: any dashed IP is echoed back
q $D.default.pod.cluster.local             # 10.244.0.3
sed 's/pods insecure/pods verified/' 03-coredns-stub-working.yaml | $K apply -f -
# after the reload:
$K exec dnsutils -- dig 1-2-3-4.default.pod.cluster.local | grep status         # NXDOMAIN
$K exec dnsutils -- dig $D.default.pod.cluster.local | grep -E "status|IN\s+A"   # NOERROR  10.244.0.3   (a real Pod in that namespace)
$K exec dnsutils -- dig $D.kube-system.pod.cluster.local | grep status          # NXDOMAIN (wrong namespace)
```

## Lab 5 – dnsPolicy Default
```bash
$K run dns-default --image=busybox:1.36 --restart=Never --overrides='{"spec":{"dnsPolicy":"Default"}}' -- \
  sh -c 'cat /etc/resolv.conf; nslookup kubernetes.default.svc.cluster.local'
$K logs dns-default
#   nameserver 192.168.184.1                <- the node's resolver (Docker's gateway), no search domains
#   options edns0 trust-ad ndots:0
#   ** server can't find kubernetes.default.svc.cluster.local: SERVFAIL
```

---

## Useful commands
```bash
kubectl -n kube-system get cm coredns -o jsonpath='{.data.Corefile}'
kubectl -n kube-system edit cm coredns
kubectl -n kube-system logs -l k8s-app=kube-dns -f
kubectl exec dnsutils -- dig +short <name> ; kubectl exec dnsutils -- dig @<server> <name>
```

## Cleanup
```bash
minikube delete -p dns-lab
```
