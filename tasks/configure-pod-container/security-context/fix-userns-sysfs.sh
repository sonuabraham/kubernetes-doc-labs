#!/usr/bin/env bash
# NOT from the docs. Make user-namespace Pods (hostUsers: false) work on a minikube docker-driver node.
#
# Symptom: the sandbox never starts -
#   runc create failed: ... error mounting "sysfs" to rootfs at "/sys": ... operation not permitted
# Cause: minikube bind-mounts files over /sys/devices/virtual/dmi/id/product_{name,uuid} inside the node
# container (to fake a per-node machine ID). A user namespace may only mount a fresh sysfs if the existing
# one is fully visible (the kernel's "mount_too_revealing" check), and those overmounts hide parts of it.
# Fix: unmount them inside the node. Lasts until the node restarts (minikube re-creates them on start).
# Usage: [P=<profile>] ./fix-userns-sysfs.sh        (default profile: minikube)
P=${P:-minikube}
minikube -p "$P" ssh -- 'for f in product_uuid product_uuid product_name; do
    sudo umount /sys/devices/virtual/dmi/id/$f 2>/dev/null; done
  echo "dmi overmounts left: $(grep -c /sys/devices/virtual/dmi /proc/self/mountinfo)"'
