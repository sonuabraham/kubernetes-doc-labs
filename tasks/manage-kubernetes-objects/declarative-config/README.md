# Declarative Management of Kubernetes Objects Using Configuration Files – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/manage-kubernetes-objects/declarative-config/

> Runs on the default **minikube** cluster, `default` namespace as in the docs. The docs' URLs are replaced by local copies:
> [simple_deployment.yaml](simple_deployment.yaml), [update_deployment.yaml](update_deployment.yaml) (**verbatim**).
> Not from the docs: [merge-demo/](merge-demo/) (the docs' list-merge example as a real Deployment), [prune-demo/](prune-demo/),
> [defaults-demo/](defaults-demo/), [ownership-demo/](ownership-demo/).
>
> **Found on 1.37:** (1) the page's "strategy `Recreate` → ERROR!" example no longer fails: `kubectl apply` clears the defaulted
> `rollingUpdate` by itself (`retainKeys` patch strategy). (2) The migration recipe `kubectl get -o yaml > file; kubectl replace --save-config`
> can hit a **Conflict** on a fresh Deployment, and it stores `status` and a stale `resourceVersion` in the annotation unless you strip them.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **`kubectl apply`** | Client-side apply: computes a patch from three inputs, (1) the file, (2) the live object, (3) the `kubectl.kubernetes.io/last-applied-configuration` annotation. |
| **Delete vs keep** | Fields in the *annotation* but not in the file are **cleared**. Fields set by others (scale, controllers, defaults) and never in the annotation are **kept**. |
| **Merge by type** | primitive → replace. map → merge per key. list of primitives (`args`) → replace whole list. list of maps with a `patchMergeKey` (`containers` by `name`) → merge per element. |
| **Pruning** | `--prune` with `--prune-allowlist` + selector (old, alpha), or `KUBECTL_APPLYSET=true … --applyset=<parent>` (alpha): delete what you removed from the directory. `kubectl delete -f` is still the recommended way. |
| **Don't mix** | `create`/`replace` don't maintain the annotation (except `--save-config`). |

---

## Step 0
```bash
cd tasks/manage-kubernetes-objects/declarative-config
```

## Lab 1 – Create (docs)
```bash
kubectl diff -f simple_deployment.yaml          # full object with "+" lines; exit code 1 = differences
kubectl apply -f simple_deployment.yaml
kubectl get -f simple_deployment.yaml -o jsonpath='{.metadata.annotations.kubectl\.kubernetes\.io/last-applied-configuration}' | jq -c .
#   {"apiVersion":"apps/v1","kind":"Deployment","metadata":{"annotations":{},"name":"nginx-deployment","namespace":"default"},
#    "spec":{"minReadySeconds":5,"selector":{…},"template":{…"image":"nginx:1.14.2"…}}}
```

## Lab 2 – Update, with an imperative change in between (docs)
```bash
kubectl scale deployment/nginx-deployment --replicas=2
kubectl diff -f update_deployment.yaml | grep -E '^[-+] '
#   -  minReadySeconds: 5
#   -      - image: nginx:1.14.2
#   +      - image: nginx:1.16.1          <- no replicas line: apply won't touch it
kubectl apply -f update_deployment.yaml
kubectl get -f update_deployment.yaml -o json | jq -c '{replicas:.spec.replicas, minReadySeconds:.spec.minReadySeconds, image:.spec.template.spec.containers[0].image}'
#   {"replicas":2,"minReadySeconds":null,"image":"nginx:1.16.1"}
```
All five bullet points of the docs hold: replicas kept, image updated, `minReadySeconds` cleared, and the annotation updated
(with no replicas, minReadySeconds gone).

## Lab 3 – How lists merge (the docs' example, for real)
```bash
names(){ kubectl get deploy merge-demo -o json | jq -c '[.spec.template.spec.containers[] | {name, args, env:(.env|length? // 0)}]'; }
kubectl apply -f merge-demo/v1.yaml                                 # nginx, helper-a, helper-b
kubectl patch deploy merge-demo --type=strategic -p '{"spec":{"template":{"spec":{"containers":[
  {"name":"nginx-helper-b","env":[{"name":"LIVE","value":"edit"}]},{"name":"nginx-helper-d","image":"busybox:1.36","args":["sleep","3600"]}]}}}}'
kubectl apply -f merge-demo/v2.yaml                                 # nginx, helper-b, helper-c
names
#   [{"name":"nginx"…},{"name":"nginx-helper-b","args":["sleep","3600"],"env":1},{"name":"nginx-helper-d"…},{"name":"nginx-helper-c"…}]
```
| Container | Docs' rule | Result |
|---|---|---|
| helper-a | in annotation, not in file | deleted |
| helper-b | live-only `env` (docs use `args`) | **kept** (merged by `name`) |
| helper-c | new in file | added |
| helper-d | live-only, never in the annotation | kept |
```bash
kubectl patch deploy merge-demo --type=strategic -p '{"spec":{"template":{"spec":{"containers":[{"name":"nginx-helper-c","args":["sleep","9999","extra"]}]}}}}'
kubectl apply -f merge-demo/v2.yaml; names       # helper-c args back to ["sleep","3600"]: a primitive list is replaced as a whole
```

## Lab 4 – Pruning (docs, both modes)
```bash
kubectl apply -f prune-demo/app/ -l app=prune-demo --prune --prune-allowlist=core/v1/ConfigMap      # cm-one/two/three created
mv prune-demo/app/cm-three.yaml prune-demo/
kubectl apply -f prune-demo/app/ -l app=prune-demo --prune --prune-allowlist=core/v1/ConfigMap
#   configmap/cm-three pruned
mv prune-demo/cm-three.yaml prune-demo/app/

KUBECTL_APPLYSET=true kubectl apply -f prune-demo/app/ --prune --applyset=prune-demo-set -n default
kubectl get secret prune-demo-set -o json | jq -c '{labels:.metadata.labels, ann:.metadata.annotations}'
#   {"labels":{"applyset.kubernetes.io/id":"applyset-PRQz…-v1"},
#    "ann":{"applyset.kubernetes.io/contains-group-kinds":"ConfigMap","applyset.kubernetes.io/tooling":"kubectl/v1.35.10",…}}
kubectl get cm cm-one -o jsonpath='{.metadata.labels}'     # {…"applyset.kubernetes.io/part-of":"applyset-PRQz…-v1"}
mv prune-demo/app/cm-two.yaml prune-demo/
KUBECTL_APPLYSET=true kubectl apply -f prune-demo/app/ --prune --applyset=prune-demo-set -n default
#   configmap/cm-two pruned
mv prune-demo/cm-two.yaml prune-demo/app/
```

## Lab 5 – Defaulted fields (docs' strategy example)
```bash
kubectl apply -f update_deployment.yaml
kubectl get deploy nginx-deployment -o jsonpath='{.spec.strategy}'
#   {"rollingUpdate":{"maxSurge":"25%","maxUnavailable":"25%"},"type":"RollingUpdate"}     <- defaulted by the server
kubectl apply -f defaults-demo/recreate.yaml                    # only type: Recreate
#   deployment.apps/nginx-deployment configured                  <- the docs say this fails …
kubectl get deploy nginx-deployment -o jsonpath='{.spec.strategy}'     # {"type":"Recreate"}   … but rollingUpdate was cleared
kubectl patch deploy nginx-deployment --type=merge -p '{"spec":{"strategy":{"type":"Recreate","rollingUpdate":{"maxSurge":1}}}}'
#   … spec.strategy.rollingUpdate: Forbidden: may not be specified when strategy `type` is 'Recreate'     <- the error the docs describe
```
The docs' general fix still works and is shown in [defaults-demo/recreate-null.yaml](defaults-demo/recreate-null.yaml): set the
field to `null` to clear it or re-default it. Their advice to always write selectors and the rollout strategy explicitly in the file is still good.

## Lab 6 – Handing a field to an imperative writer (docs)
```bash
r(){ kubectl get deploy owner-demo -o jsonpath='{.spec.replicas}'; echo; }
kubectl apply -f ownership-demo/with-replicas.yaml; kubectl scale deploy owner-demo --replicas=5; r       # 5
kubectl apply -f ownership-demo/without-replicas.yaml; r
#   1      <- only removed from the FILE: apply saw it in the annotation and cleared it (back to the default)
kubectl apply -f ownership-demo/with-replicas.yaml; kubectl scale deploy owner-demo --replicas=5
kubectl apply set-last-applied -f ownership-demo/without-replicas.yaml       # also remove it from the annotation
kubectl apply -f ownership-demo/without-replicas.yaml; r                     # 5   <- kept
```

## Lab 7 – Migrating from imperative commands (docs)
```bash
kubectl create deployment imp-web --image=nginx:1.27          # no last-applied annotation
kubectl get deployment/imp-web -o yaml > deployment_imp-web.yaml
kubectl replace --save-config -f deployment_imp-web.yaml
#   Error from server (Conflict): … the object has been modified; please apply your changes to the latest version …
```
The export carried a `resourceVersion`, and the Deployment controller updated the status a moment later. Wait for
`kubectl rollout status`, export again, and `replace` works. The annotation then contains `status` and the old `resourceVersion`
too. Better: strip `metadata.resourceVersion/uid/creationTimestamp/generation` and `status` before `replace --save-config`.
## Lab 8 – Selectors (docs' warning)
```bash
sed 's/app: nginx/app: nginx-v2/g' update_deployment.yaml | kubectl apply -f -
#   … spec.selector: Invalid value: {"matchLabels":{"app":"nginx-v2"}}: field is immutable      <- docs: don't change selectors
```
The page's recommended selector label `controller-selector: "apps/v1/deployment/nginx"` is itself invalid: label values can't
contain `/`. See [../imperative-config/docs-selector.yaml](../imperative-config/docs-selector.yaml) and use e.g. `apps.v1.deployment.nginx`.

## Useful commands
```bash
kubectl apply view-last-applied deploy/<name>
kubectl apply set-last-applied -f <file>
kubectl diff -f <dir> -R
kubectl get <obj> -o yaml --show-managed-fields     # server-side ownership (see server-side apply)
```

## Cleanup
```bash
./cleanup.sh
```
