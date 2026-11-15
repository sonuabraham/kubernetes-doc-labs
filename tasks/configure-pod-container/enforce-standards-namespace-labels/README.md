# Enforce Pod Security Standards with Namespace Labels – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/configure-pod-container/enforce-standards-namespace-labels/

> Runs on the default **minikube** cluster. Files: [my-baseline-namespace.yaml](my-baseline-namespace.yaml) (docs, **verbatim**, with the
> docs' `v{{< skew currentVersion >}}` placeholder rendered as `v1.37`). Not from the docs: [test-pods.yaml](test-pods.yaml),
> [no-seccomp-pod.yaml](no-seccomp-pod.yaml).
> ⚠️ The docs' "Applying to all namespaces" step labels **every** namespace, `kube-system` included. [cleanup.sh](cleanup.sh) removes those labels again.
> Concepts: [concepts/security](../../../concepts/security/) (Pod Security Standards / Admission).

## Key ideas (read first)

| Label | Effect on a violating **Pod** | On a workload (Deployment…) |
|---|---|---|
| `pod-security.kubernetes.io/enforce: <level>` | **rejected** | *not* checked (its Pods are rejected later, at ReplicaSet level) |
| `…/warn: <level>` | allowed + warning to the user | warning too |
| `…/audit: <level>` | allowed + annotation in the API audit log | annotation too |
| `…/<mode>-version: v1.37 \| latest` | which version of the standard's rules to apply | |

Levels: `privileged` (no checks) ⊂ `baseline` (no host namespaces, privileged, hostPath, …) ⊂ `restricted` (non-root,
drop ALL, no privilege escalation, seccomp). Common pattern: **enforce** what you can today and **warn/audit** what you're aiming for.

---

## Step 0
```bash
cd tasks/configure-pod-container/enforce-standards-namespace-labels
```

## Lab 1 – Enforce baseline, warn/audit restricted (docs)
```bash
kubectl apply -f my-baseline-namespace.yaml
kubectl apply -n my-baseline-namespace -f test-pods.yaml
```
```
Warning: would violate PodSecurity "restricted:v1.37": allowPrivilegeEscalation != false (…), unrestricted capabilities (…),
         runAsNonRoot != true (…), seccompProfile (…)
pod/pod-baseline created                        <- baseline OK, restricted warned
pod/pod-restricted created                      <- nothing to complain about
Error from server (Forbidden): … pods "pod-privileged" is forbidden: violates PodSecurity "baseline:v1.37": host namespaces (hostNetwork=true)
```

## Lab 2 – Workloads are only warned about (not from the docs)
```bash
kubectl create deployment hostnet --image=busybox:1.36 -n my-baseline-namespace --dry-run=client -o json -- sleep 3600 \
  | jq '.spec.template.spec.hostNetwork=true' | kubectl apply -f -
#   Warning: would violate PodSecurity "restricted:v1.37": host namespaces (hostNetwork=true), …
#   deployment.apps/hostnet created                   <- the Deployment is accepted
kubectl get rs -n my-baseline-namespace -l app=hostnet      # DESIRED 1  CURRENT 0
kubectl describe rs -n my-baseline-namespace -l app=hostnet | grep FailedCreate
#   Error creating: pods "hostnet-…" is forbidden: violates PodSecurity "baseline:v1.37": host namespaces …
```
Enforcement happens on the Pod, so the failure shows up on the ReplicaSet. `warn` on the namespace is what tells you up front.

## Lab 3 – Try a change before making it (docs)
```bash
kubectl label --dry-run=server --overwrite ns --all pod-security.kubernetes.io/enforce=baseline
```
```
Warning: existing pods in namespace "kube-system" violate the new PodSecurity enforce level "baseline:latest"
Warning: csi-hostpath-attacher-0 (and 2 other pods): hostPath volumes, privileged
Warning: etcd-minikube (and 3 other pods): host namespaces, hostPath volumes, hostPort, probe or lifecycle host
Warning: kindnet-wt5hc: non-default capabilities, host namespaces, hostPath volumes
Warning: kube-proxy-c8bcn: host namespaces, hostPath volumes, privileged
Warning: storage-provisioner: host namespaces, hostPath volumes
```
Nothing was changed (`kubectl get ns -L pod-security.kubernetes.io/enforce` still shows only `my-baseline-namespace`).

## Lab 4 – Audit + warn everywhere (docs)
```bash
kubectl label --overwrite ns --all pod-security.kubernetes.io/audit=baseline pod-security.kubernetes.io/warn=baseline
kubectl get namespaces --selector='!pod-security.kubernetes.io/enforce'
#   default  kube-node-lease  kube-public  kube-system           <- not yet evaluated for enforcement
kubectl run plain-hostnet --image=busybox:1.36 --overrides='{"spec":{"hostNetwork":true}}' -- sleep 3600
#   Warning: would violate PodSecurity "baseline:latest": host namespaces (hostNetwork=true)
#   pod/plain-hostnet created
kubectl delete pod plain-hostnet --now
kubectl get ns my-baseline-namespace -o json | jq -c '.metadata.labels|with_entries(select(.key|startswith("pod-security")))'
#   {…"audit":"baseline",…"warn":"baseline",…}        <- careful: --overwrite --all LOWERED Lab 1's restricted audit/warn
```

## Lab 5 – Enforce restricted on an existing namespace (docs)
```bash
kubectl create namespace my-existing-namespace
kubectl run legacy -n my-existing-namespace --image=busybox:1.36 -- sleep 3600
kubectl label --overwrite ns my-existing-namespace \
  pod-security.kubernetes.io/enforce=restricted pod-security.kubernetes.io/enforce-version=v1.37
#   Warning: existing pods in namespace "my-existing-namespace" violate the new PodSecurity enforce level "restricted:v1.37"
#   Warning: legacy: allowPrivilegeEscalation != false, unrestricted capabilities, runAsNonRoot != true, seccompProfile
kubectl get pod legacy -n my-existing-namespace       # still Running: existing Pods are never evicted
kubectl run newer -n my-existing-namespace --image=busybox:1.36 -- sleep 3600
#   Error from server (Forbidden): pods "newer" is forbidden: violates PodSecurity "restricted:v1.37": …
```

## Lab 6 – Why pin the version (not from the docs)
[no-seccomp-pod.yaml](no-seccomp-pod.yaml) is restricted-compliant except for seccomp.
```bash
kubectl create ns psa-versions
for v in v1.18 v1.24 latest; do
  kubectl label --overwrite ns psa-versions pod-security.kubernetes.io/enforce=restricted pod-security.kubernetes.io/enforce-version=$v
  kubectl create -n psa-versions --dry-run=server -o name -f no-seccomp-pod.yaml; done
```
| enforce-version | Result |
|---|---|
| v1.18 | `pod/no-seccomp` allowed |
| v1.24 | `violates PodSecurity "restricted:v1.24": seccompProfile (…)` |
| latest | `violates PodSecurity "restricted:latest": seccompProfile (…)` |

`latest` follows every Kubernetes upgrade, so a new version can start rejecting Pods. Pin the version, and raise it on purpose.

## Useful commands
```bash
kubectl get ns -L pod-security.kubernetes.io/enforce,pod-security.kubernetes.io/warn,pod-security.kubernetes.io/audit
kubectl label --dry-run=server --overwrite ns <ns> pod-security.kubernetes.io/enforce=restricted
```

## Cleanup
```bash
./cleanup.sh      # deletes the lab namespaces and removes the audit/warn labels from ALL namespaces
```
