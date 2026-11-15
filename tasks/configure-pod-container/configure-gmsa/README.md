# Configure GMSA for Windows Pods and containers – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/configure-pod-container/configure-gmsa/

> minikube has no Windows nodes and no Active Directory, so the **last step** (the Windows container
> runtime logging the container into the domain as the GMSA) can't happen here: the Pods stay `Pending`.
> Everything Kubernetes does **before** that step runs for real on the default **minikube** cluster:
> the CRD, credspec objects, the RBAC `use` verb and the two admission "webhooks".
> The webhooks are rebuilt as CEL admission policies, so no webhook image, certificates or Deployment are needed.
>
> Files (docs examples **verbatim**):
> [gmsa-Webapp1-credspec.yaml](gmsa-Webapp1-credspec.yaml), [gmsa-webapp1-role.yaml](gmsa-webapp1-role.yaml),
> [gmsa-webapp1-rolebinding.yaml](gmsa-webapp1-rolebinding.yaml), [with-creds-pod-level.yaml](with-creds-pod-level.yaml),
> [with-creds-container-level.yaml](with-creds-container-level.yaml), [lifecycle-netlogon-snippet.yaml](lifecycle-netlogon-snippet.yaml) (fragment).
> Not from the docs: [gmsa-crd.yaml](gmsa-crd.yaml) (the upstream CRD the docs link to, vendored),
> [gmsa-webhooks-as-policies.yaml](gmsa-webhooks-as-policies.yaml),
> [gmsa-webapp1-credspec-fixed.yaml](gmsa-webapp1-credspec-fixed.yaml), [gmsa-webapp1-role-fixed.yaml](gmsa-webapp1-role-fixed.yaml).

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **GMSA** | Group Managed Service Account, an Active Directory account whose password AD rotates. Windows containers can use one to authenticate to domain services (Kerberos, SMB, SQL) without holding a password. |
| **GMSACredentialSpec** (CRD `windows.k8s.io/v1`, **cluster-scoped**) | A *credential spec*: JSON that tells the Windows runtime which GMSA and domain to use. It contains **no secret**. It is generated with PowerShell (`New-CredentialSpec`) and wrapped as a custom resource. |
| **`windowsOptions.gmsaCredentialSpecName`** | What you write in a Pod (pod-level or per-container `securityContext`): a *reference* to a credspec by name. |
| **`windowsOptions.gmsaCredentialSpec`** | The full credspec JSON, filled in by the **mutating webhook**. The runtime on the node only reads this field. |
| **`use` verb** | A custom RBAC verb. The **validating webhook** allows a Pod only if its ServiceAccount may `use` each credspec it references. |
| **Webhook ≈ policy** | Here: `MutatingAdmissionPolicy gmsa-expand` (one evaluation per credspec via `paramRef.selector: {}`) and `ValidatingAdmissionPolicy gmsa-authorize` (CEL `authorizer` check). |

## What happens to a Pod
```
Deployment ──► ReplicaSet ──► Pod CREATE
                               │
                               ├─ gmsa-expand (mutating):  gmsaCredentialSpecName: gmsa-webapp1
                               │                             + gmsaCredentialSpec: '{"ActiveDirectoryConfig":…}'
                               ├─ gmsa-authorize (validating): can SA default/default `use` gmsa-webapp1?
                               │      no  ──► FailedCreate event on the ReplicaSet
                               │      yes ──► Pod stored
                               └─ scheduler: nodeSelector kubernetes.io/os=windows ──► (no node here) Pending
                                   on a real Windows node: containerd/hcsshim joins the container to AD as WebApp1
```

---

## Step 0 – Install the CRD and the two "webhooks"
```bash
cd tasks/configure-pod-container/configure-gmsa
kubectl apply -f gmsa-crd.yaml
kubectl wait --for condition=established crd/gmsacredentialspecs.windows.k8s.io
kubectl apply -f gmsa-webhooks-as-policies.yaml
#   mutatingadmissionpolicy…/gmsa-expand created   (+ binding)
#   validatingadmissionpolicy…/gmsa-authorize created   (+ binding)
```
On a real cluster you'd run upstream's `deploy-gmsa-webhook.sh` instead. It creates a cert, a Secret, a
Deployment and the two `*WebhookConfiguration`s. `--dry-run=server` shows what it would create.

## Lab 1 – Create the credential spec (and hit a docs bug)
```bash
kubectl apply -f gmsa-Webapp1-credspec.yaml
#   The GMSACredentialSpec "gmsa-WebApp1" is invalid: metadata.name: Invalid value: "gmsa-WebApp1":
#   a lowercase RFC 1123 subdomain must consist of lower case alphanumeric characters ...
```
Object names must be lowercase. The docs' name is also inconsistent: the Deployments use `gmsa-webapp1` and
`gmsa-Webapp1`. The fixed file changes only the name:
```bash
kubectl apply -f gmsa-webapp1-credspec-fixed.yaml
kubectl get gmsacredentialspecs
#   NAME           AGE
#   gmsa-webapp1   3s
```

## Lab 2 – No RBAC yet → the validating webhook says no
```bash
kubectl apply -f with-creds-pod-level.yaml
kubectl get rs -l run=with-creds
#   with-creds-7df56795b5   1   0   0        <- DESIRED 1, CURRENT 0
kubectl describe rs -l run=with-creds | grep FailedCreate | tail -1
#   Error creating: pods "with-creds-…" is forbidden: ValidatingAdmissionPolicy 'gmsa-authorize' with binding
#   'gmsa-authorize' denied request: service account default is not authorized to `use` gmsa credspec(s) gmsa-webapp1
kubectl delete deploy with-creds
```

## Lab 3 – Grant `use` with a ClusterRole + RoleBinding
```bash
kubectl apply -f gmsa-webapp1-role.yaml -f gmsa-webapp1-rolebinding.yaml   # docs verbatim
kubectl auth can-i use gmsacredentialspecs.windows.k8s.io/gmsa-webapp1 --as=system:serviceaccount:default:default
#   no            <- the docs' role names "gmsa-WebApp1" in resourceNames, which never matches a real object
kubectl apply -f gmsa-webapp1-role-fixed.yaml                            # resourceNames: ["gmsa-webapp1"]
kubectl auth can-i use gmsacredentialspecs.windows.k8s.io/gmsa-webapp1 --as=system:serviceaccount:default:default
#   Warning: resource 'gmsacredentialspecs' is not namespace scoped in group 'windows.k8s.io'
#   yes
```
A **RoleBinding** granting rights on a **cluster-scoped** resource only counts when the access check
carries a namespace. `kubectl auth can-i` sends the current namespace. The real webhook's
SubjectAccessReview sends the Pod's namespace, and so does the policy (`.namespace(request.namespace)`).
Without that, this binding would never authorise anything.

## Lab 4 – GMSA at pod level: expanded and allowed
```bash
kubectl apply -f with-creds-pod-level.yaml
kubectl get pods -l run=with-creds
#   with-creds-7df56795b5-5tj78   0/1   Pending      <- admitted; no Windows node to schedule on
kubectl get $(kubectl get pod -l run=with-creds -o name) -o jsonpath='{.spec.securityContext.windowsOptions}' | jq .
```
```json
{
  "gmsaCredentialSpec": "{\"ActiveDirectoryConfig\":{\"GroupManagedServiceAccounts\":[{\"Name\":\"WebApp1\",\"Scope\":\"CONTOSO\"},{\"Name\":\"WebApp1\",\"Scope\":\"contoso.com\"}]},\"CmsPlugins\":[\"ActiveDirectory\"],\"DomainJoinConfig\":{\"DnsName\":\"contoso.com\",\"DnsTreeName\":\"contoso.com\",\"Guid\":\"244818ae-87ac-4fcd-92ec-e79e5252348a\",\"MachineAccountName\":\"WebApp1\",\"NetBiosName\":\"CONTOSO\",\"Sid\":\"S-1-5-21-2126449477-2524075714-3094792973\"}}",
  "gmsaCredentialSpecName": "gmsa-webapp1"
}
```
The Deployment template only had the name. The full JSON was added at Pod admission, so it is in the Pod but not in the Deployment.

## Lab 5 – GMSA per container
```bash
kubectl delete deploy with-creds
kubectl apply -f with-creds-container-level.yaml
#   The Deployment "with-creds" is invalid: spec.template.spec.containers[0].securityContext.windowsOptions
#   .gmsaCredentialSpecName: Invalid value: "gmsa-Webapp1": a lowercase RFC 1123 subdomain must consist of …
sed 's/gmsa-Webapp1/gmsa-webapp1/' with-creds-container-level.yaml | kubectl apply -f -
kubectl get $(kubectl get pod -l run=with-creds -o name) -o json \
  | jq -c '.spec.containers[0].securityContext.windowsOptions | {name: .gmsaCredentialSpecName, specBytes: (.gmsaCredentialSpec|length)}'
#   {"name":"gmsa-webapp1","specBytes":394}
```

## Lab 6 – A different ServiceAccount is refused (not from the docs)
```bash
kubectl create sa other
kubectl create deploy other --image=busybox -- sleep 1
kubectl patch deploy other --type=merge -p '{"spec":{"template":{"spec":{"serviceAccountName":"other",
  "securityContext":{"windowsOptions":{"gmsaCredentialSpecName":"gmsa-webapp1"}}}}}}'
kubectl describe rs -l app=other | grep FailedCreate | tail -1
#   … denied request: service account other is not authorized to `use` gmsa credspec(s) gmsa-webapp1
```
The RBAC grant is per ServiceAccount, so only `default/default` may run Pods as WebApp1.

## On a real Windows node (reference only)
- **SMB by hostname/FQDN fails, but IP works**: on each Windows node, run
  `reg add "HKLM\SYSTEM\CurrentControlSet\Services\hns\State" /v EnableCompartmentNamespace /t REG_DWORD /d 1`, then recreate the Pods.
- **Did the Pod get the credspec?** Run `kubectl exec -it <pod> powershell.exe`, then `nltest.exe /parentdomain`.
  `Status = 1722 0x6ba RPC_S_SERVER_UNAVAILABLE` means no.
- **Can it reach the DC?** `nslookup` the domain root from inside the Pod.
- **Secure channel**: `nltest.exe /query`. To repair it, run `nltest /sc_reset:domain.example`. If that helps, automate it with the
  postStart hook in [lifecycle-netlogon-snippet.yaml](lifecycle-netlogon-snippet.yaml).

## Useful commands
```bash
kubectl get gmsacredentialspecs
kubectl get mutatingadmissionpolicy,validatingadmissionpolicy
kubectl auth can-i use gmsacredentialspecs.windows.k8s.io/<name> --as=system:serviceaccount:<ns>:<sa> -n <ns>
kubectl describe rs -l run=with-creds | grep FailedCreate
```

## Cleanup
```bash
./cleanup.sh
```
