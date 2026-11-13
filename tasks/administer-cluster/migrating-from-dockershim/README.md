# Migrating from dockershim – lab group

Based on: https://kubernetes.io/docs/tasks/administer-cluster/migrating-from-dockershim/

All labs here use the throwaway profile **`rt-lab`** (Docker Engine + cri-dockerd, [start-rt-lab.sh](start-rt-lab.sh)) next to the default containerd cluster. [node.sh](node.sh) runs commands on a node. Suggested order:

1. [find-out-runtime-you-use](find-out-runtime-you-use/)
2. [check-if-dockershim-removal-affects-you](check-if-dockershim-removal-affects-you/)
3. [migrating-telemetry-and-security-agents](migrating-telemetry-and-security-agents/)
4. [troubleshooting-cni-plugin-related-errors](troubleshooting-cni-plugin-related-errors/)
5. [change-runtime-containerd](change-runtime-containerd/) – **last**: it removes Docker from rt-lab
