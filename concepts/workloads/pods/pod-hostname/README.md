# Pod Hostname – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/workloads/pods/pod-hostname/

## Key ideas (read first)

| Setting | Hostname inside the Pod | FQDN inside the Pod | Cluster DNS record |
|---|---|---|---|
| default | `metadata.name` | `metadata.name` | – |
| `hostname: foo` + `subdomain: bar` (namespace `my-namespace`) | `foo` | `foo.bar.my-namespace.svc.<cluster-domain>` | **A/AAAA record** if a **headless Service named `bar`** exists |
| … + `setHostnameAsFQDN: true` (stable since 1.22) | the **FQDN** | the FQDN | same |
| `hostnameOverride: x` | `x` | `x` | **not** affected; records still come from hostname/subdomain |

| Rule | Meaning |
|---|---|
| **64 characters** | The kernel hostname (`utsname.nodename`) holds 64 characters. With `setHostnameAsFQDN`, an FQDN longer than that keeps the Pod in `ContainerCreating` ("Failed to construct FQDN…"). |
| **hostnameOverride** | ≤ 64 characters, a DNS subdomain. **Can't** be combined with `hostNetwork` or `setHostnameAsFQDN` (the API rejects it). |

## The demo app
The docs examples are **verbatim**: [busybox-1.yaml](busybox-1.yaml) and [busybox-2-hostname-override.yaml](busybox-2-hostname-override.yaml). Namespace **`my-namespace`**, as in the docs text. Extra: [01-hostname-subdomain.yaml](01-hostname-subdomain.yaml) (the docs' foo/bar example plus a headless Service `bar`), [02-fqdn-too-long.yaml](02-fqdn-too-long.yaml), [03-override-with-hostnetwork.yaml](03-override-with-hostnetwork.yaml).

---

## Lab 1 – All four flavours side by side
```bash
cd concepts/workloads/pods/pod-hostname
kubectl apply -f 00-namespace.yaml
kubectl apply -f busybox-1.yaml -f busybox-2-hostname-override.yaml -n my-namespace
kubectl apply -f 01-hostname-subdomain.yaml ; sleep 15
for p in busybox-1 busybox-2-busybox-example-domain foo-pod foo-fqdn; do
  printf '%-34s hostname=%-45s fqdn=%s\n' $p "$(kubectl exec $p -n my-namespace -- hostname)" "$(kubectl exec $p -n my-namespace -- hostname -f)"; done
```
Expected:
```
busybox-1                          hostname=busybox-1                                    fqdn=busybox-1
busybox-2-busybox-example-domain   hostname=busybox-2.busybox.example.domain             fqdn=busybox-2.busybox.example.domain
foo-pod                            hostname=foo                                          fqdn=foo.bar.my-namespace.svc.cluster.local
foo-fqdn                           hostname=foo-fqdn.bar.my-namespace.svc.cluster.local  fqdn=foo-fqdn.bar.my-namespace.svc.cluster.local
```

## Lab 2 – hostname + subdomain create DNS records; hostnameOverride doesn't
```bash
kubectl exec busybox-1 -n my-namespace -- nslookup foo.bar.my-namespace.svc.cluster.local
#   Address 1: 10.244.0.186 foo.bar.my-namespace.svc.cluster.local     <- thanks to the headless Service "bar"
kubectl exec busybox-1 -n my-namespace -- nslookup busybox-2.busybox.example.domain
#   can't resolve                                                       <- hostnameOverride is only the Pod's own view
```
Delete the Service `bar` and the `foo.bar…` lookup fails too. The subdomain needs a matching headless Service.

## Lab 3 – The 64-character limit
```bash
kubectl apply -f 02-fqdn-too-long.yaml ; sleep 10
kubectl get pod this-pod-name-is-quite-long-on-purpose -n my-namespace        # ContainerCreating (forever)
kubectl get events -n my-namespace --field-selector involvedObject.name=this-pod-name-is-quite-long-on-purpose -o custom-columns=M:.message | tail -1
#   Failed to create pod sandbox: failed to construct FQDN from pod hostname and cluster domain, FQDN
#   this-pod-name-is-quite-long-on-purpose.and-the-subdomain-is-long-too.my-namespace.svc.cluster.local is too long (64 characters is the max, ...)
```

## Lab 4 – hostnameOverride + hostNetwork is rejected
```bash
kubectl apply -f 03-override-with-hostnetwork.yaml
#   The Pod "override-hostnet" is invalid: spec.hostnameOverride: Forbidden: may not be specified when hostNetwork is true
```

---

## Useful commands
```bash
kubectl exec <pod> -- hostname ; kubectl exec <pod> -- hostname -f
kubectl explain pod.spec.hostname ; kubectl explain pod.spec.hostnameOverride
```
DNS for Pods and Services in depth: `../../../services-networking/dns-pod-service`.

## Cleanup
```bash
./cleanup.sh
```
