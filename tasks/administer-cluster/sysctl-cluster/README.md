# Using sysctls in a Kubernetes Cluster – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/administer-cluster/sysctl-cluster/

> This runs on a throwaway profile **`sysctl-lab`**, started with the docs' own minikube command, which allow-lists two unsafe sysctls. Files:
> - [01-sysctl-example.yaml](01-sysctl-example.yaml): the docs' Pod, with its `securityContext` **verbatim**; the `...` is filled with a printing container.
> - [kubelet-default-pod-sysctls-docs.yaml](kubelet-default-pod-sysctls-docs.yaml): the docs' `defaultPodSysctls` kubelet config, **verbatim**.
> - The other numbered files test the page's rules and are labelled "not from the docs".

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **Namespaced vs node-level** | Only *namespaced* sysctls (`kernel.shm*`, `kernel.msg*`, `kernel.sem`, `fs.mqueue.*`, most `net.*`) can be set per Pod. Node-level ones (e.g. `vm.swappiness`) can't. |
| **Safe** | Isolated between Pods, always allowed: `kernel.shm_rmid_forced`, `net.ipv4.ip_local_port_range`, `tcp_syncookies`, `ping_group_range`, `ip_unprivileged_port_start`, `ip_local_reserved_ports`, `tcp_keepalive_*`, `tcp_fin_timeout`, `tcp_rmem/wmem`, and since 1.37 `tcp_slow_start_after_idle`, `tcp_notsent_lowat`. |
| **Unsafe** | Every other namespaced sysctl, allowed per node with the kubelet's `--allowed-unsafe-sysctls` (globs allowed). Otherwise the Pod is rejected by the kubelet (`SysctlForbidden`), *after* scheduling, so use taints and tolerations to steer such Pods. |
| **hostNetwork** | `net.*` sysctls are not allowed with `hostNetwork: true`. |
| **`defaultPodSysctls`** | Gate `DefaultPodSysctls` (alpha): the kubelet applies node-wide defaults to every new Pod's sandbox (safe *and* unsafe, no allow-list needed). Pod values win per key. Defaults are skipped for shared host namespaces. The kubelet refuses non-namespaced keys at startup. |

---

## Step 0 – a node that allows two unsafe sysctls (the docs' minikube command)
```bash
cd tasks/administer-cluster/sysctl-cluster
minikube start -p sysctl-lab --memory 2200 --cpus 2 --kubernetes-version v1.37.0 \
  --extra-config="kubelet.allowed-unsafe-sysctls=kernel.msg*,net.core.somaxconn"
kubectl config use-context minikube; K="kubectl --context sysctl-lab"
minikube ssh -p sysctl-lab -- 'ps -o args= -C kubelet' | tr ' ' '\n' | grep sysctl
#   --allowed-unsafe-sysctls=kernel.msg*,net.core.somaxconn
```

## Lab 1 – The docs' Pod (1 safe + 2 unsafe sysctls)
```bash
$K apply -f 01-sysctl-example.yaml && $K wait --for=condition=Ready pod/sysctl-example
$K logs sysctl-example
#   kernel.shm_rmid_forced=0
#   net.core.somaxconn=1024
#   kernel.msgmax=65536
# the same Pod on a node WITHOUT the allow-list (the default minikube cluster):
kubectl --context minikube apply -f 01-sysctl-example.yaml
kubectl --context minikube get po sysctl-example -o jsonpath='{.status.phase} {.status.reason}: {.status.message}{"\n"}'
#   Failed SysctlForbidden: Pod was rejected: forbidden sysctl: "net.core.somaxconn" not allowlisted
kubectl --context minikube delete -f 01-sysctl-example.yaml
```

## Lab 2 – What isn't allowed
```bash
$K apply -f 02-not-allowed.yaml     # kernel.sem: namespaced, unsafe, not allow-listed
#   sysctl-not-allowed: Failed SysctlForbidden: Pod was rejected: forbidden sysctl: "kernel.sem" not allowlisted
$K apply -f 03-node-level.yaml      # vm.swappiness: node-level
#   sysctl-node-level: Failed SysctlForbidden: Pod was rejected: forbidden sysctl: "vm.swappiness" not allowlisted
$K apply -f 04-hostnetwork.yaml     # safe net.* sysctl + hostNetwork
#   The Pod "sysctl-hostnetwork" is invalid: spec.securityContext.sysctls[0].name: Invalid value: "net.ipv4.ip_local_port_range":
#   may not be specified when 'hostNetwork' is true         <- rejected by the API server, never created
```
(`net.ipv4.tcp_fin_timeout` is a tempting "unsafe" example, but it has been **safe** since 1.29. A Pod using it simply runs.)

## Lab 3 – Default sysctls for all Pods (`defaultPodSysctls`)
```bash
minikube -p sysctl-lab cp kubelet-default-pod-sysctls-docs.yaml /tmp/dps.yaml
minikube ssh -p sysctl-lab -- 'sudo bash -c "cp /var/lib/kubelet/config.yaml /root/; grep -vE \"^(apiVersion|kind):\" /tmp/dps.yaml >> /var/lib/kubelet/config.yaml; systemctl restart kubelet"'
$K apply -f 05-default-sysctls-check.yaml        # Pods: plain, override (somaxconn=2048), hostnet
$K logs plain
#   net.ipv4.ip_forward=1   net.core.somaxconn=1024   net.ipv4.tcp_rmem=4096 87380 16777216
#   kernel.msgmax=65536     kernel.sem=250 32000 32 128   fs.mqueue.msg_max=1024           <- all from the kubelet defaults
$K logs override
#   net.core.somaxconn=2048  (Pod wins for this key)   ... all other defaults still applied
$K logs hostnet
#   net.ipv4.ip_forward=1  net.core.somaxconn=4096  net.ipv4.tcp_rmem=4096 131072 33554432   <- the NODE's own net.* values: skipped
#   kernel.msgmax=65536  kernel.sem=250 32000 32 128  fs.mqueue.msg_max=1024                  <- IPC defaults still applied (no hostIPC)
```
`kernel.sem` was applied although it isn't in `allowed-unsafe-sysctls`: node-admin defaults need no allow-list. `user.max_user_namespaces` only applies to Pods with `hostUsers: false`, which minikube's Docker node can't run (see [../kubelet-in-userns](../kubelet-in-userns/)).

Validation, with a node-level key added to `defaultPodSysctls`:
```bash
#   vm.swappiness: "10"
#   "command failed" err="failed to validate kubelet configuration, error: invalid configuration: \"vm.swappiness\" is not known to be namespaced for defaultPodSysctls ..."
```

---

## Useful commands
```bash
sysctl -a | grep <name>                                  # on a node
kubectl exec <pod> -- sysctl -n <name>
kubectl get po <pod> -o jsonpath='{.status.reason}: {.status.message}'
```

## Cleanup
```bash
minikube delete -p sysctl-lab
```
