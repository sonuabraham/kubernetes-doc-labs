#!/usr/bin/env bash
# NOT from the docs – start a throwaway minikube profile with a given container runtime and show what the page talks about:
# CRI socket, cgroup driver (runtime + kubelet), pause image, IP forwarding, CRI version.
#   ./inspect-runtime.sh containerd|cri-o|docker      (profile rt-<runtime>; deleted again at the end)
# Stop the default minikube first (inotify limit on this host).
set -uo pipefail
RT=${1:?containerd|cri-o|docker}; P=rt-$RT
minikube start -p $P --memory 2048 --cpus 2 --kubernetes-version v1.37.0 --container-runtime=$RT >/dev/null 2>&1 || { echo "start failed"; exit 1; }
n() { minikube -p $P ssh -- "$1" 2>/dev/null | tr -d '\r'; }
echo "== $RT"
kubectl --context $P get node $P -o jsonpath='containerRuntimeVersion: {.status.nodeInfo.containerRuntimeVersion}{"\n"}'
kubectl --context $P get --raw /api/v1/nodes/$P/proxy/configz | python3 -c 'import json,sys; k=json.load(sys.stdin)["kubeletconfig"]; print("kubelet cgroupDriver:", k.get("cgroupDriver"), "| endpoint:", k.get("containerRuntimeEndpoint"))'
n 'echo "ip_forward: $(cat /proc/sys/net/ipv4/ip_forward)"'
n 'sudo crictl version | grep -E "RuntimeName|RuntimeVersion|RuntimeApiVersion"'
case $RT in
  containerd) n 'sudo grep -nE "^version|SystemdCgroup|sandbox_image" /etc/containerd/config.toml' ;;
  cri-o)      n 'sudo grep -rhnE "cgroup_manager|conmon_cgroup|pause_image" /etc/crio/ | grep -v "^ *#"; sudo crio config 2>/dev/null | grep -E "^\s*(cgroup_manager|conmon_cgroup|pause_image) "' ;;
  docker)     n 'systemctl is-active docker cri-docker.socket; systemctl cat cri-docker.service | grep ExecStart=/; docker info --format "docker cgroup driver: {{.CgroupDriver}}"; ls -l /run/cri-dockerd.sock /var/run/cri-dockerd.sock 2>&1 | head -2' ;;
esac
timeout 60 bash -c "until kubectl --context $P get sa default >/dev/null 2>&1; do sleep 1; done"   # fresh cluster: wait for the default ServiceAccount
kubectl --context $P run t --image=registry.k8s.io/pause:3.10 --restart=Never >/dev/null && kubectl --context $P wait --for=condition=Ready pod/t --timeout=120s >/dev/null && echo "test Pod: Running"
minikube delete -p $P >/dev/null 2>&1; echo "profile $P deleted"
