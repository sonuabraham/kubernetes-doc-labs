#!/usr/bin/env bash
# Undo add-handler.sh
minikube ssh -- "sudo sed -i '/runtimes.myconfiguration\]/,+3d' /etc/containerd/config.toml && sudo systemctl restart containerd && echo removed"
