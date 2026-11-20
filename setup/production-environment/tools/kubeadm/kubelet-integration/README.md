# Configuring each kubelet in your cluster using kubeadm – Hands-on Lab

Based on: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/kubelet-integration/

> Runs on machines **cp1** + **w1** from [../machines.sh](../machines.sh) (kubeadm/kubelet v1.37.2 from pkgs.k8s.io).
> [kubelet-integration-config.yaml](kubelet-integration-config.yaml) (NOT from the docs) is the page's `kubeadm init --service-cidr 10.96.0.0/12`
> plus its `KubeletConfiguration` (`clusterDNS: [10.96.0.10]`) as one config, with the lab basics (endpoint, Pod CIDR, swap).
>
> **Found:**
> - **"Currently, the kubelet cannot automatically detect the cgroup driver used by the container runtime"** is outdated. The kubelet logs
>   `"Using cgroup driver setting received from the CRI runtime" cgroupDriver="systemd"`, as the Container Runtimes page says
>   (RuntimeConfig CRI RPC).
> - **`kubeadm-flags.env` is empty:** `KUBELET_KUBEADM_ARGS=""` on both nodes. It contains no "dynamic parameters such as the cgroup driver";
>   the CRI endpoint moved to `/var/lib/kubelet/instance-config.yaml` (`containerRuntimeEndpoint: "unix:///var/run/containerd/containerd.sock"`).
>   Only `nodeRegistration.kubeletExtraArgs` end up in it (see [../control-plane-flags](../control-plane-flags/): `--node-labels=…`).
> - **"A kubelet configuration file is also written to `/etc/kubernetes/kubelet.conf` with the baseline cluster-wide configuration"**:
>   kubelet.conf is a **kubeconfig** (`kind: Config`, `client-certificate: /var/lib/kubelet/pki/kubelet-client-current.pem`). The
>   cluster-wide configuration is `/var/lib/kubelet/config.yaml` + the `kube-system/kubelet-config` ConfigMap.
> - **A `local-overrides.conf` drop-in that sets `KUBELET_EXTRA_ARGS` does nothing on a package install.** The `kubelet` deb ships
>   `/etc/default/kubelet` containing `KUBELET_EXTRA_ARGS=` (empty), and systemd lets `EnvironmentFile=` override `Environment=`.
>   Measured with `--max-pods`: drop-in only → 33 ✓; drop-in + `/etc/default/kubelet` with 42 → 42; drop-in + the package's empty file →
>   **no flag, 110**. Put kubelet flags in `/etc/default/kubelet` (as the page's flag-chain list says) or override `ExecStart` in the drop-in.
> - The `cri-tools` package in the page's table wasn't installed. `apt-get install kubelet kubeadm kubectl` pulled in only `kubernetes-cni`
>   (`dpkg -l cri-tools` → no packages found). crictl on these machines comes from the kicbase image.
> - `/usr/lib/systemd/system/kubelet.service.d/10-kubeadm.conf` matches the page's sample exactly (comments aside).

## Key ideas (read first)

| File | Written by | Holds |
|---|---|---|
| `/var/lib/kubelet/config.yaml` | `kubeadm init` (from the config) / `kubeadm join` (from the `kubelet-config` ConfigMap) | the cluster-wide `KubeletConfiguration` (clusterDNS, cgroupDriver …) |
| `kube-system/kubelet-config` ConfigMap | `kubeadm init` | the same, for joining nodes |
| `/var/lib/kubelet/instance-config.yaml` | init/join | per-node settings (CRI endpoint) |
| `/var/lib/kubelet/kubeadm-flags.env` | init/join | `KUBELET_KUBEADM_ARGS` (kubeletExtraArgs) |
| `/etc/kubernetes/bootstrap-kubelet.conf` | join (temporary) | bootstrap token + CA for TLS bootstrap; deleted afterwards |
| `/etc/kubernetes/kubelet.conf` | init/join | the kubelet's kubeconfig (its own client cert) |
| `/etc/default/kubelet` | the deb package (empty) / you | `KUBELET_EXTRA_ARGS`, last in the flag chain |
| `10-kubeadm.conf` drop-in | the kubeadm package; kubeadm never edits it | wires all of the above into `ExecStart` |

## Lab 1 – Cluster-wide configuration (init)
```bash
cd setup/production-environment/tools/kubeadm
docker cp kubelet-integration/kubelet-integration-config.yaml kadm-cp1:/root/
./machines.sh x cp1 'kubeadm init --config kubelet-integration-config.yaml'
#   [kubelet-start] Writing kubelet environment file with flags to file "/var/lib/kubelet/kubeadm-flags.env"
#   [kubelet-start] Writing kubelet configuration to file "/var/lib/kubelet/instance-config.yaml"
#   [kubelet-start] Writing kubelet configuration to file "/var/lib/kubelet/config.yaml"
#   [kubelet-start] Starting the kubelet
./machines.sh x cp1 'cat /var/lib/kubelet/kubeadm-flags.env'        # KUBELET_KUBEADM_ARGS=""
./machines.sh x cp1 'cat /var/lib/kubelet/instance-config.yaml'     # containerRuntimeEndpoint: "unix:///var/run/containerd/containerd.sock"
./machines.sh x cp1 'grep -E "cgroupDriver|clusterDNS" -A1 /var/lib/kubelet/config.yaml'    # cgroupDriver: systemd / clusterDNS: - 10.96.0.10
./machines.sh x cp1 'grep ^kind /etc/kubernetes/kubelet.conf'      # kind: Config   (a kubeconfig)
./machines.sh x cp1 'journalctl -u kubelet | grep "cgroup driver"' # "Using cgroup driver setting received from the CRI runtime" cgroupDriver="systemd"
./machines.sh x cp1 'kubeadm config print init-defaults --component-configs KubeletConfiguration'   # all defaults (documented command)
```

## Lab 2 – Join: TLS bootstrap and the ConfigMap
```bash
./machines.sh x cp1 'KUBECONFIG=/etc/kubernetes/admin.conf kubectl -n kube-system get cm kubelet-config -o jsonpath="{.data.kubelet}"' | grep -A1 clusterDNS
#   clusterDNS: - 10.96.0.10
./machines.sh x w1 'kubeadm join cluster-endpoint:6443 --token … --discovery-token-ca-cert-hash sha256:… --ignore-preflight-errors=Swap'
#   [kubelet-start] Writing … instance-config.yaml / config.yaml / kubeadm-flags.env, Starting the kubelet,
#   Waiting for the kubelet to perform the TLS Bootstrap
#   (a background poll saw /etc/kubernetes/bootstrap-kubelet.conf during the join)
./machines.sh x w1 'ls /etc/kubernetes; ls /var/lib/kubelet/pki'
#   kubelet.conf manifests pki                     <- bootstrap-kubelet.conf deleted
#   kubelet-client-2026-11-20-10-08-12.pem, kubelet-client-current.pem -> …, kubelet.crt, kubelet.key
./machines.sh x w1 'grep -A1 clusterDNS /var/lib/kubelet/config.yaml'   # - 10.96.0.10   (downloaded from the ConfigMap)
```

## Lab 3 – Overrides and the drop-in (w1, measured as `node.status.allocatable.pods`)
```bash
./machines.sh x w1 'cat /etc/default/kubelet'          # KUBELET_EXTRA_ARGS=        (shipped by the kubelet package: dpkg -S → kubelet)
# default                                                → 110
echo 'KUBELET_EXTRA_ARGS=--max-pods=42' > /etc/default/kubelet; systemctl restart kubelet           → 42   (beats config.yaml)
printf '[Service]\nEnvironment="KUBELET_EXTRA_ARGS=--max-pods=33"\n' > /etc/systemd/system/kubelet.service.d/local-overrides.conf
systemctl daemon-reload; systemctl restart kubelet                                                   → 42   (EnvironmentFile wins)
rm /etc/default/kubelet; systemctl restart kubelet                                                   → 33
echo 'KUBELET_EXTRA_ARGS=' > /etc/default/kubelet; systemctl restart kubelet                         → 110  (drop-in silently ignored)
systemctl show kubelet -p DropInPaths
#   DropInPaths=/usr/lib/systemd/system/kubelet.service.d/10-kubeadm.conf /etc/systemd/system/kubelet.service.d/local-overrides.conf
```

## Cleanup
```bash
./machines.sh x w1 'rm -f /etc/systemd/system/kubelet.service.d/local-overrides.conf; systemctl daemon-reload; kubeadm reset -f'
./machines.sh x cp1 'kubeadm reset -f'          # machines stay for the next labs; ./machines.sh down removes them
```
