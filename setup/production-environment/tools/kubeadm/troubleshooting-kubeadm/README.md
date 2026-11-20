# Troubleshooting kubeadm – Hands-on Lab

Based on: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/troubleshooting-kubeadm/

> The page is a catalogue of known problems. Here each one that can still happen with kubeadm **v1.37.2** is reproduced on machines
> **cp1** + **w1** ([../machines.sh](../machines.sh), cluster as in [../create-cluster-kubeadm](../create-cluster-kubeadm/)). The rest are
> marked as historical with a check that shows why.
>
> **Found:**
> - **`--apiserver-extra-args` / `--component-extra-args` no longer exist.** `kubeadm init --apiserver-extra-args "enable-admission-plugins=…"`
>   → `error: unknown flag: --apiserver-extra-args`. The whole "comma separated list" section is about removed flags; the config file
>   (`apiServer.extraArgs`, see [../control-plane-flags](../control-plane-flags/)) is the only way.
> - **No `ebtables`/`ethtool` preflight warnings any more.** With both binaries moved away, `kubeadm init phase preflight` printed no
>   warning about them (only the Swap warning).
> - The TLS error text has changed with newer Go: `Unable to connect to the server: tls: failed to verify certificate: x509: certificate
>   signed by unknown authority` (the page shows the old `x509: … (possibly because of "crypto/rsa: verification error" …)`).
> - **Kubelet client certificate recovery works as described.** Small differences:
>   - `kubeadm kubeconfig user --org system:nodes --client-name system:node:w1` wrote `server: https://172.30.0.2:6443` (the control
>     plane node's own address), not the cluster's `controlPlaneEndpoint` (`cluster-endpoint:6443`, what w1 used). That's the "adjust the
>     … server endpoint" step.
>   - `kubelet-client-current.pem` was back **4 s** after the restart (CSR `system:node:w1` auto-approved).
> - **CoreDNS isn't always `Pending` before the network add-on.** On a machine that had been `kubeadm reset`, the old
>   `/etc/cni/net.d/10-kindnet.conflist` was still there, so CoreDNS got IPs and showed `Running 0/1` while the node was `NotReady`.
>   `kubeadm reset` doesn't clean CNI config.
> - (Lab) a restarted machine loses its `/etc/hosts` additions, because Docker regenerates the file. kubectl then fails with
>   `lookup cluster-endpoint … server misbehaving`, as it would on any host whose name resolution for the endpoint breaks.

## Key ideas (read first)

| Symptom | Where to look |
|---|---|
| `kubeadm init` waits for the control plane | `crictl ps -a` / `crictl logs <id>` on the node (the page still says `docker ps`) |
| `kubeadm reset` hangs removing containers | restart the container runtime, `crictl` |
| Pods `RunContainerError`/`CrashLoopBackOff` right after the network add-on | the add-on (RBAC, version) |
| CoreDNS `Pending` | expected until a Pod network is installed |
| HostPort / hairpin | depends on the CNI (portmap plugin, hairpin mode) |
| `x509: certificate signed by unknown authority` | the kubeconfig's CA (`base64 --decode` + `openssl x509`) |
| kubelet cert expired / missing | regenerate `kubelet.conf` with `kubeadm kubeconfig user`, let the kubelet rotate |
| metrics-server TLS errors | kubelet serving certs are self-signed unless `serverTLSBootstrap` |

## Lab 1 – Historical entries, checked
```bash
./machines.sh x cp1 'kubeadm init --apiserver-extra-args "enable-admission-plugins=LimitRanger,NamespaceExists" --dry-run'
#   error: unknown flag: --apiserver-extra-args
./machines.sh x cp1 'mv /usr/sbin/ebtables{,.off}; mv /usr/sbin/ethtool{,.off}; kubeadm init phase preflight; mv /usr/sbin/ebtables{.off,}; mv /usr/sbin/ethtool{.off,}'
#   only [WARNING Swap] – no ebtables/ethtool warnings
kubectl get clusterrolebinding kubeadm:get-nodes -o jsonpath='{.subjects[0].name}'
#   system:bootstrappers:kubeadm:default-node-token      <- the v1.17/1.18 RBAC workaround is built in
```
Also historical (no lab): Docker 1.13 on CentOS 7 (etcd restarts), the `kubeadm upgrade plan` external-etcd message (fixed in 1.19),
`kubeadm reset` unmounting `/var/lib/kubelet` (fixed in 1.20), the etcd hash upgrade bug (only v1.28.0–v1.28.2), and flannel in Vagrant.

## Lab 2 – No Pod network yet
```bash
./machines.sh x cp1 'kubeadm init --config kubeadm-config.yaml'; # w1 joins
kubectl get nodes                                # cp1 NotReady, w1 NotReady
kubectl -n kube-system get pods -l k8s-app=kube-dns
#   coredns-…   0/1   Running     <- not Pending: stale 10-kindnet.conflist from an earlier kubeadm reset (see Found)
```

## Lab 3 – TLS certificate errors
```bash
cp /etc/kubernetes/admin.conf bad.conf          # then put the front-proxy CA into certificate-authority-data
KUBECONFIG=bad.conf kubectl get pods
#   Unable to connect to the server: tls: failed to verify certificate: x509: certificate signed by unknown authority
grep certificate-authority-data bad.conf | awk '{print $2}' | base64 --decode | openssl x509 -noout -subject      # CN = front-proxy-ca
grep certificate-authority-data /etc/kubernetes/admin.conf | awk '{print $2}' | base64 --decode | openssl x509 -noout -subject   # CN = kubernetes
```

## Lab 4 – Kubelet client certificate rotation fails (the page's procedure)
```bash
# break it on w1 (step 1: back up, delete)
./machines.sh x w1 'rm /etc/kubernetes/kubelet.conf /var/lib/kubelet/pki/kubelet-client*; systemctl restart kubelet'
#   kubelet: failed to run Kubelet: unable to load bootstrap kubeconfig: stat /etc/kubernetes/bootstrap-kubelet.conf: no such file or directory
#   kubectl get node w1 → NotReady
# step 2, on cp1 (has /etc/kubernetes/pki/ca.key):
kubeadm kubeconfig user --org system:nodes --client-name system:node:w1 > kubelet.conf
#   server: https://172.30.0.2:6443   cluster: kubernetes   user: system:node:w1   (embedded client cert)
# step 3–4: copy to w1:/etc/kubernetes/kubelet.conf, systemctl restart kubelet
#   kubelet-client-current.pem recreated after ~4s
#   kubectl get csr → csr-2t847  kubernetes.io/kube-apiserver-client-kubelet  system:node:w1  Approved,Issued
# step 5–6: in kubelet.conf replace client-certificate-data/client-key-data with
#   client-certificate: /var/lib/kubelet/pki/kubelet-client-current.pem
#   client-key: /var/lib/kubelet/pki/kubelet-client-current.pem
#   (and set server back to https://cluster-endpoint:6443), restart the kubelet
# step 7:
kubectl get nodes                                # w1 Ready
```

## Lab 5 – Why metrics-server can't verify kubelets
```bash
./machines.sh x cp1 'echo | openssl s_client -connect 172.30.0.3:10250 -CAfile /etc/kubernetes/pki/ca.crt'
#   subject=CN = w1@1795170907   issuer=CN = w1-ca@1795170907
#   Verify return code: 19 (self-signed certificate in certificate chain)        → "x509: certificate signed by unknown authority"
#   X509v3 Subject Alternative Name: DNS:w1                                       → "certificate is valid for … not <IP>"
./machines.sh x w1 'grep serverTLSBootstrap /var/lib/kubelet/config.yaml'       # (not set)
```
Fix: `serverTLSBootstrap: true` + approving the serving CSRs (see
[tasks/…/kubeadm-certs](../../../../../tasks/administer-cluster/kubeadm/kubeadm-certs/)).

## Cleanup
```bash
./machines.sh x w1 'kubeadm reset -f'; ./machines.sh x cp1 'kubeadm reset -f'
```
