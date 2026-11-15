#!/usr/bin/env bash
# NOT from the docs as a script: the page's "If filing a bug, please include ..." list, collected in one go.
#   Kubernetes version | cloud provider, OS distro, network configuration, container runtime version
# Review the output before you paste it anywhere public (it contains IPs and host names).
echo "## kubectl version";                 kubectl version 2>&1
echo; echo "## nodes";                     kubectl get nodes -o wide
echo; echo "## per-node runtime / OS / kernel"
kubectl get nodes -o custom-columns=NODE:.metadata.name,OS:.status.nodeInfo.osImage,KERNEL:.status.nodeInfo.kernelVersion,RUNTIME:.status.nodeInfo.containerRuntimeVersion,KUBELET:.status.nodeInfo.kubeletVersion,ARCH:.status.nodeInfo.architecture
echo; echo "## provider (spec.providerID / well-known labels)"
kubectl get nodes -o custom-columns=NODE:.metadata.name,PROVIDER_ID:.spec.providerID,INSTANCE:.metadata.labels.node\\.kubernetes\\.io/instance-type,ZONE:.metadata.labels.topology\\.kubernetes\\.io/zone
echo; echo "## network: CNI pods, Service CIDR, Pod CIDRs"
kubectl get pods -n kube-system -o wide | grep -Ei 'cni|calico|cilium|flannel|kindnet|weave|antrea|kube-proxy' || true
kubectl get servicecidrs 2>/dev/null
kubectl get nodes -o custom-columns=NODE:.metadata.name,POD_CIDRS:.spec.podCIDRs
echo; echo "## control plane health";      kubectl get --raw='/readyz?verbose' | tail -3
