#!/usr/bin/env bash
# NOT from the docs – a throwaway "Linux machine with systemd" for this tutorial, because the page needs root on a systemd host.
# It is a privileged Docker container from minikube's own kicbase image (Debian 12 + systemd + CRI-O 1.35 + CNI plugins), started
# the way minikube starts its node. The kubelet binary (v1.37.0) is copied out of the minikube node, so nothing is downloaded.
#   ./standalone-machine.sh up      create + start container "kubelet-standalone", put /root/kubelet in it
#   ./standalone-machine.sh sh      shell inside (you are root there: drop the "sudo" from the docs' commands, or keep it – sudo exists)
#   ./standalone-machine.sh down    delete the container (= the docs' whole "Clean up" section)
# Needs the default minikube running for "up" (kubelet is copied from it). Stop it afterwards if inotify gets tight.
set -euo pipefail
N=kubelet-standalone
IMG=gcr.io/k8s-minikube/kicbase:v0.0.51
case ${1:?up|sh|down} in
  up)
    docker run -d --name $N --hostname $N --privileged \
      --security-opt seccomp=unconfined --security-opt apparmor=unconfined \
      --tmpfs /tmp --tmpfs /run -v /lib/modules:/lib/modules:ro -v $N-var:/var $IMG >/dev/null   # /var on a volume: CRI-O overlay cannot sit on overlayfs
    tmp=$(mktemp -d)
    docker cp minikube:/var/lib/minikube/binaries/v1.37.0/kubelet "$tmp/kubelet"
    docker cp "$tmp/kubelet" $N:/root/kubelet; rm -rf "$tmp"
    # docker inside kicbase is enabled by default; it isn't part of this tutorial
    docker exec $N sh -c 'until systemctl is-system-running 2>/dev/null | grep -qE "running|degraded"; do sleep 1; done; systemctl disable --now docker.service docker.socket >/dev/null 2>&1; systemctl is-system-running || true'
    echo "machine $N ready; kubelet at /root/kubelet" ;;
  sh)   docker exec -it -w /root $N bash ;;
  down) docker rm -f $N; docker volume rm $N-var ;;
esac
