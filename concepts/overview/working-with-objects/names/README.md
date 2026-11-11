# Object Names and IDs – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Name** | Client-given, in `metadata.name`. Unique **per resource type** (per namespace for namespaced types). A Pod and a Deployment can share a name. Two Pods in one namespace can't. |
| **Identity** | API **group** + **resource type** + **namespace** + **name**. The API **version** is *not* part of it: `autoscaling/v1` and `autoscaling/v2` are two views of the same HPA object. |
| **generateName** | A prefix. The server appends a random suffix. Since v1.31 it retries up to 8 times before giving up with HTTP 409. Works with `create`, not with `apply`. |
| **UID** | Server-generated UUID, unique across the whole cluster **and over time**. Deleting and recreating an object with the same name gives a new UID. |
| **Node note** | A Node object represents a physical host. If the host is rebuilt under the same name without recreating the Node, Kubernetes treats it as the old host. |
| **Labels/annotations** | For non-unique, user-provided attributes. See [../labels](../labels/) and [../annotations](../annotations/). |

### The four name constraints

| Rule | Max length | Allowed | Start / end | Example resources |
|---|---|---|---|---|
| **DNS subdomain (RFC 1123)** | 253 | `a-z 0-9 - .` | alphanumeric / alphanumeric | Most resources: ConfigMap, Secret, Pod, Deployment |
| **RFC 1123 label** | 63 | `a-z 0-9 -` (no dots) | see note / alphanumeric | Namespace, container names |
| **RFC 1035 label** | 63 | `a-z 0-9 -` | **alphabetic** / alphanumeric | Service (unless `RelaxedServiceNameValidation` is on) |
| **Path segment** | – | anything except `/`, `%`, and not `.` or `..` | – | RBAC Role/ClusterRole (allows `:` and uppercase) |

## The demo app
[nginx-demo.yaml](nginx-demo.yaml) is the docs' Pod `nginx-demo`, **verbatim** and without a namespace, so it's applied with `-n names-demo`. The other files are numbered labs.

---

## Step 1
```bash
cd concepts/overview/working-with-objects/names
kubectl apply -f 00-namespace.yaml
kubectl apply -f nginx-demo.yaml -n names-demo
```

## Lab 1 – Names are unique per type and namespace
```bash
kubectl create -f nginx-demo.yaml -n names-demo         # Error (AlreadyExists): pods "nginx-demo" already exists
kubectl apply  -f nginx-demo.yaml -n default --dry-run=server   # pod/nginx-demo created - other namespace is fine
```

## Lab 2 – Same name, different kinds (the docs' `myapp-1234`)
```bash
kubectl apply -f 01-same-name-different-kinds.yaml
kubectl get pod,deploy myapp-1234 -n names-demo         # both exist
```

## Lab 3 – The API version is not part of the identity
```bash
kubectl create -f 02-hpa-v2.yaml                        # created via autoscaling/v2
kubectl create -f 03-hpa-v1-same-name.yaml              # via autoscaling/v1 ->
#   Error from server (AlreadyExists): horizontalpodautoscalers.autoscaling "web-hpa" already exists
for v in v1 v2; do
  kubectl get --raw /apis/autoscaling/$v/namespaces/names-demo/horizontalpodautoscalers/web-hpa \
    | jq -c '{apiVersion, uid: .metadata.uid, cpu: (.spec.targetCPUUtilizationPercentage // .spec.metrics[0].resource.target.averageUtilization)}'
done
#   {"apiVersion":"autoscaling/v1","uid":"ccebefd8-...","cpu":80}
#   {"apiVersion":"autoscaling/v2","uid":"ccebefd8-...","cpu":80}     <- same UID, two representations
```

## Lab 4 – generateName
```bash
kubectl create -f 04-generate-name.yaml                 # pod/worker-hcxwv created
kubectl create -f 04-generate-name.yaml                 # pod/worker-lrrnz created - a new one each time
kubectl apply  -f 04-generate-name.yaml                 # error: cannot use generate name with apply
kubectl logs -n names-demo -l '!app' --prefix 2>/dev/null | grep 'my name'   # "my name is worker-xxxxx"
```
Controllers use this all the time: ReplicaSet pods (`web-557577df75-jqrth`) and Job pods are named from `generateName`.

## Lab 5 – Name constraints
Each command is a server dry-run, so nothing is created:
```bash
t(){ printf '%-26s' "$1"; shift; "$@" --dry-run=server -o name 2>&1 | head -c 140; echo; }
t "cm with dots"          kubectl create configmap my.config.v1 -n names-demo
t "cm uppercase"          kubectl create configmap MyConfig -n names-demo
t "cm 254 chars"          kubectl create configmap $(printf 'a%.0s' {1..254}) -n names-demo
t "ns with dot"           kubectl create namespace team.a
t "ns 64 chars"           kubectl create namespace $(printf 'a%.0s' {1..64})
t "ns starts with digit"  kubectl create namespace 1team
t "svc with dot"          kubectl create service clusterip web.v1 --tcp=80 -n names-demo
t "svc starts with digit" kubectl create service clusterip 1web --tcp=80 -n names-demo
t "clusterrole a:B"       kubectl create clusterrole Team:viewer --verb=get --resource=pods
t "clusterrole with %"    kubectl create clusterrole 'team%viewer' --verb=get --resource=pods
kubectl apply -f 05-pod-name-with-dots.yaml --dry-run=server
kubectl run web.v1 --image=nginx -n names-demo --dry-run=server
```
Expected on **v1.37** (minikube):

| Test | Result | Rule |
|---|---|---|
| cm `my.config.v1` | ✅ | DNS subdomain allows dots |
| cm `MyConfig` | ❌ lowercase RFC 1123 subdomain | uppercase not allowed |
| cm, 254 chars | ❌ must be no more than 253 characters | |
| ns `team.a` | ❌ must not contain dots | namespaces are RFC 1123 **labels** |
| ns, 64 chars | ❌ must be no more than 63 characters | |
| ns `1team` | ✅ | the label regex allows a leading digit (the docs say "alphabetic". Check your version.) |
| svc `web.v1` | ❌ must not contain dots | |
| svc `1web` | ✅ | `RelaxedServiceNameValidation` is enabled by default here. With it off, this is ❌ (RFC 1035) |
| clusterrole `Team:viewer` | ✅ | path segment: uppercase and `:` are fine (as in `system:node`) |
| clusterrole `team%viewer` | ❌ may not contain '%' | |
| pod `web.v1.example` | ✅ with a **Warning**: the name is used as the hostname, so a DNS label is recommended | |
| `kubectl run web.v1` | ❌ `spec.containers[0].name … must not contain dots` | kubectl reuses the pod name as the container name, and container names are labels |

## Lab 6 – UIDs
```bash
kubectl get pod nginx-demo -n names-demo -o jsonpath='{.metadata.uid}{"\n"}'
kubectl delete pod nginx-demo -n names-demo
kubectl apply -f nginx-demo.yaml -n names-demo
kubectl get pod nginx-demo -n names-demo -o jsonpath='{.metadata.uid}{"\n"}'     # different UUID
kubectl get pod -n names-demo -l app=myapp -o jsonpath='{.items[0].metadata.ownerReferences[0].uid}{"\n"}'
```
Same name, new UID: it's a different object. Owner references point at a **UID**, so a dependent can never be adopted by mistake by a recreated owner that happens to share the old name. See [../owners-dependents](../owners-dependents/).

---

## Useful commands
```bash
kubectl get <kind> <name> -o jsonpath='{.metadata.uid}'
kubectl get --raw /apis/<group>/<version>/namespaces/<ns>/<resource>/<name>   # see one version's view
kubectl api-resources -o wide                    # group, version, namespaced?, kind
```

## Cleanup
```bash
./cleanup.sh
```
