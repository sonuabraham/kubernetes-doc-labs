# Using Minikube to Create a Cluster – Hands-on Lab

Based on: https://kubernetes.io/docs/tutorials/kubernetes-basics/create-cluster/cluster-intro/

> Module 1 of [Learn Kubernetes Basics](../../). Runs on the default **minikube** (v1.39.0, Kubernetes v1.37.0, docker driver).
> The page is mostly theory; its only commands are `minikube start` and `minikube status`.
> Note: the page says minikube "creates a VM". With the docker driver used here, the "node" is a **container**, not a VM.

## Key ideas (read first)

| Part | Role |
|---|---|
| Control Plane | API server, scheduler, controller-manager, etcd: decides and records what should run |
| Node | runs the workloads: kubelet (agent), container runtime (containerd here), kube-proxy |
| minikube | one machine that is both control plane and node |

## Lab
```bash
minikube start            # already running for these labs; starting again is harmless
minikube status
#   minikube
#   type: Control Plane
#   host: Running
#   kubelet: Running
#   apiserver: Running
#   kubeconfig: Configured
kubectl get nodes -o wide
#   minikube   Ready   control-plane   …   v1.37.0   192.168.58.2   …   containerd://2.3.4
docker ps --filter name=^minikube$ --format '{{.Names}} {{.Image}}'      # the "VM" is a container with the docker driver
kubectl get pods -n kube-system -o custom-columns=NAME:.metadata.name --no-headers
#   coredns-…  etcd-minikube  kube-apiserver-minikube  kube-controller-manager-minikube  kube-proxy-…  kube-scheduler-minikube  …
```

Next: [deploy-intro](../../deploy-app/deploy-intro/).
