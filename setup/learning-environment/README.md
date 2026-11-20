# Learning environment – Hands-on Lab

Based on: https://kubernetes.io/docs/setup/learning-environment/

> The page is an overview of where to practise: kubectl, kind, minikube, other desktop tools, online playgrounds, and kubeadm for
> "production-like" clusters. It has no commands. This lab looks at the learning environment **this repo uses** and does one full
> set-up/tear-down cycle with a throwaway minikube profile (NOT from the docs).
>
> **This machine:**
> - kubectl **v1.35.10** (snap). The server is v1.37, so kubectl prints a version-skew warning; `minikube kubectl --` gives a v1.37 client.
> - minikube **v1.39.0**, docker driver, containerd runtime, Kubernetes v1.37.0. The node is the container `minikube` from image
>   `gcr.io/k8s-minikube/kicbase:v0.0.51`.
> - Docker 29.1.3.
> - **kind is not installed.** Downloading it was not permitted in this environment, so the labs that use kind
>   ([tutorials/security](../../tutorials/security/)) use minikube profiles instead. kind runs the same kind of node (a systemd container).
> - **Limit:** the host's `fs.inotify.max_user_instances` is 128. One extra profile works if the default `minikube` is stopped
>   first; 3+ node clusters don't come up.
>
> **Measured:** a fresh single-node cluster was ready in **22 s** (`minikube start`, images cached), and was gone in **8 s** (`minikube delete`).

## Key ideas (read first)

| Option | What it is |
|---|---|
| kind | Kubernetes nodes as Docker containers; built for testing Kubernetes itself; multi-node easy |
| minikube | local cluster (VM or container driver); addons (dashboard, metrics-server, CSI …); profiles = several clusters |
| Desktop tools | Docker Desktop, Podman Desktop, Rancher Desktop, MicroK8s, CRC (OpenShift) – third-party |
| Online playground | Killercoda: nothing to install |
| kubeadm | production-like clusters on real or virtual machines; the next step, see [../production-environment/tools/kubeadm](../production-environment/tools/kubeadm/) |

## Lab – A throwaway learning cluster
```bash
kubectl version --client                       # Client Version: v1.35.10
minikube version                               # minikube version: v1.39.0
which kind                                     # (nothing)
docker ps --filter name=minikube --format '{{.Names}} {{.Image}}'    # minikube gcr.io/k8s-minikube/kicbase:v0.0.51  <- the "node"

minikube stop                                  # (inotify: one cluster at a time on this host)
time minikube start -p learn-lab --memory 2048 --cpus 2 --kubernetes-version v1.37.0     # ~22 s
kubectl --context learn-lab get nodes          # learn-lab   NotReady → Ready   control-plane   v1.37.0
kubectl --context learn-lab create deployment hello --image=registry.k8s.io/e2e-test-images/agnhost:2.53 -- /agnhost netexec --http-port=8080
kubectl --context learn-lab rollout status deploy/hello     # successfully rolled out
time minikube delete -p learn-lab              # ~8 s – everything gone, nothing to clean up
minikube start                                 # back to the default cluster
```

## Cleanup
Nothing left behind (`minikube delete -p learn-lab` removes the profile, its container and its kubeconfig context).
