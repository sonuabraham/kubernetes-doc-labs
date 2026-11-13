# Debugging DNS Resolution – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/administer-cluster/dns-debugging-resolution/

> This runs the page's checklist on a throwaway profile **`dnsdebug-lab`**: once on a healthy cluster, then four times with DNS **broken on purpose** in the ways the page diagnoses. [dnsutils.yaml](dnsutils.yaml) is the docs' test Pod, **verbatim** (`agnhost:2.39`, which has `nslookup`/`dig`).

## Key ideas (read first)

| Check | Command | What a broken result looks like |
|---|---|---|
| Resolve something | `kubectl exec -i -t dnsutils -- nslookup kubernetes.default` | `connection timed out; no servers could be reached` / `SERVFAIL` / `NXDOMAIN` |
| resolv.conf | `kubectl exec -ti dnsutils -- cat /etc/resolv.conf` | wrong `nameserver`, missing `search` domains or `ndots:5` |
| CoreDNS Pods | `kubectl get pods -n kube-system -l k8s-app=kube-dns` | missing, `0/1`, `CrashLoopBackOff` |
| CoreDNS logs | `kubectl logs -n kube-system -l k8s-app=kube-dns` | `[ERROR]` / `[FATAL]` lines |
| Service | `kubectl get svc -n kube-system` | no `kube-dns` / wrong ClusterIP |
| Endpoints | `kubectl get endpointslice -l kubernetes.io/service-name=kube-dns -n kube-system` | `<unset>` = no ready CoreDNS Pods |
| Queries arriving? | add `log` to the Corefile (minikube already has it) | no `[INFO] ... "A IN ..."` lines |
| RBAC | `kubectl describe clusterrole system:coredns` | missing `endpointslices`/`services`/... list+watch |
| Namespace | `nslookup <svc>` vs `nslookup <svc>.<namespace>` | short names only search the Pod's own namespace |

Known issues from the page:
- **systemd-resolved stub:** a `127.0.0.53` stub resolver in `/etc/resolv.conf` gives a **forwarding loop**. Point the kubelet's `resolvConf` at `/run/systemd/resolve/resolv.conf`.
- **3-nameserver glibc limit.**
- **Alpine ≤3.17:** no TCP fallback for answers over 512 bytes.

---

## Step 0 + healthy baseline
```bash
cd tasks/administer-cluster/dns-debugging-resolution
minikube start -p dnsdebug-lab --memory 2200 --cpus 2 --kubernetes-version v1.37.0 && kubectl config use-context minikube
K="kubectl --context dnsdebug-lab"
$K apply -f dnsutils.yaml && $K wait --for=condition=Ready pod/dnsutils
$K exec -i -t dnsutils -- nslookup kubernetes.default
#   Server:  10.96.0.10   Address: 10.96.0.10#53
#   Name:    kubernetes.default.svc.cluster.local   Address: 10.96.0.1
$K exec -ti dnsutils -- cat /etc/resolv.conf
#   search default.svc.cluster.local svc.cluster.local cluster.local
#   nameserver 10.96.0.10
#   options ndots:5
$K get pods --namespace=kube-system -l k8s-app=kube-dns        # coredns-...   1/1   Running
$K logs --namespace=kube-system -l k8s-app=kube-dns | head -5
#   .:53   [INFO] plugin/reload: Running configuration SHA512 = ...   CoreDNS-1.14.6   linux/amd64, go1.26.5
$K get endpointslice -l kubernetes.io/service-name=kube-dns --namespace=kube-system
#   kube-dns-ztz2c   IPv4   53,53,9153   10.244.0.2
$K describe clusterrole system:coredns -n kube-system
#   endpoints, namespaces, pods, services, endpointslices.discovery.k8s.io   [list watch]      <- as the docs expect
```

## Break 1 – No DNS endpoints
```bash
$K -n kube-system scale deploy coredns --replicas=0
$K exec -i -t dnsutils -- nslookup -timeout=3 kubernetes.default
#   ;; connection timed out; no servers could be reached
$K get endpointslice -l kubernetes.io/service-name=kube-dns --namespace=kube-system
#   kube-dns-ztz2c   IPv4   <unset>   <unset>          <- Service exists, nothing behind it
$K -n kube-system scale deploy coredns --replicas=1
```

## Break 2 – CoreDNS lacks RBAC for EndpointSlices
```bash
$K patch clusterrole system:coredns --type=json -p '[{"op":"remove","path":"/rules/1"}]'     # rule 1 = endpointslices
$K -n kube-system rollout restart deploy coredns
$K get pods --namespace=kube-system -l k8s-app=kube-dns
#   coredns-779787688b-7z9f4   0/1   Running      <- never Ready: the kubernetes plugin can't sync
$K logs --namespace=kube-system -l k8s-app=kube-dns | grep forbidden | head -1
#   [ERROR] plugin/kubernetes: Failed to watch: failed to list *v1.EndpointSlice: endpointslices.discovery.k8s.io is forbidden:
#   User "system:serviceaccount:kube-system:coredns" cannot list resource "endpointslices" in API group "discovery.k8s.io" ...
$K exec -i -t dnsutils -- nslookup -timeout=3 kubernetes.default
#   ;; connection timed out; no servers could be reached     <- the old Pod was already replaced (maxUnavailable 1)
```
The fix is the docs' insertion (`kubectl edit clusterrole system:coredns`), done here as a patch:
```bash
$K patch clusterrole system:coredns --type=json -p '[{"op":"add","path":"/rules/-","value":{"apiGroups":["discovery.k8s.io"],"resources":["endpointslices"],"verbs":["list","watch"]}}]'
$K -n kube-system rollout status deploy coredns && $K exec -i -t dnsutils -- nslookup kubernetes.default     # 10.96.0.1 again
```

## Break 3 – Wrong namespace (and reading the query log)
```bash
$K create ns other && $K -n other create service clusterip my-svc --tcp=80:80
$K exec -i -t dnsutils -- nslookup my-svc
#   ** server can't find my-svc: SERVFAIL
$K exec -i -t dnsutils -- nslookup my-svc.other
#   Name:	my-svc.other.svc.cluster.local   Address: 10.104.170.75
$K logs --namespace=kube-system -l k8s-app=kube-dns --tail=6
#   "A IN my-svc.svc.cluster.local."                    NXDOMAIN      <- the search list (ndots:5) being walked
#   "A IN my-svc.cluster.local."                        NXDOMAIN
#   "A IN my-svc."                                      SERVFAIL      <- finally sent upstream
#   "A IN my-svc.other.default.svc.cluster.local."      NXDOMAIN
#   "A IN my-svc.other.svc.cluster.local."              NOERROR       <- found
```

## Break 4 – Forwarding loop (the systemd-resolved known issue)
A node whose `/etc/resolv.conf` points at a local stub (`127.0.0.53`) makes CoreDNS forward to itself. The same thing, simulated:
```bash
$K -n kube-system get cm coredns -o yaml > /tmp/coredns-backup.yaml
$K -n kube-system get cm coredns -o yaml | sed 's|forward . /etc/resolv.conf|forward . 127.0.0.1|' | $K apply -f -
$K -n kube-system rollout restart deploy coredns
$K -n kube-system get po -l k8s-app=kube-dns          # coredns-...   0/1   CrashLoopBackOff
$K -n kube-system logs <crashing-pod> --previous | grep loop
#   [FATAL] plugin/loop: Loop (127.0.0.1:58014 -> :53) detected for zone ".", see https://coredns.io/plugins/loop#troubleshooting.
#   Query: "HINFO 3201192832411410454.2337031617591476950."
$K apply -f /tmp/coredns-backup.yaml && $K -n kube-system rollout restart deploy coredns
```
On real nodes the fix is the kubelet's `resolvConf: /run/systemd/resolve/resolv.conf`, which kubeadm sets automatically when it detects systemd-resolved.

---

## Useful commands
```bash
kubectl exec -i -t dnsutils -- nslookup <name> ; kubectl exec dnsutils -- dig +search <name>
kubectl -n kube-system logs -l k8s-app=kube-dns -f
kubectl get endpointslice -n kube-system -l kubernetes.io/service-name=kube-dns
kubectl auth can-i list endpointslices.discovery.k8s.io --as=system:serviceaccount:kube-system:coredns
```

## Cleanup
```bash
minikube delete -p dnsdebug-lab
```
