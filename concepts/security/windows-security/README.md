# Security for Windows Nodes – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/security/windows-security/

> ⚠️ **Needs Windows nodes**, which minikube can't run. The page has no YAML. [probe.sh](probe.sh) server-dry-runs Windows Pods (`spec.os.name: windows`) to show which security settings the API accepts or rejects. Running them for real needs a Windows node pool.

## Key ideas (read first)

| Topic | Windows | Linux equivalent |
|---|---|---|
| **Secret data on nodes** | Written **in clear text to the node's disk**. Protect it with file ACLs and **BitLocker** volume encryption. | tmpfs (RAM), see [../linux-security](../linux-security/) |
| **Container user** | `windowsOptions.runAsUserName`: `ContainerUser` (Nano Server default) or `ContainerAdministrator` (Server Core default), or users added in the image | `runAsUser` |
| **Domain identity** | **gMSA** (`windowsOptions.gmsaCredentialSpecName` + the gMSA webhook/CRD) for Active Directory | — |
| **Isolation knobs** | **None** of SELinux, AppArmor, seccomp, POSIX capabilities | all available |
| **Privileged** | **Not supported**. Use **HostProcess** containers (`hostProcess: true` + `hostNetwork: true`) | `privileged: true` |

---

## Lab 1 – What the API allows for a Windows Pod
```bash
cd concepts/security/windows-security
./probe.sh
```
Measured:
```
runAsUserName ContainerUser                  pod/w created (server dry run)
runAsUserName ContainerAdministrator         pod/w created (server dry run)
runAsUserName DOMAIN\user                    pod/w created (server dry run)
runAsUserName with bad chars                 Invalid value: "bad\"user": runAsUserName's User cannot contain the following characters: "/\:;|=,+*?<>@[]
runAsUserName too long (>256)                Invalid value: "aaaa…": runAsUserName's length must not be greater than 256 characters
gmsaCredentialSpecName                       pod/w created (server dry run)
runAsUser (Linux)                            spec.securityContext.runAsUser: Forbidden: cannot be set for a windows pod
seLinuxOptions (Linux)                       Forbidden: cannot be set for a windows pod
seccompProfile (Linux)                       Forbidden: cannot be set for a windows pod
capabilities (Linux)                         Forbidden: cannot be set for a windows pod
appArmorProfile (Linux)                      Forbidden: cannot be set for a windows pod
privileged                                   Forbidden: cannot be set for a windows pod
hostProcess + hostNetwork                    pod/w created (server dry run)
```
- `runAsUserName` is validated as a Windows account name (`DOMAIN\user` or `user`, length and character limits).
- `gmsaCredentialSpecName` is accepted here because no gMSA webhook is installed. With the webhook (from the Windows gMSA project), the named `GMSACredentialSpec` must exist and the Pod's ServiceAccount must be allowed to `use` it.
- Linux-only security fields are **rejected outright** once `os.name: windows` is set. Without the OS field they'd be accepted and silently ignored on a Windows node.

## Lab 2 – Secret files on a Windows node (what you'd check there)
```powershell
# on the node, for a Pod mounting a Secret:
Get-ChildItem C:\var\lib\kubelet\pods\<pod-uid>\volumes\kubernetes.io~secret\<vol>\   # plain files on NTFS
Get-Acl <that path> | Format-List                                                        # restrict with ACLs
manage-bde -status C:                                                                    # BitLocker on?
```

---

## Useful commands
```bash
kubectl explain pod.spec.securityContext.windowsOptions
kubectl get nodes -L kubernetes.io/os
```

## Cleanup
```bash
./cleanup.sh
```
