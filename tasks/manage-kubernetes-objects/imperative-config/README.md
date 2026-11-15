# Imperative Management of Kubernetes Objects Using Configuration Files – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/manage-kubernetes-objects/imperative-config/

> Runs on the default **minikube** cluster in namespace `imp-cfg`. Not from the docs (the page has no manifests): [web.yaml](web.yaml),
> [generated-cm.yaml](generated-cm.yaml), [docs-selector.yaml](docs-selector.yaml) (the docs' selector snippet in a minimal Deployment).
>
> **Docs bug (here and on [declarative-config](../declarative-config/)):** the recommended selector label
> `controller-selector: "apps/v1/deployment/nginx"` is **invalid**: label values may not contain `/`. Use e.g. `apps.v1.deployment.nginx`.

## Key ideas (read first)

| Command | Behaviour |
|---|---|
| `kubectl create -f` | create; fails if the object exists |
| `kubectl replace -f` | **full replacement**: everything not in the file is dropped, including changes by other writers (scale, HPA, annotations) |
| `kubectl delete -f` | delete by the name in the file; can't work with `generateName` |
| `kubectl get -f … -o yaml` | view |
| `create --edit -f` | tweak a (remote) file before creating |

---

## Step 0
```bash
cd tasks/manage-kubernetes-objects/imperative-config
kubectl create namespace imp-cfg
kubectl create -f docs-selector.yaml
#   The Deployment "nginx" is invalid: * spec.selector.matchLabels: Invalid value: "apps/v1/deployment/nginx": a valid label must be an
#   empty string or consist of alphanumeric characters, '-', '_' or '.', …                       <- the docs' snippet
```

## Lab 1 – Create, change elsewhere, replace (docs' "Limitations")
```bash
kubectl create -f web.yaml                            # Deployment (replicas 1) + NodePort Service
kubectl scale deploy web -n imp-cfg --replicas=3      # "another source updates the object"
kubectl annotate deploy web -n imp-cfg note=by-hand
kubectl replace -f web.yaml
kubectl get -f web.yaml -o jsonpath='{range .items[*]}{.kind}: replicas={.spec.replicas} nodePort={.spec.ports[0].nodePort} note={.metadata.annotations.note} clusterIP={.spec.clusterIP}{"\n"}{end}'
#   Deployment: replicas=1 note=                      <- the scale and the annotation are LOST
#   Service: nodePort=31001 clusterIP=10.97.86.162    <- kept: the API server re-fills allocated fields left empty on replace
```
The page's warning about Services is about fields set by *other parties* (for example `externalIPs`, or `status.loadBalancer` written by
a cloud controller). Server-allocated `clusterIP`/`nodePort` survive.

## Lab 2 – `generateName` and `delete -f` (docs note)
```bash
kubectl create -f generated-cm.yaml; kubectl create -f generated-cm.yaml
kubectl get cm -n imp-cfg -l purpose=generate-demo -o name       # job-config-d62hx, job-config-zztrq (two objects!)
kubectl delete -f generated-cm.yaml
#   error: error when deleting "generated-cm.yaml": resource name may not be empty
kubectl delete cm -n imp-cfg -l purpose=generate-demo            # the docs' alternative: by label
```

## Lab 3 – Edit before creating (docs)
```bash
kubectl create -n imp-cfg --edit -f web.yaml          # opens $EDITOR. Scripted, on a renamed copy of the Deployment:
EDITOR="sed -i s/replicas:\ 1/replicas:\ 2/" kubectl create -n imp-cfg --edit -f <(sed 's/name: web,/name: web-edited,/' web.yaml | sed -n '/^---/q;p')
kubectl get deploy web-edited -n imp-cfg -o jsonpath='{.spec.replicas}'      # 2
```
Without `-n imp-cfg` the edited object is refused: `the namespace from the provided object "imp-cfg" does not match the namespace "default"`.

## Lab 4 – Migrating from imperative commands (docs)
```bash
kubectl create deployment cmd-made -n imp-cfg --image=nginx:1.27
kubectl get deployment/cmd-made -n imp-cfg -o yaml | sed '/^status:/,$d' > deployment_cmd-made.yaml     # export, drop status
sed -i 's/replicas: 1/replicas: 2/' deployment_cmd-made.yaml
kubectl replace -f deployment_cmd-made.yaml          # deployment.apps/cmd-made replaced
kubectl replace -f deployment_cmd-made.yaml
#   Error from server (Conflict): … Operation cannot be fulfilled on deployments.apps "cmd-made": the object has been modified;
```
The exported file still contains `metadata.resourceVersion`, so the *second* replace (with an older version than the live one) is
refused. Remove `resourceVersion` and `uid` from the file once, and `replace` works every time after that.

## Useful commands
```bash
kubectl get -f <file> -o yaml
kubectl replace -f <file> --dry-run=server
kubectl replace --force -f <file>        # delete + recreate (for immutable field changes)
```

## Cleanup
```bash
./cleanup.sh
```
