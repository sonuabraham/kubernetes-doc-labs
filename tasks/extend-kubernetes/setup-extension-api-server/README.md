# Set up an Extension API Server – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/extend-kubernetes/setup-extension-api-server/

> Runs on the default **minikube** cluster. The page is a 15-step checklist without manifests. This lab follows it step by step with a real
> `k8s.io/apiserver`-based server: the Kubernetes **sample-apiserver** (group `wardle.example.com`, kinds `Flunder`/`Fischer`, image
> `registry.k8s.io/e2e-test-images/sample-apiserver:1.29.2`, the one the aggregator e2e tests use) with an etcd sidecar as its storage.
> Files (all **not from the docs**): [extension-apiserver.yaml](extension-apiserver.yaml) (one object per step, commented with the step number),
> [setup.sh](setup.sh) (steps 1–15 in order, makes the CA/cert and fills `caBundle`), [flunder.yaml](flunder.yaml), [flunder-reader.yaml](flunder-reader.yaml).
> The aggregation layer flags are already set by minikube (see [configure-aggregation-layer](../configure-aggregation-layer/)). A tiny
> hand-written extension server is in the concept lab [apiserver-aggregation](../../../concepts/extend-kubernetes/api-extension/apiserver-aggregation/).
>
> **Notes from testing:**
> 1. Step 12 (`system:auth-delegator`) looks optional if you test as cluster admin. `k8s.io/apiserver` always allows `system:masters` without
>    a SubjectAccessReview. Test with a normal user to see it matter (Lab 3).
> 2. Step 13 (`extension-apiserver-authentication-reader`) is needed **at startup**: without it the server exits (`CrashLoopBackOff`).
> 3. The extension server has its **own storage**. With an `emptyDir`-less etcd sidecar (like here) all objects are gone after a Pod restart.

## Key ideas (read first)

| Step | Object | Why |
|---|---|---|
| 4–6 | CA, serving cert (CN/SAN `wardle-apiserver.wardle.svc`), Secret | kube-apiserver verifies the server with the CA in `caBundle` |
| 7–8 | Deployment mounting the Secret | the server serves TLS with it |
| 9–11 | ServiceAccount + ClusterRole(+Binding) | what the server itself reads (namespaces, admission configs, APF objects) |
| 12 | ClusterRoleBinding → `system:auth-delegator` | create TokenReviews / **SubjectAccessReviews** (authz is asked back from kube-apiserver) |
| 13 | RoleBinding in kube-system → `extension-apiserver-authentication-reader` | read the front-proxy CA + header names ConfigMap |
| 14 | APIService `v1alpha1.wardle.example.com` | registers `/apis/wardle.example.com/v1alpha1` with the aggregator |

---

## Lab 1 – Steps 1–15 (docs)
```bash
cd tasks/extend-kubernetes/setup-extension-api-server
./setup.sh
#   ## 1. APIService API enabled?      apiservices   apiregistration.k8s.io/v1   false   APIService
#   ## 2. may I create APIServices?    yes
#   ## 4-5. CA and serving cert (CN = wardle-apiserver.wardle.svc)
#   ## 3, 6-14. … serviceaccount/wardle-apiserver created … apiservice.apiregistration.k8s.io/v1alpha1.wardle.example.com created
#   apiservice.apiregistration.k8s.io/v1alpha1.wardle.example.com condition met
#   ## 15. get the resource
#   No resources found in default namespace.          <- what the docs promise
```

## Lab 2 – Use it (not from the docs)
```bash
kubectl api-resources --api-group=wardle.example.com
#   fischers   wardle.example.com/v1alpha1   false   Fischer
#   flunders   wardle.example.com/v1alpha1   true    Flunder
kubectl apply -f flunder.yaml && kubectl get flunders          # my-flunder   2026-11-18T10:41:07Z
kubectl -n wardle exec deploy/wardle-apiserver -c etcd -- etcdctl get --prefix --keys-only /
#   /registry/wardle.example.com/wardle.example.com/flunders/default/my-flunder      <- in the sidecar etcd …
../../../concepts/extend-kubernetes/api-extension/custom-resources/etcd-get.sh /registry/wardle.example.com/flunders/default/my-flunder
#   (nothing)                                                                       <- … not in the cluster's etcd
kubectl get flunders --as=system:serviceaccount:default:default
#   Error from server (Forbidden): flunders.wardle.example.com is forbidden: … cannot list resource "flunders" …   <- normal RBAC applies
```

## Lab 3 – Why steps 12 and 13 (not from the docs)
```bash
kubectl -n kube-system delete rolebinding wardle-apiserver-auth-reader       # undo step 13
kubectl -n wardle rollout restart deploy/wardle-apiserver
kubectl -n wardle get pods                                                    # new pod 1/2 CrashLoopBackOff
kubectl -n wardle logs <new-pod> -c apiserver | grep -E 'Unable|failed'
#   Unable to get configmap/extension-apiserver-authentication in kube-system.  Usually fixed by 'kubectl create rolebinding -n kube-system … --role=extension-apiserver-authentication-reader …'
#   "command failed" err="unable to load configmap based request-header-client-ca-file: configmaps \"extension-apiserver-authentication\" is forbidden: …"
# restore the RoleBinding (from extension-apiserver.yaml) → the rollout completes
kubectl get flunders                                       # No resources found   <- my-flunder lost with the old Pod's etcd (Note 3)

kubectl apply -f flunder-reader.yaml                       # a normal user (SA default/default) may list flunders
kubectl get flunders --as=system:serviceaccount:default:default        # No resources found  (allowed)
kubectl delete clusterrolebinding wardle-apiserver:system:auth-delegator      # undo step 12
kubectl get flunders --as=system:serviceaccount:default:default
#   Error from server (InternalError): … subjectaccessreviews.authorization.k8s.io is forbidden: User "system:serviceaccount:wardle:wardle-apiserver"
#   cannot create resource "subjectaccessreviews" in API group "authorization.k8s.io" at the cluster scope …
kubectl get flunders                                       # still works as admin (system:masters is always allowed, Note 1)
# restore the binding → the normal user works again
```

## Cleanup
```bash
./cleanup.sh
```
