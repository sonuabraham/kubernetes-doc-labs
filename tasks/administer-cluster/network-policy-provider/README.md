# Install a Network Policy Provider – lab group

Based on: https://kubernetes.io/docs/tasks/administer-cluster/network-policy-provider/

NetworkPolicy objects do nothing unless the **network plugin enforces them**. Each lab here creates a throwaway minikube profile with one provider and runs the same check, [np-test.sh](np-test.sh):
1. no policy: both clients reach nginx
2. default-deny ingress: neither does
3. allow from `access=true`: only the labelled client does

| Lab | Install route | Tested version |
|---|---|---|
| [calico-network-policy](calico-network-policy/) | `minikube start --cni=calico` | Calico v3.32.2 |
| [cilium-network-policy](cilium-network-policy/) | docs route: `--network-plugin=cni` + `cilium install` | Cilium 1.20.3 (cilium-cli v0.20.3) |
| [antrea-network-policy](antrea-network-policy/) | `kubectl apply` the release `antrea.yml` | Antrea v2.7.0 |
| [kube-router-network-policy](kube-router-network-policy/) | `kubectl apply` `daemonset/kubeadm-kuberouter.yaml` | kube-router (master manifest) |

Run them one at a time. Each profile needs about 2 GB and inotify instances (see the kubeadm labs). The default minikube cluster uses kindnet, which also enforces NetworkPolicy here (see `concepts/services-networking/network-policies`).
