# Managing Kubernetes Objects Using Imperative Commands – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/manage-kubernetes-objects/imperative-command/

> Runs on the default **minikube** cluster in namespace `imp-cmd` (the page has no manifests: everything is a `kubectl` command).
> Sibling labs: [imperative-config](../imperative-config/) and [declarative-config](../declarative-config/).

## Key ideas (read first)

| Kind of command | Examples | Notes |
|---|---|---|
| verb-driven create | `run`, `expose`, `autoscale` | for users who don't know the object types |
| type-driven create | `create <type> [<subtype>] <name>` | e.g. `create service nodeport` |
| verb-driven update | `scale`, `annotate`, `label` | |
| aspect-driven update | `set image`, `set resources`, `set selector`, `set env`… | |
| raw update | `edit`, `patch` | need schema knowledge |
| delete / view | `delete <type>/<name>`, `get`, `describe`, `logs` | |
| fields without a flag | `create … -o yaml --dry-run=client \| kubectl set … --local -f - -o yaml \| kubectl create -f -`, or `create --edit` | |

---

## Step 0
```bash
cd tasks/manage-kubernetes-objects/imperative-command
kubectl create namespace imp-cmd; kubectl config set-context --current --namespace=imp-cmd
```

## Lab 1 – Create
```bash
kubectl create deployment nginx --image=nginx:1.27
kubectl run single --image=busybox:1.36 -- sleep 3600
kubectl expose deployment nginx --port=80
kubectl autoscale deployment nginx --min=1 --max=3 --cpu=50%      # newer flag; --cpu-percent=50 is the old spelling
kubectl create service nodeport my-nodeport --tcp=8080:80        # the docs' subtype example
kubectl get svc my-nodeport -o jsonpath='{.spec.type} {.spec.selector}'      # NodePort {"app":"my-nodeport"}
kubectl create service nodeport -h                               # flags of a subcommand
```

## Lab 2 – Update
```bash
kubectl scale deployment nginx --replicas=2
kubectl annotate deployment nginx owner=team-a
kubectl label deployment nginx tier=web
kubectl set image deployment/nginx nginx=nginx:1.27-alpine
kubectl set resources deployment nginx --limits=memory=128Mi
kubectl patch deployment nginx -p '{"spec":{"minReadySeconds":3}}'
kubectl get deploy nginx -o json | jq -c '{replicas:.spec.replicas, minReady:.spec.minReadySeconds, image:.spec.template.spec.containers[0].image, res:.spec.template.spec.containers[0].resources, ann:.metadata.annotations.owner, labels:.metadata.labels}'
#   {"replicas":2,"minReady":3,"image":"nginx:1.27-alpine","res":{"limits":{"memory":"128Mi"}},"ann":"team-a","labels":{"app":"nginx","tier":"web"}}
```

## Lab 3 – Fields without a flag (docs)
```bash
kubectl create service clusterip my-svc --clusterip="None" -o yaml --dry-run=client \
  | kubectl set selector --local -f - 'environment=qa' -o yaml | kubectl create -f -
kubectl get svc my-svc -o jsonpath='{.spec.clusterIP} {.spec.selector}'       # None {"environment":"qa"}

kubectl create service clusterip my-svc2 --clusterip="None" -o yaml --dry-run=client > srv.yaml
kubectl create --edit -f srv.yaml          # opens $EDITOR; to script it:
EDITOR="sed -i s/app:\ my-svc2/app:\ edited/" kubectl create --edit -f srv.yaml
kubectl get svc my-svc2 -o jsonpath='{.spec.selector}'                         # {"app":"edited"}
```

## Lab 4 – Delete (docs)
```bash
kubectl delete deployment/nginx
kubectl get hpa,svc -o name
#   horizontalpodautoscaler.autoscaling/nginx      <- still there: deleting the Deployment doesn't touch the HPA
#   service/nginx                                   <- or the Service that `expose` created
```
Imperative commands don't track which objects belong together. You delete each one yourself (or use labels).

## Useful commands
```bash
kubectl create --help                     # all type-driven create subcommands
kubectl set --help                        # all aspects
kubectl <cmd> --dry-run=client -o yaml    # see what a command would create
```

## Cleanup
```bash
kubectl config set-context --current --namespace=default
./cleanup.sh
```
