# Update API Objects in Place Using kubectl patch – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/manage-kubernetes-objects/update-api-object-kubectl-patch/

> Runs on the default **minikube** cluster, `default` namespace as in the docs.
> Files (docs, **verbatim**): [deployment-patch.yaml](deployment-patch.yaml), [deployment-retainkeys.yaml](deployment-retainkeys.yaml),
> [deployment.yaml](deployment.yaml), and the patch files [patch-file.yaml](patch-file.yaml), [patch-file.json](patch-file.json),
> [patch-file-tolerations.yaml](patch-file-tolerations.yaml), [patch-file-2.yaml](patch-file-2.yaml),
> [patch-file-no-retainkeys.yaml](patch-file-no-retainkeys.yaml), [patch-file-retainkeys.yaml](patch-file-retainkeys.yaml).
>
> **Found:** one of the docs' "equivalent" forms, `--patch 'spec:\n template:\n …'`, does **not** work in bash. Inside single quotes `\n`
> stays a literal backslash-n: `yaml: mapping values are not allowed in this context`. Use `$'…'`, `printf`, or a file.

## Key ideas (read first)

| `--type` | Lists | Notes |
|---|---|---|
| `strategic` (default) | per field: **merge** by key (`containers` by `name`), or **replace** (`tolerations`: no `patchStrategy`) | built-in types only, not custom resources |
| `merge` (RFC 7386) | always replaced as a whole | |
| `json` (RFC 6902) | explicit operations (`add`, `remove`, `replace`, `test`…) on paths | |
| `$retainKeys` | strategic-patch directive: keep only the listed keys of a `retainKeys` field (`strategy`) | `kubectl apply` adds it for you |
| `--subresource` | patch `scale`, `status` or `resize` only; a 404 if the resource has no such subresource | |

---

## Step 0
```bash
cd tasks/manage-kubernetes-objects/update-api-object-kubectl-patch
c(){ kubectl get deploy patch-demo -o json | jq -c '{containers:[.spec.template.spec.containers[]|.name], tolerations:[.spec.template.spec.tolerations[]?|.key]}'; }
kubectl apply -f deployment-patch.yaml; c
#   {"containers":["patch-demo-ctr"],"tolerations":["dedicated"]}
```

## Lab 1 – Strategic merge patch: merged vs replaced lists (docs)
```bash
kubectl patch deployment patch-demo --patch-file patch-file.yaml; c
#   {"containers":["patch-demo-ctr-2","patch-demo-ctr"],…}        <- containers MERGED (patchStrategy merge, key name)
kubectl get pods -l app=nginx                                     # new Pods, 2/2
kubectl patch deployment patch-demo --patch-file patch-file-tolerations.yaml; c
#   {…,"tolerations":["disktype"]}                                <- tolerations REPLACED (no patchStrategy); "dedicated" is gone
```

## Lab 2 – JSON merge patch (docs)
```bash
kubectl patch deployment patch-demo --type merge --patch-file patch-file-2.yaml; c
#   {"containers":["patch-demo-ctr-3"],…}                         <- the whole list replaced by the one in the patch
```

## Lab 3 – retainKeys (docs)
```bash
kubectl apply -f deployment-retainkeys.yaml
kubectl patch deployment retainkeys-demo --type strategic --patch-file patch-file-no-retainkeys.yaml
#   The Deployment "retainkeys-demo" is invalid: spec.strategy.rollingUpdate: Forbidden: may not be specified when strategy `type` is 'Recreate'
kubectl patch deployment retainkeys-demo --type strategic --patch-file patch-file-retainkeys.yaml
kubectl get deploy retainkeys-demo -o jsonpath='{.spec.strategy}'          # {"type":"Recreate"}
```
`kubectl apply` computes `$retainKeys` itself. That's why in [declarative-config](../declarative-config/) a file with only
`type: Recreate` applied cleanly, while this hand-written patch fails.

## Lab 4 – Alternate forms (docs)
```bash
kubectl apply -f deployment-patch.yaml        # fresh object; each form below as a server-side dry run
kubectl patch deployment patch-demo --patch-file patch-file.yaml --dry-run=server -o json | jq -c '[.spec.template.spec.containers[].name]'
kubectl patch deployment patch-demo --patch-file patch-file.json --dry-run=server -o json | jq -c '[.spec.template.spec.containers[].name]'
kubectl patch deployment patch-demo --patch '{"spec": {"template": {"spec": {"containers": [{"name": "patch-demo-ctr-2","image": "redis"}]}}}}' --dry-run=server -o name
#   all: ["patch-demo-ctr-2","patch-demo-ctr"]
kubectl patch deployment patch-demo --patch 'spec:\n template:\n  spec:\n   containers:\n   - name: patch-demo-ctr-2\n     image: redis'
#   error: unable to parse "spec:\\n template:…": yaml: mapping values are not allowed in this context      <- the docs' form, in bash
kubectl patch deployment patch-demo --patch "$(printf 'spec:\n template:\n  spec:\n   containers:\n   - name: patch-demo-ctr-2\n     image: redis')" --dry-run=server -o json | jq -c '[.spec.template.spec.containers[].name]'
#   ["patch-demo-ctr-2","patch-demo-ctr"]
```

## Lab 5 – `--subresource` (docs + extras)
```bash
kubectl apply -f deployment.yaml
kubectl patch deployment nginx-deployment --subresource='scale' --type='merge' -p '{"spec":{"replicas":3}}'
#   scale.autoscaling/nginx-deployment patched
kubectl get deployment nginx-deployment -o jsonpath='spec={.spec.replicas} status={.status.readyReplicas}'      # spec=3 status=3
kubectl get deployment nginx-deployment --subresource=scale -o json | jq -c '{kind, spec, status}'
#   {"kind":"Scale","spec":{"replicas":3},"status":{"replicas":3,"selector":"app=nginx"}}
kubectl patch pod <a-nginx-pod> --subresource=scale --type=merge -p '{"spec":{"replicas":2}}'
#   Error from server (NotFound): the server could not find the requested resource         <- Pods have no scale subresource
kubectl patch deployment nginx-deployment --subresource=status --type=merge -p '{"status":{"observedGeneration":99}}'
#   deployment.apps/nginx-deployment patched
kubectl get deployment nginx-deployment -o jsonpath='{.status.observedGeneration}'       # 2   <- the controller overwrote it at once
```

## Lab 6 – Custom resources: no strategic merge (docs note)
```bash
kubectl patch volumesnapshotclass csi-hostpath-snapclass -p '{"metadata":{"labels":{"demo":"x"}}}' --dry-run=server
#   error: application/strategic-merge-patch+json is not supported by snapshot.storage.k8s.io/v1, Kind=VolumeSnapshotClass: … accepted media
#   types include: application/json-patch+json, application/merge-patch+json, application/apply-patch+yaml
kubectl patch volumesnapshotclass csi-hostpath-snapclass --type merge -p '{"metadata":{"labels":{"demo":"x"}}}' --dry-run=server     # ok
```
(The VolumeSnapshotClass CRD comes from minikube's `volumesnapshots` addon.)

## Useful commands
```bash
kubectl get --raw /openapi/v2 | jq -c '.definitions["io.k8s.api.core.v1.PodSpec"].properties.containers | {"x-kubernetes-patch-strategy", "x-kubernetes-patch-merge-key"}'
#   {"x-kubernetes-patch-strategy":"merge","x-kubernetes-patch-merge-key":"name"}      (tolerations: null = replace)
kubectl patch <obj> --type json -p '[{"op":"remove","path":"/spec/template/spec/tolerations"}]'
```

## Cleanup
```bash
./cleanup.sh
```
