# Share a Cluster with Namespaces – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/administer-cluster/namespaces/

> Runs on the default **minikube** cluster. The docs' files are copied **verbatim**: [my-namespace.yaml](my-namespace.yaml) (still containing its placeholder), [namespace-dev.json](namespace-dev.json) and [namespace-prod.json](namespace-prod.json). The deployment commands (`snowflake`, `cattle`) are the docs' commands. [stuck-finalizer.yaml](stuck-finalizer.yaml) is extra, for the page's finalizer warning.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **Scope** | Namespaces scope **names** (two `web` Services can coexist) and are the unit for RBAC, ResourceQuota, LimitRange, NetworkPolicy and Pod Security. Nodes, PVs and the like are cluster-scoped. |
| **Names** | Must be an RFC 1123 DNS **label** (lowercase alphanumerics and `-`). Every namespace gets the label `kubernetes.io/metadata.name=<name>`. |
| **`kube-` prefix** | Reserved by convention for the system. It's *recommended* to avoid it, not enforced. |
| **DNS** | `<svc>.<ns>.svc.cluster.local`. A short name like `web` resolves in the **Pod's own** namespace, so the same config works in dev, staging and prod. |
| **Deleting** | Deletes **everything** inside it. `spec.finalizers` must all be cleared first; an unknown finalizer leaves it `Terminating` forever. |

---

## Lab 1 – View and create namespaces
```bash
cd tasks/administer-cluster/namespaces
kubectl get namespaces
#   default  kube-node-lease  kube-public  kube-system   (Active)
kubectl create -f ./my-namespace.yaml          # verbatim: the placeholder isn't a valid name
#   The Namespace "<insert-namespace-name-here>" is invalid: metadata.name: Invalid value: ...
#   a lowercase RFC 1123 label must consist of lower case alphanumeric characters or '-', ...
sed 's/<insert-namespace-name-here>/my-team/' my-namespace.yaml | kubectl create -f -        # namespace/my-team created
kubectl create namespace My_Team              # Invalid value: "My_Team": a lowercase RFC 1123 label must ...
kubectl create namespace kube-mine            # namespace/kube-mine created   <- "avoid" kube-, but it's allowed
kubectl describe namespaces my-team
#   Labels: kubernetes.io/metadata.name=my-team   Status: Active   No resource quota.   No LimitRange resource.
```

## Lab 2 – Subdivide the cluster: development and production
```bash
kubectl create -f namespace-dev.json
kubectl create -f namespace-prod.json
kubectl get namespaces --show-labels
#   development   Active   kubernetes.io/metadata.name=development,name=development
#   production    Active   kubernetes.io/metadata.name=production,name=production
kubectl create deployment snowflake --image=registry.k8s.io/serve_hostname -n=development --replicas=2
kubectl get deployment -n=development                 # snowflake   2/2
kubectl get pods -l app=snowflake -n=development      # snowflake-87b568444-d6sld, -rcsx4   Running
kubectl get deployment -n=production                  # No resources found  <- separate scope
kubectl create deployment cattle --image=registry.k8s.io/serve_hostname -n=production
kubectl scale deployment cattle --replicas=5 -n=production
kubectl get deployment -n=production                  # cattle   5/5
```

## Lab 3 (extra) – Namespaces and DNS
The same Service name in both namespaces:
```bash
kubectl expose deployment snowflake --name=web --port=80 --target-port=9376 -n development
kubectl expose deployment cattle    --name=web --port=80 --target-port=9376 -n production
kubectl run dnsclient -n development --image=busybox:1.36 --restart=Never -- sh -c \
  'nslookup web; nslookup web.production; wget -qO- http://web; echo; wget -qO- http://web.production'
kubectl logs dnsclient -n development
#   web            -> 10.101.230.130     (development's web)
#   web.production -> 10.96.89.14        (production's web)
#   snowflake-87b568444-d6sld            <- "web" answered by development
#   cattle-c49b5584f-nxgvx               <- "web.production" crosses namespaces
```

## Lab 4 (extra) – The finalizer warning
```bash
kubectl create -f stuck-finalizer.yaml          # spec.finalizers: [example.com/nobody-handles-this]
kubectl delete namespace stuck-demo --wait=false
kubectl get namespace stuck-demo                # stuck-demo   Terminating   (forever)
# remove the finalizer through the namespace's "finalize" subresource:
kubectl get namespace stuck-demo -o json | jq '.spec.finalizers=[]' | kubectl replace --raw /api/v1/namespaces/stuck-demo/finalize -f -
kubectl get namespace stuck-demo                # NotFound - gone
```

## Lab 5 – Delete namespaces
```bash
kubectl delete namespaces development production my-team kube-mine     # takes their Deployments, Pods and Services with them
```

---

## Useful commands
```bash
kubectl get ns --show-labels
kubectl config set-context --current --namespace=<ns>
kubectl api-resources --namespaced=false        # what is NOT namespaced
```

## Cleanup
Lab 5 already deleted everything this lab created.
