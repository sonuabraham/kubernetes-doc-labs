#!/usr/bin/env bash
# Talk CRI directly - exactly the gRPC calls the kubelet makes - via crictl:
#   RunPodSandbox -> CreateContainer -> StartContainer
# The result is a container the KUBELET DOES NOT KNOW ABOUT (no Pod object).
# Usage: ./crictl-direct.sh start | stop
case "$1" in
  start)
    minikube cp sandbox.json minikube:/tmp/sandbox.json >/dev/null
    minikube cp container.json minikube:/tmp/container.json >/dev/null
    minikube ssh -- 'sudo mkdir -p /tmp/crictl-demo; sudo crictl pull docker.io/library/busybox:1.36 >/dev/null;
      POD=$(sudo crictl runp /tmp/sandbox.json); echo "sandbox: $POD";
      CTR=$(sudo crictl create $POD /tmp/container.json /tmp/sandbox.json); echo "container: $CTR";
      sudo crictl start $CTR; sudo crictl ps --name sleeper' ;;
  stop)
    minikube ssh -- 'P=$(sudo crictl pods --name made-by-crictl -q); [ -n "$P" ] && sudo crictl stopp $P >/dev/null && sudo crictl rmp $P && echo removed' ;;
  *) echo "usage: $0 start|stop" ;;
esac
