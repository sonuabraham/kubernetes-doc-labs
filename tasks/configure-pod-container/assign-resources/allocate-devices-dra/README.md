# Allocate Devices to Workloads with DRA – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/configure-pod-container/assign-resources/allocate-devices-dra/

> Runs on **`dra-lab`** with the lab driver as `driver.example.com` (4 GPUs) and the DeviceClass from [../set-up-dra-cluster](../set-up-dra-cluster/). Files:
> - Docs manifests, **verbatim**: [resourceclaimtemplate.yaml](resourceclaimtemplate.yaml), [resourceclaim.yaml](resourceclaim.yaml), [dra-example-job.yaml](dra-example-job.yaml).
> - [resourceclaim-exactcount.yaml](resourceclaim-exactcount.yaml) (**not from the docs**): the docs' claim with `allocationMode: ExactCount, count: 1`. With the docs' claim the Job can never be scheduled (Lab 2).

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **ResourceClaimTemplate** | Each Pod gets its **own** generated ResourceClaim (`<pod>-<claimname>-xxxxx`), deleted with the Pod. |
| **ResourceClaim** | One claim that you create. Every Pod that references it **shares** the same allocated device(s) (`status.reservedFor` lists them). |
| **Request** | `exactly:` with `deviceClassName`, optional CEL `selectors` on `device.attributes[...]` / `device.capacity[...]`, and `allocationMode`: `ExactCount` (default, `count: 1`) or `All` (every matching device). |
| **In the Pod** | `spec.resourceClaims` names the claims (by `resourceClaimName` or `resourceClaimTemplateName`). Each container opts in with `resources.claims[].name`. Containers that don't list a claim don't get its device. |
| **Scheduling** | The scheduler allocates devices from ResourceSlices (`status.allocation`), then the kubelet asks the driver to **prepare** them before the containers start. |

---

## Step 0
```bash
cd tasks/configure-pod-container/assign-resources
$K get resourceslices                     # 00000-driver.example.com-dra-lab-...  (4 GPUs)
$K apply -f set-up-dra-cluster/deviceclass.yaml
cd allocate-devices-dra
```

## Lab 1 – Create the claims (the docs' commands)
```bash
$K apply -f resourceclaimtemplate.yaml
$K apply -f resourceclaim.yaml
$K get resourceclaims
#   NAME                     STATE     AGE
#   example-resource-claim   pending   2s      <- allocated only when a Pod uses it
```

## Lab 2 – The docs' Job with the docs' claim: never schedules
```bash
$K apply -f dra-example-job.yaml
$K get po -l job-name=example-dra-job
#   example-dra-job-xxxxx   0/3   Pending
$K describe po -l job-name=example-dra-job | grep -A1 Events -m1; $K get events | grep FailedScheduling | tail -1
#   0/1 nodes are available: 1 cannot allocate all claims. ...
```
Why: `allocationMode: All` makes the **shared** claim take *every* GPU matching its selector, which is all 4 GPUs. Each Pod's template claim needs one more GPU with the same selector, so there's none left. This holds on any node: the template and the All claim always compete for the same devices.
```bash
$K delete -f dra-example-job.yaml; $K delete -f resourceclaim.yaml
```

## Lab 3 – The Job with a single-GPU shared claim (not from the docs)
```bash
$K apply -f resourceclaim-exactcount.yaml
$K apply -f dra-example-job.yaml
$K get po -l job-name=example-dra-job
#   example-dra-job-7xlsm   3/3   Running        <- parallelism 2: 2 template GPUs + 1 shared = 3 of 4 GPUs
#   example-dra-job-q4m9t   3/3   Running
$K get resourceclaims -o custom-columns=NAME:.metadata.name,DEVICES:.status.allocation.devices.results[*].device,RESERVED:.status.reservedFor[*].name
#   example-dra-job-7xlsm-separate-gpu-claim-wlk55   gpu-0   example-dra-job-7xlsm
#   example-dra-job-q4m9t-separate-gpu-claim-dkcmq   gpu-2   example-dra-job-q4m9t
#   example-resource-claim                           gpu-1   example-dra-job-7xlsm,example-dra-job-q4m9t    <- shared
```

## Lab 4 – Did the containers really get their devices?
The lab driver's CDI spec injects env vars, so each container shows what it was given:
```bash
POD=$($K get po -l job-name=example-dra-job -o name | head -1)
for c in container0 container1 container2; do echo "$c: $($K exec $POD -c $c -- sh -c 'env | grep ^GPU_DEVICE | sort | tr "\n" " "')"; done
#   container0: GPU_DEVICE_0=gpu-2 GPU_DEVICE_0_CLAIM=default/example-dra-job-q4m9t-separate-gpu-claim-dkcmq GPU_DEVICE_0_REQUEST=gpu-claim
#   container1: GPU_DEVICE_0=gpu-1 GPU_DEVICE_0_CLAIM=default/example-resource-claim GPU_DEVICE_0_REQUEST=single-gpu-claim
#   container2: GPU_DEVICE_0=gpu-1 GPU_DEVICE_0_CLAIM=default/example-resource-claim GPU_DEVICE_0_REQUEST=single-gpu-claim
../driver.sh logs driver.example.com 5
#   prepared claim default/example-dra-job-q4m9t-separate-gpu-claim-dkcmq: 1 device(s), CDI spec /var/run/cdi/driver_example_com-<uid>.json
```
`container0` has a GPU of its own. `container1` and `container2` share `gpu-1` with the other Pod's two containers. With real GPUs, the driver would inject device nodes the same way.

---

## Useful commands
```bash
kubectl get resourceclaims -o wide
kubectl get resourceclaim <name> -o jsonpath='{.status.allocation}{"\n"}{.status.reservedFor}'
kubectl describe pod <pod> | grep -A3 "Resource Claims"
```

## Cleanup (the docs' commands)
```bash
$K delete -f dra-example-job.yaml
$K delete -f resourceclaimtemplate.yaml
$K delete -f resourceclaim-exactcount.yaml          # docs: resourceclaim.yaml
```
