# Bootstrapping clusters with kubeadm – Section Page

Based on: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/

> The docs section page has no body. These labs build **real kubeadm clusters** from scratch on throwaway "machines":
> privileged containers from minikube's kicbase image (Debian 12 + systemd + containerd), like kind nodes, made by
> [machines.sh](machines.sh). Packages come from pkgs.k8s.io (v1.37.2). Shared pieces:
> - [machines.sh](machines.sh): `up NAME…`, `x NAME 'cmd'`, `sh`, `ip`, `down`; optional dual-stack network (`NET=… V6SUBNET=…`)
> - [prepare-runtime.sh](prepare-runtime.sh): containerd settings from the Container Runtimes page (SystemdCgroup, pause image)
> - [kindnet.yaml](kindnet.yaml): the Pod network add-on (as minikube deploys it)
>
> Host limits: stop the default `minikube` first. At most 3 kubelets run at once (inotify instances: 128). Never `swapoff` inside a
> machine; `/proc/swaps` is the host's.
>
> | Lab | Shows |
> |---|---|
> | [install-kubeadm](install-kubeadm/) | the Debian package install, preflight in a container |
> | [troubleshooting-kubeadm](troubleshooting-kubeadm/) | the catalogue, reproduced (kubelet cert recovery, TLS errors, …) |
> | [create-cluster-kubeadm](create-cluster-kubeadm/) | init, CNI, join, NodeRestriction, admin.conf, tear down |
> | [control-plane-flags](control-plane-flags/) | extraArgs, extraVolumes, patches, kubelet/kube-proxy/CoreDNS customization |
> | [ha-topology](ha-topology/) | stacked vs external etcd |
> | [high-availability](high-availability/) | 3 control planes behind HAProxy, failover |
> | [setup-ha-etcd-with-kubeadm](setup-ha-etcd-with-kubeadm/) | 3-member etcd + external-etcd control plane |
> | [kubelet-integration](kubelet-integration/) | the kubelet's files, TLS bootstrap, override order |
> | [dual-stack-support](dual-stack-support/) | a real dual-stack cluster |
>
> Remove everything: `./machines.sh down` (machines, volumes, networks), then `minikube start`.
