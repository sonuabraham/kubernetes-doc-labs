# Enable Or Disable Feature Gates – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/administer-cluster/configure-feature-gates/

> This runs on a throwaway profile **`fg-lab`**. minikube builds it with kubeadm, so it has the static Pod manifests, `/var/lib/kubelet/config.yaml` and the `kube-proxy` ConfigMap the page edits. Node commands use [../kubeadm/node.sh](../kubeadm/node.sh) with `P=fg-lab`.
>
> The gate used is the real alpha **`ContainerStopSignals`**. It needs **two** components: the API server keeps the new `lifecycle.stopSignal` field, and the kubelet sends that signal. That makes the page's "enable it on all relevant components" caution visible. Files:
> - [01-stop-signal-pod.yaml](01-stop-signal-pod.yaml) + [stop-test.sh](stop-test.sh) show which signal a container really gets.
> - [kubeadm-config.yaml](kubeadm-config.yaml) is the docs' init config, **verbatim**.
> - [kubeadm-config-v1beta4.yaml](kubeadm-config-v1beta4.yaml) is a version of it that validates.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **Stages** | **Alpha**: off by default, may be buggy. **Beta**: usually on. **GA**: always on; may be disable-able for one release after GA (non-conformant if you do). |
| **Per component** | Every component knows every gate name, but only the components that implement a feature act on its gate. Multi-component features need the gate **everywhere**. |
| **Where to set it** | Control plane: `--feature-gates=A=true,B=false` in the static Pod manifests (kubeadm: `extraArgs`). kubelet: `featureGates:` in its config file (the flag is deprecated). kube-proxy: `featureGates:` in its ConfigMap, then restart the DaemonSet. |
| **Verify** | Manifest / Pod spec, kubelet `/configz`, `kubernetes_feature_enabled{name=...}` metrics (1/0) on each component, and the API server's `/flagz`. |

---

## Step 0
```bash
cd tasks/administer-cluster/configure-feature-gates
minikube start -p fg-lab --memory 2200 --cpus 2 --kubernetes-version v1.37.0 && kubectl config use-context minikube
N(){ P=fg-lab ../kubeadm/node.sh "$1"; }
```

## Lab 1 – Maturity at a glance (metrics)
```bash
kubectl --context fg-lab get --raw /metrics | grep '^kubernetes_feature_enabled' | sed -E 's/.*stage="([A-Z]*)"\} ([01])/\1 \2/' | sort | uniq -c
#        71  1          <- GA (stage=""), all on
#        56 ALPHA 0     <- alpha: off by default
#       100 BETA 1       9 BETA 0     <- most beta on, a few beta-off
#        10 DEPRECATED 0     7 DEPRECATED 1
kubectl --context fg-lab get --raw /metrics | grep kubernetes_feature_enabled | grep ContainerStopSignals
#   kubernetes_feature_enabled{name="ContainerStopSignals",stage="ALPHA"} 0
```

## Lab 2 – The docs' kubeadm init config
```bash
for f in kubeadm-config.yaml kubeadm-config-v1beta4.yaml; do minikube -p fg-lab cp $f /tmp/$f; echo "== $f"; N "\$KUBEADM config validate --config /tmp/$f"; done
#   == kubeadm-config.yaml
#   error: error unmarshaling configuration ... json: cannot unmarshal object into Go struct field
#          APIServer.apiServer.ControlPlaneComponent.extraArgs of type []v1beta4.Arg
#   == kubeadm-config-v1beta4.yaml
#   ok
```
The page's example uses the **v1beta3 map form** of `extraArgs` under `apiVersion: kubeadm.k8s.io/v1beta4`. Since v1beta4, `extraArgs` is a list of `{name, value}`. For a new cluster you'd run `kubeadm init --config kubeadm-config-v1beta4.yaml`.

## Lab 3 – Gate off everywhere
```bash
./stop-test.sh
#   pod/stop-signal-demo created
#   stored lifecycle:                       <- the API server silently DROPPED lifecycle.stopSignal
#   container received: 11:55:55 got SIGTERM
```

## Lab 4 – Enable on the API server only (static Pod manifest)
```bash
N 'cp /etc/kubernetes/manifests/kube-apiserver.yaml /root/
   sed -i "s|^    - kube-apiserver$|&\n    - --feature-gates=ContainerStopSignals=true|" /etc/kubernetes/manifests/kube-apiserver.yaml
   grep -n -A1 "^    - kube-apiserver" /etc/kubernetes/manifests/kube-apiserver.yaml'
#   14:    - kube-apiserver
#   15-    - --feature-gates=ContainerStopSignals=true          <- saving the file restarts the static Pod
until kubectl --context fg-lab get --raw /readyz >/dev/null 2>&1; do sleep 3; done
kubectl --context fg-lab -n kube-system get pod kube-apiserver-fg-lab -o yaml | grep feature-gates
#   - --feature-gates=ContainerStopSignals=true
kubectl --context fg-lab get --raw /metrics | grep kubernetes_feature_enabled | grep ContainerStopSignals
#   kubernetes_feature_enabled{name="ContainerStopSignals",stage="ALPHA"} 1
kubectl --context fg-lab get --raw /flagz | grep feature-gates            # ComponentFlagz is beta/on in 1.37
#   feature-gates :ContainerStopSignals=true
./stop-test.sh
#   stored lifecycle: {"stopSignal":"SIGUSR1"}       <- kept now...
#   container received: 11:57:19 got SIGTERM           <- ...but the kubelet doesn't know the feature yet
```

## Lab 5 – Enable on the kubelet (config file)
```bash
N 'printf "featureGates:\n  ContainerStopSignals: true\n" >> /var/lib/kubelet/config.yaml
   cat /var/lib/kubelet/config.yaml | grep -A 10 featureGates
   systemctl restart kubelet'
kubectl --context fg-lab proxy --port=8001 &
curl -sSL "http://localhost:8001/api/v1/nodes/fg-lab/proxy/configz" | grep featureGates -A 5
#   ... "featureGates":{"ContainerStopSignals":true} ...
curl -sSL "http://localhost:8001/api/v1/nodes/fg-lab/proxy/metrics" | grep kubernetes_feature_enabled | grep ContainerStopSignals     # ... 1
kill %1
./stop-test.sh
#   stored lifecycle: {"stopSignal":"SIGUSR1"}
#   container received: 11:57:43 got SIGUSR1          <- both components on: feature works
```
(On a real kubeadm cluster, `kubeadm upgrade` rewrites `config.yaml` from the `kubelet-config` ConfigMap. Put the gate there too, see [../kubeadm/kubeadm-reconfigure](../kubeadm/kubeadm-reconfigure/).)

## Lab 6 – Enable on kube-proxy (ConfigMap + restart)
The alpha gate `KubeProxyNFTablesLocalhostNodePorts`. Instead of `kubectl -n kube-system edit configmap kube-proxy`, use the non-interactive editor from the reconfigure lab:
```bash
m(){ N 'curl -s 127.0.0.1:10249/metrics | grep kubernetes_feature_enabled | grep KubeProxyNFTablesLocalhostNodePorts'; }
m                                                                       # ... 0
CTX=fg-lab ../kubeadm/kubeadm-reconfigure/edit-cm.py kube-proxy config.conf 'd["featureGates"]={"KubeProxyNFTablesLocalhostNodePorts": True}'
m                                                                       # ... 0  <- running Pods read the config at start
kubectl --context fg-lab -n kube-system rollout restart daemonset kube-proxy
kubectl --context fg-lab -n kube-system rollout status daemonset kube-proxy
m                                                                       # ... 1
```

---

## Useful commands
```bash
kubectl get --raw /metrics | grep kubernetes_feature_enabled | grep <Gate>
kubectl get --raw /flagz
kubectl get --raw /api/v1/nodes/<node>/proxy/configz
kubectl get --raw /api/v1/nodes/<node>/proxy/metrics | grep kubernetes_feature_enabled
```

## Cleanup
```bash
minikube delete -p fg-lab
```
