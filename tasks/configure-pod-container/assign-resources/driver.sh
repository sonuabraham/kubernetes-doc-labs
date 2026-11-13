#!/usr/bin/env bash
# ./driver.sh start <driver-name> [gpus]   copy lab-dra-driver to the dra-lab node and run it as systemd unit
#                                          lab-dra-<driver-name> (kubelet plugin + ResourceSlice publisher)
# ./driver.sh stop  <driver-name>
# ./driver.sh logs  <driver-name>
# The driver uses the node's /etc/kubernetes/admin.conf to publish ResourceSlices (a real driver runs as a
# DaemonSet with its own ServiceAccount).                                             (P=<profile>, default dra-lab)
P=${P:-dra-lab}; D=$(cd "$(dirname "$0")" && pwd); N(){ P=$P "$D/../../administer-cluster/kubeadm/node.sh" "$1"; }
DRV=${2:?driver name}; U=lab-dra-${DRV//./-}
case $1 in
start)
  N "systemctl stop $U 2>/dev/null; systemctl reset-failed $U 2>/dev/null; true"
  minikube -p "$P" cp "$D/lab-dra-driver/lab-dra-driver" /usr/local/bin/lab-dra-driver >/dev/null 2>&1 || true
  N "chmod 755 /usr/local/bin/lab-dra-driver; mkdir -p /var/lib/kubelet/plugins/$DRV
     systemd-run --unit=$U /usr/local/bin/lab-dra-driver -driver $DRV -gpus ${3:-4} -kubeconfig /etc/kubernetes/admin.conf -node \$(hostname)
     sleep 3; systemctl is-active $U; ls /var/lib/kubelet/plugins_registry/ | grep -i ${DRV%%.*}" ;;
stop) N "systemctl stop $U; echo stopped $U" ;;
logs) N "journalctl -u $U --no-pager | tail -${3:-20}" ;;
*) echo "usage: $0 start|stop|logs <driver-name>"; exit 1 ;;
esac
