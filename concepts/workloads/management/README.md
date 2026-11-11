# Managing Workloads – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/workloads/management/

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Group related objects** | Put a Service and a Deployment in one file (`---` separated), Service **first**, so the scheduler can spread the Deployment's pods. Or keep them in a directory. |
| **URLs and directories** | `kubectl apply -f <url|file|dir>`. `-R/--recursive` descends into sub-directories, and works for get/delete/describe/rollout too. |
| **Bulk operations** | `kubectl delete -f <file>`, `kubectl delete deploy,svc -l app=nginx`, and chaining: `kubectl get $(kubectl create -f dir/ -o name | grep service/)`. |
| **External tools** | Helm (packaged charts) and Kustomize (`kubectl apply -k`). |
| **Updates without outage** | Change the Deployment's image, and the rolling update does the rest. `kubectl rollout status --timeout` / `--watch=false`. |
| **Canary** | Two Deployments that differ only in a `track` label (stable/canary), plus one Service selecting the common labels. Traffic splits by replica count. |
| **Annotations** | Non-identifying metadata: `kubectl annotate`. |
| **Scaling** | `kubectl scale`, `kubectl autoscale` (HPA), or a patch on the `scale` subresource. |
| **In-place updates** | `kubectl apply` (3-way merge), `kubectl edit`, `kubectl patch` (strategic / merge / JSON patch). |
| **Disruptive updates** | Immutable fields need `kubectl replace --force` (delete + recreate, so there's an outage). |

## The demo app
The docs files are **verbatim**: [application/nginx-app.yaml](application/nginx-app.yaml) (Service `my-nginx-svc` + Deployment `my-nginx`), [application/nginx/nginx-svc.yaml](application/nginx/nginx-svc.yaml) and [application/nginx/nginx-deployment.yaml](application/nginx/nginx-deployment.yaml).
The docs' directory example, recreated with the same names: [project/k8s/development](project/k8s/development/) (`configmap/my-configmap.yaml`, `deployment/my-deployment.yaml`, `pvc/my-pvc.yaml`) and [project/k8s/namespaces](project/k8s/namespaces/).
[canary.yaml](canary.yaml) is the docs' guestbook stable/canary sketch, made complete.

---

## Lab 1 – One file, several objects; delete by file or label
```bash
cd concepts/workloads/management
kubectl create namespace mgmt-demo
kubectl apply -f application/nginx-app.yaml -n mgmt-demo         # service/my-nginx-svc created, deployment.apps/my-nginx created
kubectl delete deployments/my-nginx services/my-nginx-svc -n mgmt-demo
kubectl apply -f application/nginx/ -n mgmt-demo                 # a whole directory
kubectl delete deployment,services -l app=nginx -n mgmt-demo     # by label
kubectl apply -f application/nginx/ -n mgmt-demo
kubectl get $(kubectl get -f application/nginx/ -o name -n mgmt-demo | grep service/) -n mgmt-demo     # chaining
```

## Lab 2 – Recursive directories (docs example)
```bash
kubectl apply -f project/k8s/development
#   error: error reading [project/k8s/development]: recognized file extensions are [.json .yaml .yml]
#   (the docs show "you must provide one or more resources..." - same meaning, newer kubectl wording)
kubectl apply -f project/k8s/namespaces -f project/k8s/development --recursive
#   namespace/development created
#   namespace/staging created
#   configmap/my-config created
#   deployment.apps/my-deployment created
#   persistentvolumeclaim/my-pvc created
kubectl get -f project/k8s/development -R
```

## Lab 3 – Canary deployments
```bash
kubectl apply -f canary.yaml
kubectl wait --for=condition=Available deploy --all -n guestbook-demo --timeout=150s
kubectl get pods -n guestbook-demo -L track            # 3 stable + 1 canary
kubectl get endpointslice -n guestbook-demo -l kubernetes.io/service-name=frontend -o jsonpath='{range .items[0].endpoints[*]}{.targetRef.name}{"\n"}{end}'
#   all 4 pods - the Service ignores "track"
```
To promote: update `frontend`'s image, then delete `frontend-canary`. To roll back the canary, just delete it.

## Lab 4 – Annotate, scale, autoscale
```bash
P=$(kubectl get pods -n mgmt-demo -l app=nginx -o name | head -1)
kubectl annotate $P -n mgmt-demo description='my frontend running nginx'
kubectl get $P -n mgmt-demo -o jsonpath='{.metadata.annotations.description}{"\n"}'
kubectl scale deployment/my-nginx --replicas=1 -n mgmt-demo
kubectl autoscale deployment/my-nginx --min=1 --max=3 -n mgmt-demo          # needs metrics-server to act
kubectl delete hpa my-nginx -n mgmt-demo
```

## Lab 5 – In-place updates: apply, edit, patch
```bash
kubectl apply -f application/nginx/nginx-deployment.yaml -n mgmt-demo        # 3-way merge
kubectl edit deployment/my-nginx -n mgmt-demo                                 # opens $EDITOR
kubectl patch deployment my-nginx -n mgmt-demo --type='merge' -p '{"spec":{"strategy":{"rollingUpdate":{"maxSurge": "100%" }}}}'
kubectl patch deployment my-nginx -n mgmt-demo --subresource='scale' --type='merge' -p '{"spec":{"replicas": 2}}'
#   scale.autoscaling/my-nginx patched
```
The docs write the last one as `kubectl scale --replicas 1 deployments/my-nginx --subresource='scale' --type='merge' -p …`. That fails (`See 'kubectl scale --help'`) because `kubectl scale` doesn't accept a patch. Use `kubectl patch … --subresource=scale` (above) or plain `kubectl scale`.

## Lab 6 – Disruptive update
```bash
kubectl replace -f application/nginx/nginx-deployment.yaml --force -n mgmt-demo
#   deployment.apps "my-nginx" deleted
#   deployment.apps/my-nginx replaced          <- delete + create: ALL pods restart at once
```

## Lab 7 – Rollouts in pipelines
```bash
kubectl set image deployment/my-nginx nginx=nginx:1.27 -n mgmt-demo
kubectl rollout status deployment/my-nginx -n mgmt-demo --timeout 10m       # wait (exit code 0/1)
kubectl rollout status deployment/my-nginx -n mgmt-demo --watch=false       # just check, don't wait
```

---

## Useful commands
```bash
kubectl apply -f <dir> -R ; kubectl apply -k <dir>
kubectl delete <kind>,<kind> -l <selector>
kubectl get -f <file> -o name
kubectl patch <kind> <name> --type=merge|json|strategic -p '...'
```

## Cleanup
```bash
./cleanup.sh       # mgmt-demo, development, staging, guestbook-demo
```
