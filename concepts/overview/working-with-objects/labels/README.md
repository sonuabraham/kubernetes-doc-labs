# Labels and Selectors – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Label** | A key/value pair on an object, such as `environment: production`. It identifies the object to **users**. The core system gives it no meaning except through selectors. You can add or change labels at any time. Each key appears once per object. |
| **Not unique** | Many objects share labels. Use names and UIDs for uniqueness, and annotations for non-identifying data. |
| **Key syntax** | `[prefix/]name`. **name**: required, ≤ 63 chars, `[a-zA-Z0-9]` at both ends, with `- _ .` allowed in between. **prefix**: optional DNS subdomain, lowercase, ≤ 253 chars. No prefix means the key is private to the user. Automation **must** use a prefix. `kubernetes.io/` and `k8s.io/` are reserved for core components. |
| **Value syntax** | ≤ 63 chars, may be **empty**. Otherwise it must start and end alphanumeric, with `- _ .` allowed in between. |
| **Selector** | The core grouping primitive. Requirements are separated by commas, which means **AND**. There is **no OR** operator, but `in (a, b)` gives OR across values. |
| **Equality-based** | `=`, `==` (synonyms) and `!=`. `!=` also matches objects that **don't have** the key. |
| **Set-based** | `in`, `notin` and existence: `key` and `!key`. `notin` also matches objects without the key. `x=y` is the same as `x in (y)`. |
| **In API objects** | Service and ReplicationController take a **map**, so equality only. Job, Deployment, ReplicaSet and DaemonSet take `matchLabels` + `matchExpressions` (`In`, `NotIn`, `Exists`, `DoesNotExist`), all ANDed. |
| **Overlap** | Selectors of controllers such as ReplicaSets must not overlap within a namespace, or the controllers fight over the same pods. |

## The demo app
The docs examples are copied **verbatim**: [label-demo.yaml](label-demo.yaml), [cuda-test.yaml](cuda-test.yaml), the selector block in [04-set-based-selector.yaml](04-set-based-selector.yaml), the Service map selector in [03-service-selector.yaml](03-service-selector.yaml), and the guestbook label sets in [02-guestbook.yaml](02-guestbook.yaml).
[01-selector-playground.yaml](01-selector-playground.yaml) adds six `pause` pods, `p1`–`p6`, labelled with the docs' example dimensions:

| pod | environment | tier | partition | release |
|---|---|---|---|---|
| p1 | production | frontend | customerA | stable |
| p2 | production | backend | customerB | stable |
| p3 | qa | frontend | customerA | canary |
| p4 | qa | cache | – | canary |
| p5 | dev | backend | customerB | – |
| p6 | production | – | – | – |

---

## Step 1
```bash
cd concepts/overview/working-with-objects/labels
kubectl apply -f 00-namespace.yaml -f 01-selector-playground.yaml -f 02-guestbook.yaml
kubectl apply -f label-demo.yaml -f cuda-test.yaml -n labels-demo
```

## Lab 1 – Look at labels
```bash
kubectl get pod label-demo -n labels-demo --show-labels       # app=nginx,environment=production
kubectl get pods -n labels-demo -L environment,tier,partition,release
```

## Lab 2 – Equality-based selectors
```bash
s(){ printf '%-45s ' "$1"; kubectl get pods -n labels-demo -l "$1" -o name | grep -E 'p[0-9]$' | sed 's#pod/##' | tr '\n' ' '; echo; }
s 'environment = production'
s 'environment==production'
s 'tier != frontend'
s 'environment=production,tier!=frontend'
```
Expected:
```
environment = production                      p1 p2 p6
environment==production                       p1 p2 p6          (= and == are synonyms)
tier != frontend                              p2 p4 p5 p6       (p6 has NO tier key - still matches)
environment=production,tier!=frontend         p2 p6             (comma = AND)
```

## Lab 3 – Set-based selectors
```bash
s 'environment in (production, qa)'
s 'tier notin (frontend, backend)'
s 'partition'
s '!partition'
s 'partition,environment notin (qa)'
s 'partition in (customerA, customerB),environment!=qa'
s 'environment,environment notin (frontend)'
```
Expected:
```
environment in (production, qa)               p1 p2 p3 p4 p6    (OR across values)
tier notin (frontend, backend)                p4 p6             (p6: no tier key -> matches)
partition                                     p1 p2 p3 p5       (key exists)
!partition                                    p4 p6             (key absent)
partition,environment notin (qa)              p1 p2 p5
partition in (customerA, customerB),environment!=qa   p1 p2 p5  (set + equality mixed)
environment,environment notin (frontend)      p1 p2 p3 p4 p5 p6 (the docs' example: has key AND value isn't "frontend")
```

## Lab 4 – Selectors in the REST API (LIST/WATCH)
The docs' query strings, URL-encoded:
```bash
kubectl get --raw "/api/v1/namespaces/labels-demo/pods?labelSelector=environment%3Dproduction,tier%3Dfrontend" | jq -r '.items[].metadata.name'
#   p1
kubectl get --raw "/api/v1/namespaces/labels-demo/pods?labelSelector=environment+in+%28production%2Cqa%29%2Ctier+in+%28frontend%29" | jq -r '.items[].metadata.name'
#   p1 p3
kubectl get pods -n labels-demo -l 'tier=frontend' -w      # WATCH with a selector. In another terminal: kubectl label pod p4 -n labels-demo tier=frontend --overwrite
```
The server does the filtering. That's why the docs call labels "efficient for queries and watches".

## Lab 5 – Using labels effectively (guestbook)
```bash
kubectl get pods -n labels-demo -Lapp -Ltier -Lrole -l 'app in (guestbook, nginx)'
kubectl get pods -n labels-demo -lapp=guestbook,role=replica
```
Expected, matching the docs' output:
```
NAME                             READY  STATUS   APP        TIER      ROLE
guestbook-fe-…  (3 pods)         1/1    Running  guestbook  frontend
guestbook-redis-master-…         1/1    Running  guestbook  backend   master
guestbook-redis-replica-… (2)    1/1    Running  guestbook  backend   replica
label-demo, my-nginx-… (3)       1/1    Running  nginx
---
guestbook-redis-replica-…  (the 2 replicas only)
```

## Lab 6 – Updating labels (docs example)
```bash
kubectl label pods -n labels-demo -l app=nginx tier=fe
#   pod/label-demo labeled, pod/my-nginx-… labeled (×3)
kubectl get pods -n labels-demo -l app=nginx -L tier
kubectl label pod label-demo -n labels-demo tier=web               # error: 'tier' already has a value (fe), and --overwrite is false
kubectl label pod label-demo -n labels-demo tier=web --overwrite
kubectl label pod label-demo -n labels-demo tier-                  # remove a label: key followed by "-"
```
Relabelling a pod **out of** its ReplicaSet's selector orphans it, and the ReplicaSet creates a replacement:
```bash
P=$(kubectl get pod -n labels-demo -l app=nginx,'!environment' -o name | head -1)
kubectl label $P -n labels-demo app=debug --overwrite
kubectl get pods -n labels-demo -L app | grep -E 'my-nginx'        # 4 my-nginx pods: 3 app=nginx + 1 app=debug (orphan, kept for debugging)
```

## Lab 7 – Selectors inside API objects
```bash
kubectl apply -f 03-service-selector.yaml -f 04-set-based-selector.yaml
kubectl get endpointslices -n labels-demo -l kubernetes.io/service-name=redis -o jsonpath='{.items[0].endpoints[*].targetRef.name}{"\n"}'
#   redis-cache-…  redis-cache-…   (the Service map selects component=redis pods)
kubectl get deploy redis-cache -n labels-demo -o jsonpath='{.spec.selector}{"\n"}'
kubectl apply -f 05-template-mismatch.yaml
#   The Deployment "redis-cache-dev" is invalid: spec.template.metadata.labels: Invalid value:
#   {"component":"redis","environment":"dev","tier":"cache"}: `selector` does not match template `labels`
```

## Lab 8 – Selecting nodes (the docs' `cuda-test`)
```bash
kubectl get pod cuda-test -n labels-demo                           # Pending
kubectl get pod cuda-test -n labels-demo -o jsonpath='{.status.conditions[0].message}{"\n"}'
#   0/1 nodes are available: 1 node(s) didn't match Pod's node affinity/selector.
kubectl label node minikube accelerator=nvidia-tesla-p100
kubectl describe pod cuda-test -n labels-demo | tail -2
#   0/1 nodes are available: 1 Insufficient nvidia.com/gpu.            <- the label matches now; there's just no GPU
kubectl label node minikube accelerator-                           # undo
```
`nodeSelector` is an equality-based selector over **node** labels. More in `../../../scheduling-eviction/assign-pod-node`.

## Lab 9 – Label syntax
```bash
for l in 'Tier=Front' 'Bad_Key.v1=ok' 'my.prefix.com/name=x' 'kubernetes.io/x=y' 'empty=' \
         '-bad=x' 'bad-=x' 'ok=-bad' 'My_Prefix/name=x' 'a/b/c=x' "$(printf 'k%.0s' {1..64})=x" "long=$(printf 'a%.0s' {1..64})"; do
  printf '%-24.24s ' "$l"; kubectl label pod p6 -n labels-demo --dry-run=server -- "$l" 2>&1 | head -1 | cut -c1-110; done
```
Expected:

| Label | Result | Why |
|---|---|---|
| `Tier=Front`, `Bad_Key.v1=ok` | ✅ | uppercase and `_ .` are fine in name and value |
| `my.prefix.com/name=x` | ✅ | prefix is a DNS subdomain |
| `kubernetes.io/x=y` | ✅ on a Pod | the prefix is **reserved by convention** (nodes enforce it via NodeRestriction). Don't use it |
| `empty=` | ✅ | values may be empty |
| `-bad`, `bad-` | ❌ name part must … start and end with an alphanumeric character | |
| `ok=-bad` | ❌ invalid label value | |
| `My_Prefix/name` | ❌ prefix part a lowercase RFC 1123 subdomain | the prefix must be lowercase |
| `a/b/c` | ❌ | only one `/` |
| 64-char key or value | ❌ must be no more than 63 | |

Note the `--`: without it, kubectl reads `-bad=x` as a flag.

---

## Useful commands
```bash
kubectl get pods --show-labels
kubectl get pods -L key1,key2                # label columns
kubectl get pods -l 'k in (a,b),!k2'         # quote set-based selectors in the shell
kubectl label <kind> <name> k=v [--overwrite] ;  kubectl label <kind> <name> k-
kubectl get all -l app=guestbook             # selectors work on every resource type
```

## Cleanup
```bash
./cleanup.sh       # removes the node label (if still there) and the namespace
```
