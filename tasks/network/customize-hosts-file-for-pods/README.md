# Adding entries to Pod /etc/hosts with HostAliases – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/network/customize-hosts-file-for-pods/

> Runs on the default **minikube** cluster, `default` namespace. Files: [hostaliases-pod.yaml](hostaliases-pod.yaml) (docs, **verbatim**),
> [hosts-extras.yaml](hosts-extras.yaml) (not from the docs: `hostname`/`subdomain` and `hostNetwork` Pods with an alias).
>
> Everything on the page matched. Two extras: with `hostNetwork: true` the kubelet starts from the **node's** hosts file (header
> `(host network)`, minikube's own entries), and a manual edit really is gone after a container restart (Lab 3).

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| Kubelet-managed `/etc/hosts` | bind-mounted per Pod: boilerplate + the Pod's IP and hostname (FQDN if `subdomain` is set) |
| `spec.hostAliases` | extra `ip → hostnames` lines appended under `# Entries added by HostAliases.` |
| Use it for | names DNS can't give you (legacy hosts, tests); prefer DNS / Services otherwise |
| Manual edits | lost when the container restarts |

---

## Lab 1 – Default hosts file (docs)
```bash
cd tasks/network/customize-hosts-file-for-pods
kubectl run nginx --image nginx
kubectl exec nginx -- cat /etc/hosts
#   # Kubernetes-managed hosts file.
#   127.0.0.1   localhost
#   ::1         localhost ip6-localhost ip6-loopback
#   fe00::0     ip6-localnet / ip6-mcastprefix,  fe00::1 ip6-allnodes,  fe00::2 ip6-allrouters
#   10.244.0.22 nginx
```

## Lab 2 – hostAliases (docs + extras)
```bash
kubectl apply -f hostaliases-pod.yaml
kubectl logs hostaliases-pod
#   … 10.244.0.23  hostaliases-pod
#
#   # Entries added by HostAliases.
#   127.0.0.1   foo.local   bar.local
#   10.1.2.3    foo.remote  bar.remote
kubectl apply -f hosts-extras.yaml
kubectl logs hosts-subdomain
#   10.244.0.24  web-0.demo.default.svc.cluster.local  web-0      <- hostname + subdomain → FQDN line
#   # Entries added by HostAliases.
#   10.1.2.3     foo.remote
kubectl logs hosts-hostnetwork
#   # Kubernetes-managed hosts file (host network).
#   … 192.168.58.2 minikube / 192.168.58.1 host.minikube.internal / 192.168.58.2 control-plane.minikube.internal   <- from the node
#   # Entries added by HostAliases.
#   10.1.2.3     foo.remote
```

## Lab 3 – Manual edits don't survive (docs caution)
```bash
kubectl exec nginx -- sh -c 'echo "1.1.1.1 manual.entry" >> /etc/hosts; grep -c manual /etc/hosts; mount | grep hosts'
#   1
#   /dev/nvme0n1p5 on /etc/hosts type ext4 (rw,…)       <- a bind mount from the kubelet's Pod directory
kubectl exec nginx -- kill 1                            # container restarts (RESTARTS 1)
kubectl exec nginx -- grep -c manual /etc/hosts         # 0
```

## Cleanup
```bash
./cleanup.sh
```
