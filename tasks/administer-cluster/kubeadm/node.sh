#!/usr/bin/env bash
# ./node.sh '<shell command>'  - run a command as root on the kubeadm-lab node (P=<profile> to change).
# Inside the command, $KUBEADM is the newest kubeadm binary minikube installed on the node and
# $PKI is minikube's certificate dir (/var/lib/minikube/certs - NOT kubeadm's default /etc/kubernetes/pki).
P=${P:-kubeadm-lab}
minikube ssh -p "$P" -- "sudo bash -c 'KUBEADM=\$(ls -d /var/lib/minikube/binaries/*/kubeadm | sort -V | tail -1); PKI=/var/lib/minikube/certs; export KUBECONFIG=/etc/kubernetes/admin.conf; $1'"
