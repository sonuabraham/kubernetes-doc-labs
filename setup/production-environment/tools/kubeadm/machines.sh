#!/usr/bin/env bash
# NOT from the docs – throwaway "machines" for the kubeadm labs (what kind does, by hand).
# Each machine is a privileged container from minikube's kicbase image (Debian 12, systemd, containerd 2.x, CNI plugins), on its own
# Docker network, with /var on a volume (container runtimes can't use overlayfs on overlayfs) and the host's /lib/modules and /boot
# read-only (kubeadm's SystemVerification reads the kernel config from /boot/config-$(uname -r)). Nothing Kubernetes is installed:
# the labs follow install-kubeadm (pkgs.k8s.io apt repo) inside them.
#   ./machines.sh up NAME...     create + start machines (e.g. ./machines.sh up cp1 w1)
#   ./machines.sh sh NAME        root shell
#   ./machines.sh x NAME 'cmd'   run a command as root (bash -lc)
#   ./machines.sh ip NAME        the machine's IP on the lab network
#   ./machines.sh down           delete ALL lab machines, their volumes and the network
# Stop the default minikube while machines run (host inotify limit: 128 instances).
set -euo pipefail
NET=kubeadm-lab-net
IMG=gcr.io/k8s-minikube/kicbase:v0.0.51
PFX=kadm-
cmd=${1:?up|sh|x|ip|down}; shift || true
case $cmd in
  up)
    docker network inspect $NET >/dev/null 2>&1 || docker network create --subnet 172.30.0.0/24 $NET >/dev/null
    for n in "$@"; do
      docker run -d --name $PFX$n --hostname $n --network $NET --privileged \
        --security-opt seccomp=unconfined --security-opt apparmor=unconfined \
        --tmpfs /tmp --tmpfs /run -v /lib/modules:/lib/modules:ro -v /boot:/boot:ro -v $PFX$n-var:/var \
        --label kubeadm-lab=1 $IMG >/dev/null
    done
    for n in "$@"; do
      docker exec $PFX$n bash -c 'until systemctl is-system-running 2>/dev/null | grep -qE "running|degraded"; do sleep 1; done
        systemctl disable --now docker.service docker.socket >/dev/null 2>&1; true   # kicbase extras, not part of these labs'
      # NOTE: never "swapoff -a" in these machines – /proc/swaps is the HOST's; the labs tolerate swap (failSwapOn: false) instead.
      echo "machine $n: $(docker inspect -f '{{(index .NetworkSettings.Networks "'$NET'").IPAddress}}' $PFX$n)"
    done ;;
  sh) docker exec -it -w /root $PFX${1:?name} bash ;;
  x)  docker exec -w /root $PFX${1:?name} bash -lc "${2:?command}" ;;
  ip) docker inspect -f '{{(index .NetworkSettings.Networks "'$NET'").IPAddress}}' $PFX${1:?name} ;;
  down)
    ids=$(docker ps -aq --filter label=kubeadm-lab=1); [ -n "$ids" ] && docker rm -f $ids >/dev/null
    vols=$(docker volume ls -q | grep "^$PFX" || true); [ -n "$vols" ] && docker volume rm $vols >/dev/null
    docker network rm $NET >/dev/null 2>&1 || true
    echo "all kubeadm lab machines removed" ;;
esac
