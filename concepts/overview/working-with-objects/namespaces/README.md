# Namespaces – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Namespace** | Isolates groups of resources inside one cluster. Names must be unique **within** a namespace, not across namespaces. Namespaces can't be nested, and each resource is in at most one. |
| **When to use** | Many users, teams or projects. With a few to tens of users you don't need them. Use **labels**, not namespaces, to tell apart versions of the same app. Split resources between users with **ResourceQuota** per namespace. |
| **Production note** | Avoid the `default` namespace. Create your own. |
| **Initial namespaces** | `default` (start here), `kube-node-lease` (node heartbeat Leases), `kube-public` (readable by **everyone, including unauthenticated clients**, by convention), `kube-system` (system objects). |
| **`kube-` prefix** | Reserved for Kubernetes system namespaces. Don't create your own with it. |
| **Selecting a namespace** | `--namespace` / `-n` per command, or save it in the kubeconfig context with `kubectl config set-context --current --namespace=…`. |
| **DNS** | Each Service gets `<service>.<namespace>.svc.cluster.local`. A bare `<service>` resolves to the one in the **same** namespace, so the same config works in dev, staging and prod. To cross namespaces, use the longer name. Namespace names must therefore be RFC 1123 labels. |
| **TLD warning** | A namespace named like a public TLD (`com`, `dev`, `io`…) makes its Services shadow public DNS names for lookups **without a trailing dot**, from every namespace. Restrict who can create namespaces. |
| **Not namespaced** | Namespaces themselves, Nodes, PersistentVolumes, StorageClasses, ClusterRoles, CRDs… List them with `kubectl api-resources --namespaced=false`. |
| **Automatic label** | The control plane sets the immutable label `kubernetes.io/metadata.name=<name>` on every namespace (stable since 1.22). Handy for NetworkPolicy `namespaceSelector`. |

## The demo app
[00-envs.yaml](00-envs.yaml) creates three namespaces: `development`, `staging` and `production`. [01-db.yaml](01-db.yaml) is a Deployment + Service called `db` with **no namespace** in the file. It's applied unchanged into all three, and each pod answers `db in <namespace>`.
[02-tld-namespace.yaml](02-tld-namespace.yaml) is for the TLD warning: namespace `com` with Service `example`.

---

## Step 1
```bash
cd concepts/overview/working-with-objects/namespaces
kubectl apply -f 00-envs.yaml
for n in development staging production; do kubectl apply -f 01-db.yaml -n $n; done
```

## Lab 1 – Initial namespaces (docs commands)
```bash
kubectl get namespace
#   NAME              STATUS   AGE
#   default           Active   …
#   kube-node-lease   Active   …
#   kube-public       Active   …
#   kube-system       Active   …     (+ development, staging, production and any earlier labs)
kubectl get lease -n kube-node-lease                 # one Lease per node = heartbeats
kubectl get cm -n kube-public                        # cluster-info
```
`kube-public` really is public. Anonymous requests can read `cluster-info`, but not objects in other namespaces:
```bash
curl -sk https://$(minikube ip):8443/api/v1/namespaces/kube-public/configmaps/cluster-info | jq -r .metadata.name
#   cluster-info
curl -sk https://$(minikube ip):8443/api/v1/namespaces/default/configmaps | jq -r .message
#   configmaps is forbidden: User "system:anonymous" cannot list resource "configmaps" ... in the namespace "default"
```

## Lab 2 – Same name in different namespaces
```bash
kubectl get svc db -A                    # three Services called db, one per namespace
kubectl get deploy -n production
```

## Lab 3 – Setting the namespace for a request and as a preference
```bash
kubectl run nginx --image=nginx --namespace=staging          # docs example
kubectl get pods --namespace=staging
kubectl config set-context --current --namespace=staging     # docs example: save the preference
kubectl config view --minify | grep namespace:               #   namespace: staging
kubectl get pods                                             # now lists staging without -n
kubectl config set-context --current --namespace=default     # put it back
```

## Lab 4 – Namespaces and DNS
```bash
kubectl run client -n development --restart=Never --image=busybox:1.36 -- sh -c '
  grep -E "search|ndots" /etc/resolv.conf
  echo "db                            -> $(wget -qO- http://db)"
  echo "db.production                 -> $(wget -qO- http://db.production)"
  echo "db.staging.svc.cluster.local  -> $(wget -qO- http://db.staging.svc.cluster.local)"'
kubectl logs client -n development ; kubectl delete pod client -n development
```
Expected:
```
search development.svc.cluster.local svc.cluster.local cluster.local
options ndots:5
db                            -> db in development     <- short name = own namespace
db.production                 -> db in production
db.staging.svc.cluster.local  -> db in staging         <- FQDN
```
The search list is built from the pod's namespace. That's why a short name stays local.

## Lab 5 – The TLD warning
```bash
kubectl apply -f 02-tld-namespace.yaml
kubectl get svc example -n com -o jsonpath='{.spec.clusterIP}{"\n"}'          # e.g. 10.101.105.205
kubectl run client -n development --restart=Never --image=debian:12-slim -- sh -c '
  echo "example.com   -> $(getent ahostsv4 example.com  | head -1)"
  echo "example.com.  -> $(getent ahostsv4 example.com. | head -1)"'
kubectl logs client -n development ; kubectl delete pod client -n development
```
Expected:
```
example.com   -> 10.101.105.205  STREAM example.com.svc.cluster.local    <- HIJACKED by the Service in namespace "com"
example.com.  -> 172.66.147.243  STREAM example.com                      <- trailing dot = absolute name -> public DNS
```
`example.com` has fewer than 5 dots (`ndots:5`), so the resolver tries the search suffixes first. `example.com` + `.svc.cluster.local` is exactly the Service `example` in namespace `com`.
Note: `getent ahostsv4` is used because the Service has only an IPv4 record. An IPv6 (AAAA) lookup finds no answer there and falls through to public DNS, and busybox `nslookup` doesn't apply the search list the same way.
```bash
kubectl delete -f 02-tld-namespace.yaml
```

## Lab 6 – Namespaced vs cluster-scoped resources
```bash
kubectl api-resources --namespaced=true  | head      # pods, services, deployments, configmaps, ...
kubectl api-resources --namespaced=false | head      # namespaces, nodes, persistentvolumes, clusterroles, ...
kubectl get nodes -n production                      # -n is ignored for cluster-scoped kinds
```

## Lab 7 – The automatic label
```bash
kubectl get ns production --show-labels             # kubernetes.io/metadata.name=production
kubectl label ns production kubernetes.io/metadata.name=prod --overwrite
kubectl get ns production --show-labels             # still =production - the control plane resets it
kubectl get ns -l 'kubernetes.io/metadata.name in (staging,production)'
```

## Lab 8 – `kube-` prefix and deleting a namespace
```bash
kubectl create namespace kube-mine --dry-run=server  # allowed by the API - the prefix is reserved only by convention. Don't do it.
kubectl delete namespace staging
kubectl get ns staging                               # Terminating, then gone
kubectl get all -n staging                           # everything inside was deleted with it
```

---

## Useful commands
```bash
kubectl get ns
kubectl get <kind> -A                     # all namespaces
kubectl config set-context --current --namespace=<ns>
kubectl config view --minify | grep namespace:
kubectl api-resources --namespaced=false
```

## Cleanup
```bash
./cleanup.sh        # resets your kubectl namespace preference and deletes the lab namespaces
```
