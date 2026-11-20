# Customizing components with the kubeadm API – Hands-on Lab

Based on: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/control-plane-flags/

> Runs on machine **cp1** from [../machines.sh](../machines.sh) (kubeadm v1.37.2, see [../create-cluster-kubeadm](../create-cluster-kubeadm/)).
> [docs-snippets/](docs-snippets/) holds the page's nine YAML examples **verbatim** (01–04 component flags, 05–08 patches, 09 `dns.disabled`).
> [lab-config.yaml](lab-config.yaml) (NOT from the docs) combines them into one config that works on v1.37, together with
> [schedconfig.yaml](schedconfig.yaml) and [patches/](patches/).
>
> **Found:**
> - **None of the four component examples is usable with kubeadm v1.37 as written** (`kubeadm config validate`):
>   - 01–03: `this version of kubeadm only supports deploying clusters with the control plane version >= 1.36.0. Current version: v1.16.0`
>     (`kubernetesVersion: v1.16.0`)
>   - 04 (etcd): `json: cannot unmarshal number into Go struct field Arg.etcd.local.extraArgs.value of type string`. v1beta4 extraArgs
>     values are strings: `value: "1000"`.
>   - 02 (controllerManager): kube-controller-manager crash-loops with **`Error: unknown flag: --deployment-controller-sync-period`**
>     (the flag no longer exists). The control plane never comes up: `kubeadm init` fails with `could not bootstrap the admin user …
>     context deadline exceeded`.
> - **The APIServer example switches off NodeRestriction.** `enable-admission-plugins: "AlwaysPullImages,DefaultStorageClass"` *replaces*
>   kubeadm's default `--enable-admission-plugins=NodeRestriction`. Afterwards the kubelet can set restricted labels on itself:
>   `kubectl --kubeconfig /etc/kubernetes/kubelet.conf label node cp1 node-role.kubernetes.io/worker=` → `node/cp1 labeled`
>   (forbidden in [../create-cluster-kubeadm](../create-cluster-kubeadm/)). Always repeat `NodeRestriction` when overriding this flag.
> - `audit-log-path` alone gives nothing visible. There's no extraVolume for `/var/log/kubernetes` (the apiserver Pod mounts only certs,
>   pki and /etc/hosts), and audit logging also needs `--audit-policy-file`.
> - `kubeadm init phase addon coredns --print-manifest --config my-config.yaml`` has a stray backtick: the shell answers
>   `unexpected EOF while looking for matching ``'`. Without it, it prints the Deployment, ConfigMap, Service and RBAC (`replicas: 1`
>   with the CoreDNS patch).
> - The scheduler example's `--config` file must name the kubeconfig itself (`clientConnection.kubeconfig: /etc/kubernetes/scheduler.conf`).
>   With `--config`, kube-scheduler takes its connection settings from the file.
> - (Lab pitfall, not a docs bug) a `+merge` patch is an RFC 7386 JSON merge patch: **lists are replaced**. My first
>   `kube-apiserver0+merge.yaml` with `spec.containers: [{name, resources}]` removed image and command, and kube-apiserver never started.
>   For container fields use the default **strategic** type (`kube-apiserver0+strategic.yaml` or no suffix), which merges list entries
>   by `name`.
> - Snippet 06 (JoinConfiguration with only `patches`) is a fragment: `discovery: Invalid value: "": bootstrapToken or file must be set`.

## Key ideas (read first)

| Mechanism | Scope | Use for |
|---|---|---|
| `ClusterConfiguration.<component>.extraArgs` (`name`/`value`, strings) | **cluster-wide** (stored in the kubeadm-config ConfigMap) | flags for apiserver, controller-manager, scheduler, etcd |
| `extraVolumes` | cluster-wide | files the flags point at (hostPath → mountPath) |
| `patches.directory` in Init/Join/UpgradeConfiguration | **per node**, last step before writing | `target[suffix][+strategic\|merge\|json].yaml\|json`, targets: kube-apiserver, kube-controller-manager, kube-scheduler, etcd, kubeletconfiguration, corednsdeployment |
| `KubeletConfiguration` next to the kubeadm config | base for all kubelets | per-node changes: `kubeletconfiguration` patch or `nodeRegistration.kubeletExtraArgs` |
| `KubeProxyConfiguration` | all kube-proxy Pods (DaemonSet) | |
| `dns.disabled: true` / `corednsdeployment` patch | CoreDNS | the CoreDNS ConfigMap can't be patched by kubeadm |
| Upgrades | | pass the same patches again (`UpgradeConfiguration.apply/node.patches`) |

## Lab 1 – The docs' examples as written
```bash
cd setup/production-environment/tools/kubeadm/control-plane-flags
docker cp docs-snippets kadm-cp1:/root/
../machines.sh x cp1 'cd docs-snippets; for f in *.yaml; do echo "$f: $(kubeadm config validate --config $f 2>&1 | head -1)"; done'
#   01–03: error: this version of kubeadm only supports … >= 1.36.0. Current version: v1.16.0
#   04:    error: … cannot unmarshal number into Go struct field Arg.etcd.local.extraArgs.value of type string
#   05, 07, 08: ok      06: discovery: Invalid value: "": bootstrapToken or file must be set
```

## Lab 2 – Everything at once (lab-config.yaml)
```bash
docker cp lab-config.yaml kadm-cp1:/root/; docker cp schedconfig.yaml kadm-cp1:/root/; docker cp patches kadm-cp1:/root/
../machines.sh x cp1 'kubeadm config validate --config lab-config.yaml'      # ok
../machines.sh x cp1 'kubeadm init --config lab-config.yaml'
#   [patches] Reading patches from path "/root/patches"
#   [patches] Applied patch of type "application/strategic-merge-patch+json" to target "kube-apiserver"
#   [patches] Applied patch of type "application/merge-patch+json" to target "kubeletconfiguration"
#   [patches] Applied patch of type "application/merge-patch+json" to target "corednsdeployment"
#   Your Kubernetes control-plane has initialized successfully!
```
Check every customization (on cp1, `M=/etc/kubernetes/manifests`):
```bash
grep -oE -- '--(enable-admission-plugins|audit-log-path)=[^ ]*' $M/kube-apiserver.yaml
#   --enable-admission-plugins=AlwaysPullImages,DefaultStorageClass      <- NodeRestriction gone!
#   --audit-log-path=/var/log/kubernetes/audit.log
grep -E 'patched-by|cpu: 300m' $M/kube-apiserver.yaml              # lab.example.com/patched-by: kubeadm-patches / cpu: 300m   (patch)
grep -oE -- '--concurrent-deployment-syncs=[^ ]*' $M/kube-controller-manager.yaml   # =10
grep -oE -- '--config=[^ ]*' $M/kube-scheduler.yaml                 # --config=/etc/kubernetes/scheduler-config.yaml (+ hostPath volume)
grep -oE -- '--election-timeout=[^ ]*' $M/etcd.yaml                 # =1000
grep maxPods /var/lib/kubelet/config.yaml                            # maxPods: 50                (kubeletconfiguration patch)
cat /var/lib/kubelet/kubeadm-flags.env                               # --node-labels=lab.example.com/via=kubeletExtraArgs
kubectl -n kube-system get cm kube-proxy -o jsonpath='{.data.config\.conf}' | grep metricsBindAddress    # 0.0.0.0:10249
kubectl -n kube-system get deploy coredns -o jsonpath='{.spec.replicas}'                                # 1   (corednsdeployment patch)
# second scheduler profile from schedconfig.yaml:
kubectl run sched-test --image=registry.k8s.io/pause:3.10.2 --overrides='{"spec":{"schedulerName":"lab-scheduler","hostNetwork":true}}'
#   Scheduled   lab-scheduler   Successfully assigned default/sched-test to cp1
# NodeRestriction check:
kubectl --kubeconfig /etc/kubernetes/kubelet.conf label node cp1 node-role.kubernetes.io/worker=     # node/cp1 labeled   (!)
kubeadm init phase addon coredns --print-manifest --config lab-config.yaml       # Deployment/ConfigMap/Service/RBAC, replicas: 1
```

## Cleanup
```bash
../machines.sh x cp1 'kubeadm reset -f'      # machine stays for the next kubeadm labs; ../machines.sh down removes all
```
