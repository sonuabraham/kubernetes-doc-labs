# DNS for Services and Pods – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/

## Key ideas (read first)

| Record | Name | Answer |
|---|---|---|
| Service A/AAAA (normal) | `<svc>.<ns>.svc.cluster.local` | the ClusterIP |
| Service A/AAAA (headless) | same | **all ready Pod IPs** |
| SRV (named ports) | `_<port-name>._<proto>.<svc>.<ns>.svc.cluster.local` | port + target name. For headless Services, one per Pod (`<hostname>.<svc>…`) |
| Pod A (by IP) | `<a-b-c-d>.<ns>.pod.cluster.local` | the Pod IP |
| Pod A (hostname + subdomain) | `<hostname>.<subdomain>.<ns>.svc.cluster.local` | needs a **headless Service named like the subdomain** in the same namespace |

| dnsPolicy | resolv.conf |
|---|---|
| **ClusterFirst** (default) | cluster DNS (CoreDNS), search `<ns>.svc.cluster.local svc.cluster.local cluster.local`, `ndots:5`. Non-cluster names are forwarded upstream. |
| **Default** | inherits the **node's** resolv.conf (no cluster names!) |
| **ClusterFirstWithHostNet** | for `hostNetwork: true` Pods that still want cluster DNS |
| **None** | only what you put in `dnsConfig` (`nameservers`, `searches`, `options`) |

| Concept | Meaning |
|---|---|
| **Namespaces** | Short names resolve in the Pod's **own** namespace; use `svc.ns` to cross. |
| **setHostnameAsFQDN** | Hostname = FQDN (see `../../workloads/pods/pod-hostname`). |
| **Search limits** | Up to **32** search domains, total length **2048** characters (stable since 1.28). |
| **Windows** | Different resolver behaviour (no `ndots`, the search list is only used for single-label names). |

## The demo app
The docs examples are **verbatim**: [busybox-subdomain.yaml](busybox-subdomain.yaml) (headless Service `busybox-subdomain` + Pods `busybox1`/`busybox2` with hostname/subdomain), [busybox-hostnetwork.yaml](busybox-hostnetwork.yaml) (`ClusterFirstWithHostNet`, **pinned to namespace `default`**) and [custom-dns.yaml](custom-dns.yaml) (`dnsPolicy: None` + `dnsConfig`, **also namespace `default`**).
[00-demo.yaml](00-demo.yaml) (namespace `dns-demo`) has a `dnsutils` pod (dig), Deployment + Service `web` with named port `http`, and pods with `dnsPolicy` ClusterFirst / Default.

---

## Step 1
```bash
cd concepts/services-networking/dns-pod-service
kubectl apply -f 00-demo.yaml
kubectl apply -f busybox-subdomain.yaml -n dns-demo
kubectl apply -f busybox-hostnetwork.yaml -f custom-dns.yaml          # these two carry namespace: default themselves
kubectl wait --for=condition=Ready pod --all -n dns-demo --timeout=120s
d(){ kubectl exec dnsutils -n dns-demo -- dig +short +search "$@"; }
```

## Lab 1 – Service records
```bash
d web.dns-demo.svc.cluster.local                       # 10.108.88.76            (ClusterIP)
d web                                                  # same - short name, own namespace
d SRV _http._tcp.web.dns-demo.svc.cluster.local        # 0 100 80 web.dns-demo.svc.cluster.local.
d busybox-subdomain.dns-demo.svc.cluster.local         # 10.244.0.167 10.244.0.168   (headless: the Pod IPs)
d SRV _foo._tcp.busybox-subdomain.dns-demo.svc.cluster.local
#   0 50 1234 busybox-1.busybox-subdomain.dns-demo.svc.cluster.local.
#   0 50 1234 busybox-2.busybox-subdomain.dns-demo.svc.cluster.local.     <- one SRV per Pod
```

## Lab 2 – Pod records
```bash
d busybox-1.busybox-subdomain.dns-demo.svc.cluster.local      # 10.244.0.167  (hostname + subdomain + headless Service)
IP=$(kubectl get pod busybox1 -n dns-demo -o jsonpath='{.status.podIP}')
d ${IP//./-}.dns-demo.pod.cluster.local                       # 10.244.0.167  (dashed-IP record)
kubectl exec busybox1 -n dns-demo -- hostname -f              # busybox-1.busybox-subdomain.dns-demo.svc.cluster.local
```
Delete the Service `busybox-subdomain` and the hostname record disappears. The subdomain needs it.

## Lab 3 – DNS policies
```bash
kubectl exec policy-clusterfirst -n dns-demo -- cat /etc/resolv.conf
#   search dns-demo.svc.cluster.local svc.cluster.local cluster.local
#   nameserver 10.96.0.10            <- CoreDNS (kube-dns Service)
#   options ndots:5
kubectl exec policy-default -n dns-demo -- cat /etc/resolv.conf
#   nameserver 192.168.58.1          <- the NODE's resolver: "web.dns-demo.svc.cluster.local" won't resolve here
kubectl exec dns-example -n default -- cat /etc/resolv.conf
#   search ns1.svc.cluster-domain.example my.dns.search.suffix
#   nameserver 192.0.2.1
#   options ndots:2 edns0            <- exactly the docs' dnsConfig
kubectl exec busybox -n default -- cat /etc/resolv.conf
#   nameserver 10.96.0.10 ...        <- hostNetwork + ClusterFirstWithHostNet: cluster DNS
kubectl run hostnet-cf -n dns-demo --image=busybox:1.36 --overrides='{"spec":{"hostNetwork":true}}' -- sleep 3600
kubectl exec hostnet-cf -n dns-demo -- cat /etc/resolv.conf
#   nameserver 192.168.58.1          <- hostNetwork + plain ClusterFirst silently falls back to the node's DNS
```

## Lab 4 – ndots and the search list
```bash
kubectl exec dnsutils -n dns-demo -- dig +search +showsearch kubernetes.io | grep -E '^;; (QUESTION|->>HEADER)|^kubernetes' | head
```
With `ndots:5`, `kubernetes.io` (1 dot) is first tried as `kubernetes.io.dns-demo.svc.cluster.local`, `.svc.cluster.local` and `.cluster.local` (NXDOMAIN each) before the real name. Use a trailing dot (`kubernetes.io.`) or a lower `ndots` (via `dnsConfig.options`) for heavy external lookups.

---

## Useful commands
```bash
kubectl exec <pod> -- cat /etc/resolv.conf
kubectl get svc kube-dns -n kube-system ; kubectl get cm coredns -n kube-system -o yaml
kubectl exec dnsutils -n dns-demo -- dig +short SRV _<port>._tcp.<svc>.<ns>.svc.cluster.local
```

## Cleanup
```bash
./cleanup.sh       # dns-demo + the docs' busybox and dns-example pods in default
```
