# Set Kubelet Parameters Via A Configuration File – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/administer-cluster/kubelet-config-file/

> This runs on a throwaway profile **`kcfg-lab`**. Its kubelet already uses `--config=/var/lib/kubelet/config.yaml`; the lab adds `--config-dir=/etc/kubernetes/kubelet.conf.d` and drops files in. Files:
> - [kubelet-config-docs.yaml](kubelet-config-docs.yaml): the docs' example, **verbatim**.
> - [conf.d/](conf.d/): the drop-ins used (not from the docs). [50-address-port.conf](conf.d/50-address-port.conf) has the node IP (`192.168.193.2`) filled in. Use yours.
>
> Results are read back with the page's `kubectl proxy` + `curl .../configz | jq`.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **Config file** | `--config=<file>`: a YAML/JSON `KubeletConfiguration` (`kubelet.config.k8s.io/v1beta1`). It's the recommended way to configure the kubelet; many flags are deprecated in its favour. |
| **Flags win** | A command-line flag overrides the same setting from any file. Defaults also differ: with `--config`, the *config API's* defaults apply. |
| **Drop-in dir** | `--config-dir=<dir>`: files ending in **`.conf`**, each with `apiVersion` + `kind`, applied in **file-name order** (later wins). Validation runs on the merged result. |
| **Merge order** | Feature-gate flags → `--config` file → drop-ins (sorted) → other command-line flags. |
| **evictionHard** | A partial map in a config file is **not** filled with defaults (missing thresholds are absent, i.e. 0), unless `mergeDefaultEvictionSettings: true`. |
| **Inspect** | `/api/v1/nodes/<node>/proxy/configz` shows the configuration the kubelet is actually running with. |

---

## Step 0 – enable a drop-in directory
```bash
cd tasks/administer-cluster/kubelet-config-file
minikube start -p kcfg-lab --memory 2200 --cpus 2 --kubernetes-version v1.37.0 && kubectl config use-context minikube
N(){ P=kcfg-lab ../kubeadm/node.sh "$1"; }
N 'F=/etc/systemd/system/kubelet.service.d/10-kubeadm.conf; mkdir -p /etc/kubernetes/kubelet.conf.d
   sed -i "s|^ExecStart=/.*|& --config-dir=/etc/kubernetes/kubelet.conf.d|" $F; systemctl daemon-reload; systemctl restart kubelet'
configz(){ kubectl --context kcfg-lab proxy --port=8001 >/dev/null & sleep 2
           curl -s http://127.0.0.1:8001/api/v1/nodes/kcfg-lab/proxy/configz | jq -c ".kubeletconfig | $1"; kill $!; }
```

## Lab 1 – The docs' example file
```bash
minikube -p kcfg-lab cp kubelet-config-docs.yaml /etc/kubernetes/kubelet.conf.d/50-docs-example.conf
N 'systemctl restart kubelet; sleep 8; systemctl is-active kubelet; journalctl -u kubelet --since "-10s" | grep -i listen'
#   activating
#   "Starting to listen" address="192.168.0.8" port=20250
#   "Failed to listen and serve" err="listen tcp 192.168.0.8:20250: bind: cannot assign requested address"
```
`address` must be an IP the node actually has. Use the node's own IP ([conf.d/50-address-port.conf](conf.d/50-address-port.conf)):
```bash
N 'rm /etc/kubernetes/kubelet.conf.d/50-docs-example.conf'
minikube -p kcfg-lab cp conf.d/50-address-port.conf /etc/kubernetes/kubelet.conf.d/50-address-port.conf
N 'systemctl reset-failed kubelet; systemctl restart kubelet'
kubectl --context kcfg-lab get node kcfg-lab -o jsonpath='{.status.daemonEndpoints}{"\n"}'
#   {"kubeletEndpoint":{"Port":20250}}          <- the API server now reaches this kubelet on 20250
configz '{address, port, serializeImagePulls}'
#   {"address":"192.168.193.2","port":20250,"serializeImagePulls":false}
```

## Lab 2 – evictionHard: the "others become zero" note
Partial map in the **main** config file (minikube's own `evictionHard` removed first):
```bash
N 'cp /var/lib/kubelet/config.yaml /root/kubelet-config.orig.yaml; sed -i "/^evictionHard:/,/^  nodefs.inodesFree/d" /var/lib/kubelet/config.yaml
   printf "evictionHard:\n  memory.available: \"200Mi\"\n" >> /var/lib/kubelet/config.yaml; systemctl restart kubelet'
configz '{evictionHard, mergeDefaultEvictionSettings}'
#   {"evictionHard":{"memory.available":"200Mi"},"mergeDefaultEvictionSettings":false}      <- nodefs/imagefs thresholds gone
N 'printf "mergeDefaultEvictionSettings: true\n" >> /var/lib/kubelet/config.yaml; systemctl restart kubelet'
configz '{evictionHard, mergeDefaultEvictionSettings}'
#   {"evictionHard":{"imagefs.available":"15%","imagefs.inodesFree":"5%","memory.available":"200Mi","nodefs.available":"10%","nodefs.inodesFree":"5%"},"mergeDefaultEvictionSettings":true}
```
When the main file sets no `evictionHard` and only a **drop-in** sets `memory.available`, the result is already complete (`imagefs.available 15%, ..., memory.available 200Mi`). The main file is defaulted first, and the drop-in's map key is merged on top. With minikube's original main file (three `0%` entries) and that drop-in, you get those three + `memory.available` and no `imagefs.inodesFree`.

## Lab 3 – Drop-in order and flags
```bash
minikube -p kcfg-lab cp conf.d/10-maxpods.conf /etc/kubernetes/kubelet.conf.d/10-maxpods.conf     # maxPods: 50
minikube -p kcfg-lab cp conf.d/20-maxpods.conf /etc/kubernetes/kubelet.conf.d/20-maxpods.conf     # maxPods: 70
N 'systemctl restart kubelet'
kubectl --context kcfg-lab get node kcfg-lab -o jsonpath='{.status.capacity.pods}{"\n"}'          # 70  <- 20-* sorts after 10-*
N 'sed -i "s|--config-dir=/etc/kubernetes/kubelet.conf.d|& --max-pods=90|" /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
   systemctl daemon-reload; systemctl restart kubelet'
kubectl --context kcfg-lab get node kcfg-lab -o jsonpath='{.status.capacity.pods}{"\n"}'          # 90  <- command-line flag wins
```
A drop-in without `apiVersion`/`kind` ([conf.d/30-no-typemeta.conf](conf.d/30-no-typemeta.conf)) stops the kubelet from starting (`"command failed"` in the journal). Every drop-in needs the type metadata.

## Lab 4 – Viewing the whole configuration (the docs' way)
```bash
kubectl --context kcfg-lab proxy &
#   Starting to serve on 127.0.0.1:8001
curl -X GET http://127.0.0.1:8001/api/v1/nodes/kcfg-lab/proxy/configz | jq .
#   { "kubeletconfig": { "enableServer": true, "staticPodPath": "/etc/kubernetes/manifests", ..., "port": 20250, ... "maxPods": 90, ... } }
kill %1
```

---

## Useful commands
```bash
kubectl get --raw /api/v1/nodes/<node>/proxy/configz | jq '.kubeletconfig.<field>'
ps -o args= -C kubelet | tr ' ' '\n' | grep -E '^--config'
ls /etc/kubernetes/kubelet.conf.d
```

## Cleanup
```bash
minikube delete -p kcfg-lab
```
