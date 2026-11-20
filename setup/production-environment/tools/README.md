# Installing Kubernetes with deployment tools – Section Page

Based on: https://kubernetes.io/docs/setup/production-environment/tools/

> The section page lists deployment tools: **kubeadm** (the official bootstrapper), **Cluster API** (declarative cluster lifecycle via
> Kubernetes APIs), **kOps** (automated provisioning, mainly cloud) and **Kubespray** (Ansible playbooks). Only kubeadm has pages in the
> docs, and its labs are in [kubeadm/](kubeadm/). minikube, used for most labs in this repo, runs kubeadm itself
> (`minikube ssh -- sudo cat /var/tmp/minikube/kubeadm.yaml`).
