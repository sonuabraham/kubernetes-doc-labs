# Enable Or Disable A Kubernetes API – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/administer-cluster/enable-disable-api/

> This runs on a throwaway profile **`api-lab`**. [set-runtime-config.sh](set-runtime-config.sh) sets kube-apiserver's `--runtime-config` in its static Pod manifest and waits for the API server. `''` removes the flag again.
>
> ⚠️ **The docs' own example doesn't work any more.** In v1.37, `--runtime-config=api/all=false,api/v1=true` stops the API server from starting. Lab 3 shows why, step by step.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **`--runtime-config`** | A comma-separated list of `<group>/<version>=true\|false` (core group: `api/v1`). Later entries override earlier ones. |
| **Special keys** | `api/all` (every known API), `api/legacy` (APIs that are explicitly deprecated). |
| **Defaults** | GA versions are on. **New beta APIs are off by default** (since 1.24), so a fresh 1.37 cluster serves only `v1`/`v2` group-versions. Alpha is always off. Some features also need a feature gate. |
| **Disabling ≠ deleting** | The objects stay in etcd. Re-enable the version and they're back. |
| **Dependencies** | The API server and the controllers use many APIs themselves. Turning them off breaks components, or the API server itself. |

---

## Step 0
```bash
cd tasks/administer-cluster/enable-disable-api
minikube start -p api-lab --memory 2200 --cpus 2 --kubernetes-version v1.37.0 && kubectl config use-context minikube
K="kubectl --context api-lab"
$K api-versions | tee /tmp/api-before.txt | wc -l      # 23 - all of them v1/v2, no betas
```

## Lab 1 – Enable beta API versions
```bash
./set-runtime-config.sh 'certificates.k8s.io/v1beta1=true,coordination.k8s.io/v1beta1=true'
#   15:    - --runtime-config=certificates.k8s.io/v1beta1=true,coordination.k8s.io/v1beta1=true
#   API server ready
$K api-versions | diff /tmp/api-before.txt -
#   > certificates.k8s.io/v1beta1
#   > coordination.k8s.io/v1beta1
$K api-resources --api-group=coordination.k8s.io
#   leasecandidates   coordination.k8s.io/v1beta1   true   LeaseCandidate     <- only exists at beta: new resource appears
#   leases            coordination.k8s.io/v1        true   Lease
$K api-resources --api-group=certificates.k8s.io
#   certificatesigningrequests / clustertrustbundles / podcertificaterequests   certificates.k8s.io/v1   <- v1 stays preferred
```

## Lab 2 – Disable a GA API (`batch/v1`)
```bash
$K create job before-job --image=busybox:1.36 -- true
./set-runtime-config.sh 'batch/v1=false'
$K api-versions | grep -c batch                     # 0
$K get jobs
#   error: the server doesn't have a resource type "jobs"
$K create job after-job --image=busybox:1.36 -- true
#   error: failed to create job: the server could not find the requested resource (post jobs.batch)
minikube ssh -p api-lab -- 'sudo crictl logs $(sudo crictl ps -q --name kube-controller-manager) 2>&1 | grep -E "jobs|cronjobs" | tail -2'
#   "Failed to watch" err="the server could not find the requested resource (get cronjobs.batch)"     <- controllers break too
#   "Failed to watch" err="the server could not find the requested resource (get jobs.batch)"
# the data is still in etcd:
#   etcdctl get /registry/jobs --prefix --keys-only   ->   /registry/jobs/default/before-job
```

## Lab 3 – The docs' example: `api/all=false,api/v1=true`
```bash
./set-runtime-config.sh 'api/all=false,api/v1=true'
#   API server NOT ready after ~3 min
minikube ssh -p api-lab -- 'sudo crictl logs $(sudo crictl ps -a -q --name kube-apiserver | head -1) 2>&1 | grep "command failed"'
#   "command failed" err="--runtime-config=api/all=false conflicts with --enable-priority-and-fairness=true"
```
Adding what the API server asks for, one error at a time:

| `--runtime-config=api/all=false,api/v1=true,` + … | Result |
|---|---|
| `flowcontrol.apiserver.k8s.io/v1=true` | `"command failed" err="API group/version apiregistration.k8s.io/v1 must be enabled"` |
| … `,apiregistration.k8s.io/v1=true` | `F ... PostStartHook "start-service-ip-repair-controllers" failed: unable to perform initial IP and Port allocation check (timeout)`: Service IP allocation uses ServiceCIDR/IPAddress objects |
| … `,networking.k8s.io/v1=true` | Starts, but `/readyz`: `[-]poststarthook/start-apiextensions-controllers failed`, `[-]poststarthook/crd-informer-synced failed` |
| … `,apiextensions.k8s.io/v1=true` | `/readyz`: `[-]informer-sync failed`. The authorizer and admission plugins can't watch their objects. |

The API server's own informers still failed on these (from its log):
```
clusterroles/clusterrolebindings/roles/rolebindings.rbac.authorization.k8s.io   <- the RBAC authorizer
validating/mutating webhookconfigurations, validating/mutating admissionpolicies(+bindings).admissionregistration.k8s.io
storageclasses, csidrivers, volumeattachments.storage.k8s.io      priorityclasses.scheduling.k8s.io
runtimeclasses.node.k8s.io     endpointslices.discovery.k8s.io     leases.coordination.k8s.io
podcertificaterequests.certificates.k8s.io                        resourceslices.resource.k8s.io
```
So "only v1" isn't a viable cluster today. Disable **specific** group-versions you don't want, instead of starting from `api/all=false`.

## Lab 4 – Back to defaults
```bash
./set-runtime-config.sh ''
#   no --runtime-config flag
#   API server ready
$K get jobs
#   before-job   ...   19m          <- served again from the untouched etcd data
```

---

## Useful commands
```bash
kubectl api-versions ; kubectl api-resources --api-group=<group>
kubectl get --raw '/readyz?verbose' ; kubectl get --raw '/livez?verbose'
crictl ps -a --name kube-apiserver ; crictl logs <id> | grep -E "command failed|^F"
```

## Cleanup
```bash
minikube delete -p api-lab
```
