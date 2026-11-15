# Declarative Management of Kubernetes Objects Using Kustomize – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/

> The page is a long series of `cat <<EOF > file … EOF` snippets. [extract-examples.py](extract-examples.py) (not from the docs) turns
> every heredoc into a file, **verbatim**, with one directory per example in [examples/](examples/). Each directory also has the
> `rendered.yaml` that `kubectl kustomize` produced here (kubectl v1.35, Kustomize v5.7.1). Cluster parts run on the default **minikube**.
> Not from the docs: [deprecated-fields/](deprecated-fields/).
>
> **Found:** generated name hashes differ from the page in several places, and the page contradicts itself: the same ConfigMap is
> `example-configmap-1-8mbdf7882g` in the first example and `-g4hk9g2ff8` in the Deployment example. Kustomize v5.7.1 gives
> `-g4hk9g2ff8` for both. Hashes depend on the content, not the generator name (examples 2 and 3 both get `-42cfbf598f`).

## Key ideas (read first)

| Feature | What it does |
|---|---|
| **Generators** | `configMapGenerator` / `secretGenerator` from `files`, `envs` or `literals`. A content-hash suffix means new content gives a new name, which rolls out Pods that reference it. References in the same kustomization are rewritten automatically. |
| **Cross-cutting fields** | `namespace`, `namePrefix`/`nameSuffix`, `labels` (with `includeSelectors`), `commonAnnotations`. |
| **Customizing** | `patches` (strategic merge or JSON 6902), `images` (name/tag rewrite), `replacements` (copy a field from one resource into another). |
| **Bases & overlays** | A base directory plus overlays that reference it under `resources:` and add their own changes. |
| **kubectl** | `kubectl kustomize <dir>` renders. `-k <dir>` with `apply/get/describe/diff/delete`. |

---

## Step 0 – Build the examples
```bash
cd tasks/manage-kubernetes-objects/kustomization
python3 extract-examples.py <path-to>/kustomization.md examples        # already done; output committed
for d in examples/*/; do kubectl kustomize $d > $d/rendered.yaml; done      # example 15: render dev/ and prod/
```
| Dir | Docs section | Result (kinds / names) |
|---|---|---|
| 01 | configMapGenerator `files` | ConfigMap `example-configmap-1-g4hk9g2ff8` (key `application.properties`) |
| 02 | configMapGenerator `envs` | ConfigMap `example-configmap-1-42cfbf598f` (key `FOO`) |
| 03 | configMapGenerator `literals` | ConfigMap `example-configmap-2-42cfbf598f` |
| 04 | generated ConfigMap used by a Deployment | volume `configMap.name: example-configmap-1-g4hk9g2ff8` (rewritten) |
| 05 / 06 | secretGenerator files / literals | Secret `example-secret-1-2kdd8ckcc7` / `example-secret-2-8c5228dkb9` (docs: `-t2kt65hgtb` / `-t52t6g96d8`) |
| 07 | generated Secret used by a Deployment | `secretName` rewritten |
| 08 | generatorOptions | `example-configmap-3`, no suffix, label `type: generated`, annotation `note: generated` |
| 09 | cross-cutting fields | `dev-nginx-deployment-001` in `my-namespace`, label + **selector** `app: bingo`, annotation `oncallPager` |
| 10 | composing | Deployment + Service `my-nginx` |
| 11 | patches (SMP files) | `replicas: 3`, `memory: 512Mi` |
| 12 | patch (JSON 6902) | `replicas: 3` |
| 13 | images | `image: my.image.registry/nginx:1.4.0` |
| 14 | replacements | container command `start --host dev-my-nginx-001` (the prefixed+suffixed Service name) |
| 15 | bases & overlays | `dev/`: `dev-my-nginx` (Service + Deployment), `prod/`: `prod-my-nginx` |
| 16 | apply/view/delete | Deployment `dev-my-nginx`, label/selector `app: my-nginx` |

Inspect any of them, e.g. `cat examples/14-customizing/rendered.yaml`.

## Lab 1 – Apply / view / diff / delete with `-k` (docs, example 16)
```bash
cd examples/16-how-to-apply-view-delete-objects-using-kustomize
kubectl apply -k ./                       # deployment.apps/dev-my-nginx created
kubectl get -k ./                         # dev-my-nginx   0/2   2   0   1s
kubectl describe -k ./ | grep -E '^(Name|Labels|Selector):'
#   Name: dev-my-nginx   Labels: app=my-nginx   Selector: app=my-nginx,run=my-nginx     <- includeSelectors: true
sed -i 's/replicas: 2/replicas: 3/' deployment.yaml; kubectl diff -k ./ | grep -E '^[-+] '
#   -  replicas: 2
#   +  replicas: 3
sed -i 's/replicas: 3/replicas: 2/' deployment.yaml
kubectl delete -k ./                      # deployment.apps "dev-my-nginx" deleted
cd ../..
```

## Lab 2 – One base, two overlays (docs, example 15)
```bash
kubectl apply -k examples/15-bases-and-overlays/dev/
kubectl apply -k examples/15-bases-and-overlays/prod/
kubectl get svc | grep my-nginx            # dev-my-nginx, prod-my-nginx
kubectl delete -k examples/15-bases-and-overlays/dev/ -k examples/15-bases-and-overlays/prod/
#   service "prod-my-nginx" deleted … deployment.apps "prod-my-nginx" deleted      <- only prod!
```
⚠️ With several `-k` flags, kubectl uses only the **last** one, and dev was left running. Use one command per kustomization.

## Lab 3 – The feature table's deprecated fields (not from the docs)
```bash
kubectl kustomize deprecated-fields >/dev/null
#   # Warning: 'bases' is deprecated. Please use 'resources' instead. Run 'kustomize edit fix' …
#   # Warning: 'commonLabels' is deprecated. Please use 'labels' instead. …
#   # Warning: 'patchesStrategicMerge' is deprecated. Please use 'patches' instead. …
```
They still work (labels added, replicas patched to 5). The page's examples already use `resources`, `labels` and `patches`, but its
feature table still lists the old names (and `vars`, which is replaced by `replacements`).

## Useful commands
```bash
kubectl kustomize <dir>
kubectl apply -k <dir> --dry-run=server
kubectl diff -k <dir>
```

## Cleanup
```bash
./cleanup.sh
```
