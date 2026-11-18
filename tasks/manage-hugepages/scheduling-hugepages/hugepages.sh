#!/usr/bin/env bash
# NOT from the docs: pre-allocate 2 MiB huge pages for the lab and make the kubelet report them.
# minikube's node is a privileged container on THIS machine's kernel: vm.nr_hugepages is the HOST setting and reserves host RAM.
# Only 2 MiB pages are possible here: 1 GiB pages need /sys/kernel/mm/hugepages/… (read-only in the node) or the kernel command line.
#   ./hugepages.sh alloc [N]   default 128 x 2Mi = 256 MiB
#   ./hugepages.sh free        back to 0 (do this when done!)
#   ./hugepages.sh show
set -euo pipefail
show() {
  minikube ssh -- "grep -E 'HugePages_(Total|Free)|Hugepagesize' /proc/meminfo | tr -s ' ' | paste -sd ' '"
  kubectl get node minikube -o jsonpath='{.status.allocatable}' | jq -c 'with_entries(select(.key|test("huge")))'
}
case "${1:-}" in
alloc) minikube ssh -- "sudo sysctl -w vm.nr_hugepages=${2:-128}"
       minikube ssh -- sudo systemctl restart kubelet     # docs note: pages allocated after boot need a kubelet restart
       until [ "$(kubectl get node minikube -o jsonpath='{.status.allocatable.hugepages-2Mi}' 2>/dev/null)" = "$(( ${2:-128} * 2 ))Mi" ]; do :; done
       show ;;
free)  minikube ssh -- "sudo sysctl -w vm.nr_hugepages=0"; minikube ssh -- sudo systemctl restart kubelet
       until [ "$(kubectl get node minikube -o jsonpath='{.status.allocatable.hugepages-2Mi}' 2>/dev/null)" = "0" ]; do :; done; show ;;
show)  show ;;
*) sed -n '2,8p' "$0"; exit 1 ;;
esac
