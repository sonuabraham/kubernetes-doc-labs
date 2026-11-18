# Configure Multiple Schedulers – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/extend-kubernetes/configure-multiple-schedulers/

> Runs on the default **minikube** cluster. Files (docs, **verbatim**): [my-scheduler.yaml](my-scheduler.yaml), [clusterrole.yaml](clusterrole.yaml)
> (**don't apply**, see Found #1), [pod1.yaml](pod1.yaml), [pod2.yaml](pod2.yaml), [pod3.yaml](pod3.yaml).
> Not from the docs: [image/Dockerfile](image/Dockerfile) + [build-image.sh](build-image.sh), [my-scheduler-config-leader-election.yaml](my-scheduler-config-leader-election.yaml),
> [my-scheduler-leader-election-rbac.yaml](my-scheduler-leader-election-rbac.yaml).
> Concept lab with a second scheduler and profiles: [concepts/scheduling-eviction/kube-scheduler](../../../concepts/scheduling-eviction/kube-scheduler/).
>
> **Found:**
> 1. **`clusterrole.yaml` is an excerpt.** It holds 3 rules; the live `system:kube-scheduler` has 28. `kubectl apply -f clusterrole.yaml` would
>    *replace* the rules (server dry run: `3 rules after apply (live: 28)`) and take away nodes, pods, bindings… from **both** schedulers. Do what
>    the text says (`kubectl edit` and add `my-scheduler` to the lease `resourceNames`), or, as here, grant the lease in a separate ClusterRole.
>    The file's `endpoints` rule is obsolete: leader election uses Leases only.
> 2. "Package the scheduler" (clone + `make` + push to GCR) is replaced by a two-stage Dockerfile that takes the same binary from
>    `registry.k8s.io/kube-scheduler:v1.37.0` into the docs' `FROM busybox` image. `minikube image build` gives it the docs' name
>    `gcr.io/my-gcp-project/my-kube-scheduler:1.0`, so the Deployment is unchanged.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| `spec.schedulerName` | which scheduler binds the Pod; empty = `default-scheduler`; an unknown name = Pending forever, no event |
| Second scheduler | a normal Deployment running kube-scheduler with `--config`, profile `schedulerName: my-scheduler` |
| RBAC | `system:kube-scheduler` + `system:volume-scheduler` + `extension-apiserver-authentication-reader` |
| Leader election | needs its own lock (`resourceName: my-scheduler`) and `get/update` on that Lease |

---

## Lab 1 – Build and deploy (docs)
```bash
cd tasks/extend-kubernetes/configure-multiple-schedulers
./build-image.sh                  # … naming to gcr.io/my-gcp-project/my-kube-scheduler:1.0 done
```
Verify the routing the docs' way: Pods **first**, scheduler second.
```bash
kubectl create -f pod1.yaml; kubectl create -f pod2.yaml; kubectl create -f pod3.yaml
kubectl get pods -l name=multischeduler-example
#   annotation-default-scheduler   1/1   Running
#   annotation-second-scheduler    0/1   Pending     <- nobody serves "my-scheduler" yet
#   no-annotation                  1/1   Running
kubectl create -f my-scheduler.yaml
kubectl get pods --namespace=kube-system -l component=scheduler      # my-scheduler-5b76c96fd4-5p7dc   1/1   Running
kubectl get pods -l name=multischeduler-example                      # all three Running
for p in no-annotation annotation-default-scheduler annotation-second-scheduler; do
  kubectl get events --field-selector involvedObject.name=$p,reason=Scheduled -o custom-columns=FROM:.reportingComponent --no-headers; done
#   default-scheduler
#   default-scheduler
#   my-scheduler
kubectl run typo-scheduler --image=registry.k8s.io/pause:3.8 --overrides='{"spec":{"schedulerName":"my-schedular"}}'
kubectl get pod typo-scheduler                # Pending, and no events at all (not from the docs)
```

## Lab 2 – Leader election (docs)
```bash
kubectl apply -f my-scheduler-config-leader-election.yaml      # leaderElect: true, resourceNamespace: kube-system, resourceName: my-scheduler
kubectl -n kube-system rollout restart deploy/my-scheduler
kubectl -n kube-system logs deploy/my-scheduler | grep -i lease
#   "Attempting to acquire leader lease..." lock="kube-system/my-scheduler"
#   "Error retrieving lease lock" err="leases.coordination.k8s.io \"my-scheduler\" is forbidden: User \"system:serviceaccount:kube-system:my-scheduler\" cannot get resource \"leases\" …"
sed 's/annotation-second-scheduler/second-scheduler-while-not-leader/' pod3.yaml | kubectl create -f -
kubectl get pod second-scheduler-while-not-leader      # Pending   <- a non-leader doesn't schedule
kubectl apply --dry-run=server -f clusterrole.yaml -o json | jq '.rules | length'     # 3   (live role: 28)  -> Found #1
kubectl apply -f my-scheduler-leader-election-rbac.yaml
kubectl -n kube-system get lease my-scheduler           # HOLDER my-scheduler-85ffb7464-bqr2v_…
kubectl -n kube-system logs deploy/my-scheduler | grep acquired     # "Successfully acquired lease" lock="kube-system/my-scheduler"
kubectl get pod second-scheduler-while-not-leader       # Running
```
minikube's own kube-scheduler runs with `--leader-elect=false`, so there is no `kube-scheduler` Lease to collide with here.

## Cleanup
```bash
./cleanup.sh           # the image stays cached: minikube image rm gcr.io/my-gcp-project/my-kube-scheduler:1.0
```
