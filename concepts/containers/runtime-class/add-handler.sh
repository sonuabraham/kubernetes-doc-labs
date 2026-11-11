#!/usr/bin/env bash
# Step 1 of the docs' setup: configure the CRI implementation on the node.
# Adds a containerd runtime handler called "myconfiguration" (the handler the
# docs' RuntimeClass points to). It is runc again, but with different settings
# (cgroupfs instead of the systemd cgroup driver) - "the same container runtime
# but with different settings". Then restarts containerd (running containers
# keep running; they are owned by containerd-shim processes).
minikube ssh -- "sudo grep -q 'runtimes.myconfiguration' /etc/containerd/config.toml || sudo sed -i '/runtimes.runc.options\]/{n;a\\
        [plugins.\"io.containerd.grpc.v1.cri\".containerd.runtimes.myconfiguration]\\
          runtime_type = \"io.containerd.runc.v2\"\\
          [plugins.\"io.containerd.grpc.v1.cri\".containerd.runtimes.myconfiguration.options]\\
            SystemdCgroup = false
}' /etc/containerd/config.toml && sudo systemctl restart containerd && sleep 3 && sudo grep -A3 'runtimes.myconfiguration\]' /etc/containerd/config.toml"
