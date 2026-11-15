# Create a Windows HostProcess Pod – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/configure-pod-container/create-hostprocess-pod/

> HostProcess containers need a Windows node running containerd ≥ 1.6. minikube has none, so nothing here actually runs
> *as a Windows host process*. What runs for real on the default **minikube** cluster:
> - the API server's HostProcess validation rules ([test-rules.sh](test-rules.sh)), as server-side dry runs;
> - Pod Security admission, which only lets HostProcess Pods into `privileged` namespaces;
> - a **Linux look-alike** ([linux-host-pod.yaml](linux-host-pod.yaml)), so you can feel what "a container that is really a host process" means.
>
> [hostprocess-pod.yaml](hostprocess-pod.yaml) is the docs' manifest excerpt with `apiVersion/kind/metadata` added; the spec is **verbatim**.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **HostProcess container** | A Windows container that runs as a normal **process on the host**: host network, host filesystem, devices, no filesystem or Hyper-V isolation. Used for CNI/CSI/device plugins, kube-proxy, log agents, patching. |
| **Required fields** | `windowsOptions.hostProcess: true`, `hostNetwork: true`, and a `runAsUserName`. `runAsNonRoot` must be unset or `false`. |
| **All or nothing** | If any container is HostProcess, **all** containers must be (Windows can't share the host vNIC with isolated containers). Pod-level and container-level values must agree. |
| **Users** | `NT AUTHORITY\SYSTEM` (LocalSystem, most privileged), `NT AUTHORITY\Local service` (least, preferred), `NT AUTHORITY\NetworkService`, or the name of a **local usergroup**. For a usergroup, containerd ≥ 1.7 creates an *ephemeral* user in that group. |
| **Volumes** | containerd 1.7+: at the normal `mountPath` (`c:\var\run\secrets\…` or `/var/run/secrets/…`). containerd 1.6: relative to `$CONTAINER_SANDBOX_MOUNT_POINT`. Named pipes and Unix sockets can't be mounted; use their host paths. |
| **Limits** | Memory/CPU/disk limits apply to the job object, job-wide, like other Windows containers. |
| **Pod Security** | Forbidden by **baseline** and **restricted**. Only the **privileged** level allows it. |

## The Pod as Windows would run it
```
Windows node ─ containerd (as LocalSystem) ─ job object  ◄─ hostprocess-demo/test: ping -t 127.0.0.1
                                               │   user: NT AUTHORITY\Local service
                                               │   network: the node's own IP (hostNetwork)
                                               └── fs: host C:\ + container volume at $CONTAINER_SANDBOX_MOUNT_POINT
```

---

## Step 0
```bash
cd tasks/configure-pod-container/create-hostprocess-pod
```

## Lab 1 – What the API server enforces (not from the docs)
```bash
./test-rules.sh
```
| Variation of the docs' Pod | Result |
|---|---|
| docs spec | `pod/hostprocess-demo created (server dry run)` |
| no `hostNetwork` | `spec.hostNetwork: Invalid value: false: hostNetwork must be true if pod contains any hostProcess containers` |
| `runAsNonRoot: true` | **accepted**. The API doesn't check this; the Windows kubelet refuses to start it. |
| 2nd container with `hostProcess: false` | `pod hostProcess value must be identical if both are specified, was true` **and** `If pod contains any hostProcess containers then all containers must be HostProcess containers` |
| 2nd container with nothing set | accepted: it inherits the pod-level `hostProcess: true` |
| `hostProcess` only on container 0 + a plain 2nd container | `If pod contains any hostProcess containers then all containers must be HostProcess containers` |
| `spec.os.name: linux` | `spec.securityContext.windowsOptions: Forbidden: windows options cannot be set for a linux pod` |
| `spec.os.name: windows` / `runAsUserName: hpc-localgroup` | accepted |

## Lab 2 – Pod Security admission (the page's "privileged profile" advice)
```bash
for lvl in privileged baseline restricted; do
  kubectl create ns hpc-$lvl; kubectl label ns hpc-$lvl pod-security.kubernetes.io/enforce=$lvl
  echo "== $lvl"; kubectl apply -n hpc-$lvl --dry-run=server -f hostprocess-pod.yaml
done
```
```
== privileged
pod/hostprocess-demo created (server dry run)
== baseline
… violates PodSecurity "baseline:latest": host namespaces (hostNetwork=true), hostProcess (pod must not set securityContext.windowsOptions.hostProcess=true)
== restricted
… violates PodSecurity "restricted:latest": host namespaces (hostNetwork=true), hostProcess (…), allowPrivilegeEscalation != false (…), unrestricted capabilities …
```

## Lab 3 – The Pod itself
```bash
kubectl apply -f hostprocess-pod.yaml
kubectl get pod hostprocess-demo            # Pending: nodeSelector kubernetes.io/os=windows matches no node
kubectl delete pod hostprocess-demo
```

## Lab 4 – A Linux look-alike you can run (not from the docs)
Linux has no `hostProcess` flag. The nearest equivalent is `hostNetwork` + `hostPID` + `privileged` + a hostPath of `/`:
```bash
kubectl apply -f linux-host-pod.yaml
kubectl wait --for=condition=Ready pod/linux-host-demo
kubectl get pod linux-host-demo -o wide          # IP 192.168.58.2 = the node's IP
kubectl exec linux-host-demo -- sh -c 'hostname; ip -4 -o addr show eth0 | awk "{print \$4}";
  ps -o pid,comm | grep -E "kubelet|containerd$|kube-apiserver"; chroot /host systemctl is-active kubelet'
```
```
minikube                <- the node's hostname
192.168.58.2/24         <- the node's NIC
  441 containerd        <- host processes are visible (hostPID)
  591 kubelet
 1358 kube-apiserver
active                  <- and manageable (chroot into the host's /)
```
That is the power a HostProcess container has on Windows, and why only cluster operators should get it.

## Troubleshooting on real Windows nodes
`failed to create user process token: failed to logon user: Access is denied.: unknown` means containerd itself isn't running
as `LocalSystem` or `LocalService`. User accounts, even Administrators, can't create logon tokens for the HostProcess users.

## Useful commands
```bash
kubectl explain pod.spec.securityContext.windowsOptions.hostProcess
kubectl get pods -A -o json | jq -r '.items[] | select(.spec.securityContext.windowsOptions.hostProcess==true) | .metadata.namespace+"/"+.metadata.name'
```

## Cleanup
```bash
./cleanup.sh
```
