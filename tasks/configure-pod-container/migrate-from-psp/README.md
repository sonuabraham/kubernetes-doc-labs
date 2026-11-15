# Migrate from PodSecurityPolicy to the Built-In PodSecurity Admission Controller – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/configure-pod-container/migrate-from-psp/

> **PodSecurityPolicy was removed in v1.25**, so on this 1.37 cluster the PSP half of the page (steps 2 and 3.d) can only be shown
> failing. The **Pod Security Admission** half (steps 1, 3, 4, 5) runs for real on the default **minikube** cluster. The two places
> where the page says "use an admission webhook" are built as in-cluster CEL policies.
> Files: [privileged-psp.yaml](privileged-psp.yaml) (docs, **verbatim**). Not from the docs: [legacy-workloads.yaml](legacy-workloads.yaml),
> [protect-psa-labels.yaml](protect-psa-labels.yaml), [default-securitycontext.yaml](default-securitycontext.yaml).
> Related: [enforce-standards-namespace-labels](../enforce-standards-namespace-labels/), [enforce-standards-admission-controller](../enforce-standards-admission-controller/).

## Key ideas (read first)

| PSP feature | Pod Security Admission answer | In this lab |
|---|---|---|
| validate Pods | 3 fixed levels per namespace (labels) | Lab 2 |
| **default/mutate** fields | none, PSA never mutates | MutatingAdmissionPolicy (Lab 4) |
| custom rules | none | ValidatingAdmissionPolicy / webhook |
| per user / SA policies | only static exemptions | [admission-controller lab](../enforce-standards-admission-controller/) |
| who may weaken policy | **anyone who can patch the Namespace** | VAP guarding the labels (Lab 3) |

Migration loop per namespace: choose a level → **dry-run** (existing Pods) → **warn/audit** (catches what isn't running) → **enforce**.

---

## Step 0 – PSP is gone (docs step 3.d and 5)
```bash
cd tasks/configure-pod-container/migrate-from-psp
kubectl apply -f privileged-psp.yaml
#   error: resource mapping not found … no matches for kind "PodSecurityPolicy" in version "policy/v1beta1"
kubectl api-resources | grep -i podsecuritypolic        # (nothing)
kubectl logs -n kube-system kube-apiserver-minikube | grep -E 'Loaded [0-9]+ (mutating|validating) admission'
#   Loaded 15 mutating admission controller(s) … NamespaceLifecycle,LimitRanger,ServiceAccount,…,MutatingAdmissionPolicy,…
#   Loaded 15 validating admission controller(s) … LimitRanger,ServiceAccount,PodSecurity,Priority,…,ValidatingAdmissionPolicy,…
```
That is the docs' step 5 check: `PodSecurity` is listed and `PodSecurityPolicy` is not. The docs'
`kubectl create clusterrole privileged-psp --verb use --resource podsecuritypolicies.policy …` still *succeeds*,
because RBAC doesn't check that resources exist. It just grants nothing useful.

## Lab 1 – Step 3.a/3.b: find the right level for a namespace
```bash
kubectl apply -f legacy-workloads.yaml       # ns legacy: Deployment web (plain), Deployment logger (hostPath), CronJob nightly (hostNetwork)
NAMESPACE=legacy
for LEVEL in baseline restricted; do kubectl label --dry-run=server --overwrite ns $NAMESPACE pod-security.kubernetes.io/enforce=$LEVEL; done
```
```
Warning: existing pods in namespace "legacy" violate the new PodSecurity enforce level "baseline:latest"
Warning: logger-546cbcf979-gtjwb: hostPath volumes
Warning: existing pods in namespace "legacy" violate the new PodSecurity enforce level "restricted:latest"
Warning: logger-…: allowPrivilegeEscalation != false, unrestricted capabilities, restricted volume types, runAsNonRoot != true, seccompProfile
Warning: web-…:    allowPrivilegeEscalation != false, unrestricted capabilities, runAsNonRoot != true, seccompProfile
```
**The CronJob isn't mentioned.** It has no Pods right now, which is the docs' caution. Warn/audit catches it:
```bash
kubectl label --overwrite ns $NAMESPACE pod-security.kubernetes.io/audit=baseline pod-security.kubernetes.io/warn=baseline
kubectl annotate cronjob nightly -n legacy touched=1 --overwrite      # any write of the workload
#   Warning: would violate PodSecurity "baseline:latest": host namespaces (hostNetwork=true)
```

## Lab 2 – Step 3.c: enforce
```bash
kubectl label --overwrite ns $NAMESPACE pod-security.kubernetes.io/enforce=baseline
kubectl rollout restart deploy/logger -n legacy
kubectl get rs -n legacy -l app=logger
#   logger-546cbcf979   1   1   1    <- the old Pod keeps running…
#   logger-689bb867cf   1   0   0    <- …the new one can't be created
kubectl get events -n legacy --field-selector reason=FailedCreate -o custom-columns=MSG:.message --no-headers | tail -1
#   Error creating: pods "logger-…" is forbidden: violates PodSecurity "baseline:latest": hostPath volumes (volume "logs")
```
A rolling update stalls instead of taking the app down. Fix the workload (or move it to a namespace with the right level) before the next rollout.

## Lab 3 – Step 1: stop namespace editors from lowering the level
[protect-psa-labels.yaml](protect-psa-labels.yaml): a ValidatingAdmissionPolicy plus a user `ns-editor` allowed to patch Namespaces.
```bash
kubectl apply -f protect-psa-labels.yaml
kubectl label ns legacy pod-security.kubernetes.io/enforce=privileged --overwrite --as=ns-editor
#   … ValidatingAdmissionPolicy 'protect-pod-security-labels' … denied request: only cluster admins may change pod-security.kubernetes.io labels (user ns-editor)
kubectl label ns legacy pod-security.kubernetes.io/enforce- --as=ns-editor        # denied too (removing = weakening)
kubectl label ns legacy team=payments --as=ns-editor                               # namespace/legacy labeled  (other labels are fine)
kubectl label ns legacy pod-security.kubernetes.io/enforce=baseline --overwrite    # cluster admin: allowed
```

## Lab 4 – Step 2.a replacement: defaulting without PSP
PSP could *set* `allowPrivilegeEscalation`, seccomp, dropped capabilities or the user. PSA only checks.
[default-securitycontext.yaml](default-securitycontext.yaml) brings the defaulting back with a MutatingAdmissionPolicy, for
namespaces labelled `psa-defaults=restricted`, and creates the namespace `defaulted` (enforce restricted).
```bash
kubectl apply -f default-securitycontext.yaml; sleep 5            # policies take a few seconds to become active
kubectl run plain -n defaulted --image=busybox:1.36 -- sleep 3600  # no securityContext at all
kubectl get pod plain -n defaulted -o json | jq -c '{pod:.spec.securityContext, ctr:.spec.containers[0].securityContext}'
#   {"pod":{"runAsNonRoot":true,"runAsUser":65534,"seccompProfile":{"type":"RuntimeDefault"}},
#    "ctr":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}}
kubectl exec -n defaulted plain -- id            # uid=65534(nobody) …
```
Mutating admission runs **before** validation, so `PodSecurity` sees the defaulted Pod, and it passes `restricted`.
Two things learned building it:
- Right after `kubectl apply`, the first Pod was rejected by `restricted` because the policy wasn't active yet.
- `capabilities.drop` is an *atomic* list. An ApplyConfiguration that sets it fails with `may not mutate atomic arrays,
  maps or structs: .spec.containers[0].securityContext.capabilities.drop`, so the container part uses a JSONPatch
  (`lists.range(…)` over the containers).

## Lab 5 – Step 4: new namespaces
Either a process that labels every new namespace, or cluster-wide defaults in the PodSecurity admission configuration. See
[enforce-standards-admission-controller](../enforce-standards-admission-controller/) (an unlabeled namespace got enforce baseline
plus warn/audit restricted there).

## Useful commands
```bash
kubectl get ns -L pod-security.kubernetes.io/enforce,pod-security.kubernetes.io/warn,pod-security.kubernetes.io/audit
kubectl get ns --selector='!pod-security.kubernetes.io/enforce'
kubectl label --dry-run=server --overwrite ns <ns> pod-security.kubernetes.io/enforce=<level>
```

## Cleanup
```bash
./cleanup.sh       # policies, test user RBAC, namespaces legacy + defaulted
```
