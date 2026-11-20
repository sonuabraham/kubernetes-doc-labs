#!/usr/bin/env bash
# NOT from the kubeadm pages – the Container Runtimes page's containerd settings, applied to a lab machine (run as root inside it):
#   ./machines.sh x cp1 "$(cat prepare-runtime.sh)"
# kicbase ships a "packaged" containerd config (version = 2) with SystemdCgroup = false and sandbox_image pause:3.6, plus a podman
# bridge CNI config that would hand out 10.88.0.0/16 Pod IPs before any network add-on is installed.
set -e
f=/etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' $f                                        # systemd cgroup driver
sed -i 's#sandbox_image = ".*"#sandbox_image = "registry.k8s.io/pause:3.10.2"#' $f              # = kubeadm config images list
rm -f /etc/cni/net.d/87-podman-bridge.conflist                                                    # leave CNI to the add-on
systemctl enable containerd >/dev/null 2>&1   # kicbase ships it disabled – survive machine restarts
systemctl restart containerd
grep -nE "SystemdCgroup|sandbox_image" $f; ls /etc/cni/net.d/; systemctl is-active containerd
