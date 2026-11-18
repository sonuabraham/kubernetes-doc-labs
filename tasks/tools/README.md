# Install Tools – Section Page

Based on: https://kubernetes.io/docs/tasks/tools/

> The page introduces four tools: **kubectl** (with install pages per OS, each a lab here), **kind**, **minikube** and **kubeadm**.
> The `tools/included/` pages are snippets embedded in the kubectl install pages, not pages of their own.
> This lab only checks what this study machine has. Nothing is installed or changed.

| Page / tool | Lab or status here |
|---|---|
| Install and Set Up kubectl on Linux | [install-kubectl-linux](install-kubectl-linux/) |
| Install and Set Up kubectl on macOS | [install-kubectl-macos](install-kubectl-macos/) |
| Install and Set Up kubectl on Windows | [install-kubectl-windows](install-kubectl-windows/) |
| kind | not installed; every lab uses minikube instead |
| minikube | the cluster for all labs (docker driver) |
| kubeadm | runs **inside** the minikube node (minikube bootstraps with it); used directly in several labs, e.g. [administer-cluster/kubeadm](../administer-cluster/kubeadm/), [tls/certificate-rotation](../tls/certificate-rotation/) |

## Check your toolbox
```bash
kubectl version --client                       # Client Version: v1.35.10   Kustomize Version: v5.7.1
kubectl version | grep Server                  # Server Version: v1.37.0    <- client 2 minors behind: outside the ±1 skew policy
minikube kubectl -- version --client           # Client Version: v1.37.0    <- matching kubectl that minikube downloads
minikube version                               # minikube version: v1.39.0
command -v kind || echo "kind: not installed"  # kind: not installed
minikube ssh -- /var/lib/minikube/binaries/v1.37.0/kubeadm version -o short       # v1.37.0
docker version --format 'docker {{.Server.Version}}'                               # docker 29.1.3 (minikube's driver)
```
The client/server skew (1.35 vs 1.37) is why `minikube start` prints "kubectl is version 1.35.10, which may have incompatibilities with
Kubernetes 1.37.0"; see [install-kubectl-linux](install-kubectl-linux/) for upgrading.
