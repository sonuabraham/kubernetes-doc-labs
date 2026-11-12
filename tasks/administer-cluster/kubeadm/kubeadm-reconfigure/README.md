# Reconfiguring a kubeadm cluster – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-reconfigure/

> Runs on the throwaway profile **`kubeadm-lab`** ([../start-kubeadm-lab.sh](../start-kubeadm-lab.sh)). minikube bootstraps its node **with kubeadm**, so the cluster has the real `kubeadm-config` / `kubelet-config` / `kube-proxy` ConfigMaps and kubeadm static Pods. [../node.sh](../node.sh) runs commands on the node as root (`$KUBEADM`, `$PKI`).
>
> This page has no YAML examples, only commands. The commands are the docs' commands. Two helpers stand in for the interactive editor:
> - [edit-cm.py](edit-cm.py) is a non-interactive `kubectl edit cm`. It changes one field of the YAML document stored in a ConfigMap key.
> - `KUBE_EDITOR='sed -i ...' kubectl edit ...` is the docs' `kubectl edit` with sed as the "editor".
>
> **minikube differences** (found while testing):
> 1. The PKI lives in `/var/lib/minikube/certs` (`certificatesDir`).
> 2. The API server listens on **8443**, so `--config` must include the InitConfiguration ([write-config.sh](write-config.sh)).
> 3. minikube's kubelet drop-in **doesn't read `kubeadm-flags.env`** (Lab 3 fixes that).

## Key ideas (read first)

| Object | Where kubeadm keeps it | How to roll the change out |
|---|---|---|
| **ClusterConfiguration** | ConfigMap `kube-system/kubeadm-config`, key `ClusterConfiguration` | Regenerate the files on **each control-plane node**: `kubeadm init phase certs <c> --config f` (SANs) and `kubeadm init phase control-plane <c>` / `etcd local` (`extraArgs`, `extraVolumes`). The kubelet restarts the static Pod when its manifest changes. |
| **KubeletConfiguration** | ConfigMap `kubelet-config`, key `kubelet` | On each node: `kubeadm upgrade node phase kubelet-config` (writes `/var/lib/kubelet/config.yaml`), then `systemctl restart kubelet`. Node-specific flags go in `/var/lib/kubelet/kubeadm-flags.env`. |
| **KubeProxyConfiguration** | ConfigMap `kube-proxy`, key `config.conf` | `kubectl delete po -n kube-system -l k8s-app=kube-proxy`. It's a DaemonSet, so there's no per-node config. |
| **CoreDNS** | Deployment `coredns` + Service `kube-dns` | `kubectl rollout restart deployment -n kube-system coredns`. **Lost on `kubeadm upgrade apply`**. |
| **No validation** | ConfigMap data is just a string | A typo is stored as-is and only breaks the next time kubeadm or the component reads it. |
| **Persisting** | `kubeadm upgrade` rewrites manifests, `config.yaml`, CoreDNS and parts of the Node | Keep **kubeadm patches** (`<target>+strategic.yaml` in a `--patches` dir), flags in `kubeadm-flags.env`, and a `kubectl patch --patch-file` for the Node. |

---

## Step 0
```bash
cd tasks/administer-cluster/kubeadm
./start-kubeadm-lab.sh v1.37.0          # fresh profile, ~1 min
cd kubeadm-reconfigure
kubectl --context kubeadm-lab create ns reconfigure-demo
```

## Lab 1 – ClusterConfiguration: a new API server flag and a new SAN
Edit the ConfigMap. This is the docs' `kubectl edit cm -n kube-system kubeadm-config`.
```bash
./edit-cm.py kubeadm-config ClusterConfiguration \
  'd["apiServer"]["extraArgs"].append({"name":"service-node-port-range","value":"30000-30100"}); d["apiServer"]["certSANs"].append("kubeadm-lab.example.com")'
kubectl --context kubeadm-lab -n kube-system get cm kubeadm-config -o jsonpath='{.data.ClusterConfiguration}' | head -12
#   apiServer:
#     certSANs: [127.0.0.1, localhost, 192.168.175.2, kubeadm-lab.example.com]   (one per line)
#     extraArgs:
#     - name: enable-admission-plugins ...
#     - name: service-node-port-range
#       value: 30000-30100
```
Nothing on the node has changed yet:
```bash
kubectl --context kubeadm-lab -n reconfigure-demo create service nodeport np-before --tcp=80:80 --node-port=31000
#   service/np-before created              <- still the default 30000-32767 range
kubectl --context kubeadm-lab --tls-server-name kubeadm-lab.example.com get ns reconfigure-demo
#   x509: certificate is valid for control-plane.minikube.internal, kubeadm-lab, ..., not kubeadm-lab.example.com
```
Make the `<config-file>` (InitConfiguration + the updated ClusterConfiguration) and **back up `/etc/kubernetes`** as the docs ask. On minikube, back up the certs dir too:
```bash
./write-config.sh
#   wrote /root/kubeadm.yaml (60 lines)
#   kind: InitConfiguration    bindPort: 8443    - kubeadm-lab.example.com    - name: service-node-port-range    kind: ClusterConfiguration
../node.sh 'cp -a /etc/kubernetes /root/etc-kubernetes.bak; cp -a $PKI /root/certs.bak'
```
**New certificate**:
```bash
../node.sh '$KUBEADM init phase certs apiserver --config /root/kubeadm.yaml'
#   [certs] Using existing apiserver certificate and key on disk     <- kubeadm reuses a cert that is still valid, so the SAN is NOT added
../node.sh 'mv $PKI/apiserver.crt $PKI/apiserver.key /root/; $KUBEADM init phase certs apiserver --config /root/kubeadm.yaml'
#   [certs] Generating "apiserver" certificate and key
#   [certs] apiserver serving cert is signed for DNS names [control-plane.minikube.internal kubeadm-lab kubeadm-lab.example.com
#           kubernetes ... localhost] and IPs [10.96.0.1 192.168.175.2 127.0.0.1]
```
(minikube's own cert also had `minikubeCA` and `10.0.0.1` and was valid for 3 years. The kubeadm cert is valid for 1 year: `certificateValidityPeriod`.)

**New static Pod manifest.** The kubelet notices the changed file and restarts the API server, which also loads the new cert:
```bash
../node.sh 'cp /etc/kubernetes/manifests/kube-apiserver.yaml /root/kube-apiserver.before.yaml
  $KUBEADM init phase control-plane apiserver --config /root/kubeadm.yaml
  diff /root/kube-apiserver.before.yaml /etc/kubernetes/manifests/kube-apiserver.yaml'
#   [control-plane] Creating static Pod manifest for "kube-apiserver"
#   > - --service-node-port-range=30000-30100
until kubectl --context kubeadm-lab get --raw /readyz >/dev/null 2>&1; do sleep 2; done
kubectl --context kubeadm-lab -n reconfigure-demo create service nodeport np-after --tcp=80:80 --node-port=31001
#   Invalid value: 31001: provided port is not in the valid range. The range of valid ports is 30000-30100
kubectl --context kubeadm-lab -n reconfigure-demo create service nodeport np-ok --tcp=80:80 --node-port=30080
#   service/np-ok created            (np-before keeps its 31000: existing Services are not re-validated)
kubectl --context kubeadm-lab --tls-server-name kubeadm-lab.example.com get ns reconfigure-demo
#   reconfigure-demo   Active        <- new SAN served
kubectl --context kubeadm-lab --tls-server-name other.example.com get ns reconfigure-demo
#   x509: certificate is valid for ..., kubeadm-lab.example.com, ..., not other.example.com
```
On a real HA cluster, repeat the cert and manifest steps on each control-plane node, one node at a time.

## Lab 2 – KubeletConfiguration
```bash
kubectl --context kubeadm-lab get node kubeadm-lab -o jsonpath='{.status.capacity.pods}{"\n"}'     # 110
./edit-cm.py kubelet-config kubelet 'd["maxPods"]=50'          # = kubectl edit cm -n kube-system kubelet-config
../node.sh 'grep -c maxPods /var/lib/kubelet/config.yaml'                                            # 0 - the node file is unchanged
../node.sh '$KUBEADM upgrade node phase kubelet-config; grep maxPods /var/lib/kubelet/config.yaml; systemctl restart kubelet'
#   [upgrade] Backing up kubelet config file to /etc/kubernetes/tmp/kubeadm-kubelet-config-<date>/config.yaml
#   [kubelet-start] Writing kubelet configuration to file "/var/lib/kubelet/config.yaml"
#   [upgrade/kubelet-config] The kubelet configuration for this node was successfully upgraded!
#   maxPods: 50
sleep 15; kubectl --context kubeadm-lab get node kubeadm-lab -o jsonpath='{.status.capacity.pods}{"\n"}'   # 50
```

## Lab 3 – Node-specific kubelet flags (`kubeadm-flags.env`)
```bash
../node.sh 'sed -i "s|^KUBELET_KUBEADM_ARGS=\"\(.*\)\"|KUBELET_KUBEADM_ARGS=\"\1 --max-pods=60\"|" /var/lib/kubelet/kubeadm-flags.env
  cat /var/lib/kubelet/kubeadm-flags.env; systemctl restart kubelet'
#   KUBELET_KUBEADM_ARGS="--node-ip=192.168.175.2 --max-pods=60"
sleep 15; kubectl --context kubeadm-lab get node kubeadm-lab -o jsonpath='{.status.capacity.pods}{"\n"}'   # still 50 !
../node.sh 'cat /etc/systemd/system/kubelet.service.d/10-kubeadm.conf'
#   ExecStart=/var/lib/minikube/binaries/v1.37.0/kubelet --bootstrap-kubeconfig=... --config=/var/lib/kubelet/config.yaml ... --node-ip=192.168.175.2
#   (minikube writes its own drop-in: no EnvironmentFile, no $KUBELET_KUBEADM_ARGS)
```
Give it what the kubeadm package's `10-kubeadm.conf` has:
```bash
../node.sh 'F=/etc/systemd/system/kubelet.service.d/10-kubeadm.conf; cp $F /root/10-kubeadm.conf.bak
  sed -i -e "s|^ExecStart=/.*|EnvironmentFile=-/var/lib/kubelet/kubeadm-flags.env\n& \$KUBELET_KUBEADM_ARGS|" $F
  systemctl daemon-reload; systemctl restart kubelet; sleep 3; ps -o args= -C kubelet | tr " " "\n" | grep max-pods'
#   Failed to allocate directory watch: Too many open files    <- host inotify limit, harmless here
#   --max-pods=60
sleep 15; kubectl --context kubeadm-lab get node kubeadm-lab -o jsonpath='{.status.capacity.pods}{"\n"}'   # 60  (flag beats config.yaml)
```

## Lab 4 – KubeProxyConfiguration
```bash
../node.sh 'curl -s 127.0.0.1:10249/configz' | python3 -c 'import json,sys;print(json.load(sys.stdin)["kubeproxy.config.k8s.io"]["iptables"])'
#   {... 'syncPeriod': '30s', 'minSyncPeriod': '1s'}
./edit-cm.py kube-proxy config.conf 'd["iptables"]["syncPeriod"]="45s"'      # = kubectl edit cm -n kube-system kube-proxy
#   (configz still says 30s - the running Pod read the file at start-up)
kubectl --context kubeadm-lab delete po -n kube-system -l k8s-app=kube-proxy
kubectl --context kubeadm-lab -n kube-system wait --for=condition=Ready po -l k8s-app=kube-proxy
../node.sh 'curl -s 127.0.0.1:10249/configz' | python3 -c 'import json,sys;print(json.load(sys.stdin)["kubeproxy.config.k8s.io"]["iptables"])'
#   {... 'syncPeriod': '45s', 'minSyncPeriod': '1s'}
```

## Lab 5 – CoreDNS, and why it doesn't survive an upgrade
```bash
K="kubectl --context kubeadm-lab -n kube-system"
KUBE_EDITOR='sed -i "s/memory: 170Mi/memory: 200Mi/"' $K edit deployment coredns
KUBE_EDITOR='sed -i "/^  labels:/a\    reconfigured: \"yes\""' $K edit service kube-dns
$K rollout restart deployment coredns && $K rollout status deployment coredns
$K get deploy coredns -o jsonpath='{.spec.template.spec.containers[0].resources.limits}{"\n"}'   # {"memory":"200Mi"}
$K get svc kube-dns --show-labels                                                               # ...,reconfigured=yes
```
Run only the CoreDNS step of `kubeadm upgrade apply`:
```bash
../node.sh '$KUBEADM upgrade apply phase addon coredns v1.37.0'
#   [addons] Applied essential addon: CoreDNS
$K get deploy coredns -o jsonpath='{.spec.template.spec.containers[0].resources.limits}{"\n"}'   # {"memory":"170Mi"}  <- reverted
$K get svc kube-dns --show-labels                                                               # reconfigured label gone
```

## Lab 6 – Persisting the reconfiguration
**Patches for kubeadm-managed objects.** Patch files live on the node, in a directory you pass to every `kubeadm init phase` / `kubeadm upgrade`:
- [patches/corednsdeployment+strategic.yaml](patches/corednsdeployment+strategic.yaml) sets the 200Mi limit
- [patches/kube-apiserver+strategic.yaml](patches/kube-apiserver+strategic.yaml) sets a `cpu: 300m` request

```bash
minikube -p kubeadm-lab cp patches/corednsdeployment+strategic.yaml /root/patches/corednsdeployment+strategic.yaml
minikube -p kubeadm-lab cp patches/kube-apiserver+strategic.yaml   /root/patches/kube-apiserver+strategic.yaml

../node.sh '$KUBEADM upgrade apply phase addon coredns v1.37.0 --patches /root/patches'
#   [patches] Applied patch of type "application/strategic-merge-patch+json" to target "corednsdeployment"
$K get deploy coredns -o jsonpath='{.spec.template.spec.containers[0].resources.limits}{"\n"}'   # {"memory":"200Mi"}

../node.sh '$KUBEADM init phase control-plane apiserver --config /root/kubeadm.yaml --patches /root/patches'
#   error: can not mix '--config' with arguments [patches]       <- with --config, the dir goes in InitConfiguration.patches
./write-config.sh /root/patches                                  # adds  patches: {directory: /root/patches}
../node.sh '$KUBEADM init phase control-plane apiserver --config /root/kubeadm.yaml'
#   [patches] Found the following patch files: [corednsdeployment+strategic.yaml kube-apiserver+strategic.yaml]
#   [patches] Applied patch of type "application/strategic-merge-patch+json" to target "kube-apiserver"
sleep 30; $K get pod kube-apiserver-kubeadm-lab -o jsonpath='{.spec.containers[0].resources}{"\n"}'   # {"requests":{"cpu":"300m"}}
```
For a real upgrade it would be `kubeadm upgrade apply v1.x.y --patches /root/patches` (and `kubeadm upgrade node --patches ...` on other nodes). The `service-node-port-range` flag and the SAN need no patch. They are in the `kubeadm-config` ConfigMap, which `kubeadm upgrade` reads.

**Node object.** Keep the change as a patch file ([node-patch.yaml](node-patch.yaml)) and re-apply it after upgrades:
```bash
kubectl --context kubeadm-lab patch no kubeadm-lab --patch-file node-patch.yaml
kubectl --context kubeadm-lab get no -L lab.example.com/rack
#   kubeadm-lab   Ready   control-plane   ...   v1.37.0   r1
```

**kubelet.** A local edit of `config.yaml` is overwritten by the cluster-wide ConfigMap. Flags survive:
```bash
../node.sh 'sed -i "s/^maxPods: 50/maxPods: 70/" /var/lib/kubelet/config.yaml; grep maxPods /var/lib/kubelet/config.yaml
  $KUBEADM upgrade node phase kubelet-config >/dev/null 2>&1          # what kubeadm upgrade does on every node
  grep maxPods /var/lib/kubelet/config.yaml; cat /var/lib/kubelet/kubeadm-flags.env'
#   maxPods: 70
#   maxPods: 50                                                    <- node-local edit lost
#   KUBELET_KUBEADM_ARGS="--node-ip=192.168.175.2 --max-pods=60"   <- flags file untouched
```

---

## Useful commands
```bash
kubectl edit cm -n kube-system kubeadm-config     # data.ClusterConfiguration
kubectl edit cm -n kube-system kubelet-config     # data.kubelet
kubectl edit cm -n kube-system kube-proxy         # data.config.conf
kubeadm init phase certs apiserver --config f        # move the old cert away first
kubeadm init phase control-plane apiserver|controller-manager|scheduler --config f
kubeadm init phase etcd local --config f
kubeadm upgrade node phase kubelet-config && systemctl restart kubelet
kubeadm upgrade apply phase addon coredns|kube-proxy <version> [--patches dir]
```

## Cleanup
```bash
./cleanup.sh       # deletes the demo namespace and the node label
```
The kubeadm-level changes (flag, SAN, maxPods, drop-in, patches) are easiest to undo by recreating the profile: `minikube delete -p kubeadm-lab && ../start-kubeadm-lab.sh`. Backups are in `/root` on the node. Or keep the profile for the next kubeadm lab, or `minikube stop -p kubeadm-lab`. (Restarting the profile with `minikube start` re-runs minikube's own kubeadm config, which may overwrite some of these changes.)
