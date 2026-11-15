# Monitoring, Logging, and Debugging – Section Overview

Based on: https://kubernetes.io/docs/tasks/debug/

> The section's landing page: a map of the four sub-sections plus "Getting help". The only hands-on part is the
> information a bug report needs, collected by [bug-report-info.sh](bug-report-info.sh) (not from the docs as a script).

## Key ideas (read first)

| You are… | Start at |
|---|---|
| deploying an app that doesn't work | [debug-application/](debug-application/): Pods, Services, StatefulSets, init containers, running Pods, shells |
| operating the cluster itself | [debug-cluster/](debug-cluster/): nodes, kubectl, metrics, crictl, audit, node debugging |
| setting up logging | [logging/](logging/) → the concept labs on logging architecture and system logs |
| setting up monitoring | [monitoring/](monitoring/) → the concept labs on system metrics and traces |
| still stuck | Stack Overflow (app) / Server Fault (cluster), Slack `#kubernetes-users`, discuss.kubernetes.io, GitHub issues for bugs |

## Lab – What to put in a bug report
The page asks for: Kubernetes version · cloud provider, OS distro, network configuration and container runtime version · steps to reproduce.
```bash
cd tasks/debug
./bug-report-info.sh
```
```
## kubectl version
Client Version: v1.35.10
Server Version: v1.37.0
Warning: version difference between client (1.35) and server (1.37) exceeds the supported minor version skew of +/-1   <- worth fixing BEFORE reporting
## per-node runtime / OS / kernel
NODE       OS                               KERNEL             RUNTIME              KUBELET   ARCH
minikube   Debian GNU/Linux 12 (bookworm)   7.0.0-38-generic   containerd://2.3.4   v1.37.0   amd64
## provider (spec.providerID / well-known labels)
minikube   <none>        <none>     <none>          <- no cloud provider
## network: CNI pods, Service CIDR, Pod CIDRs
kindnet-wt5hc … kube-proxy-c8bcn …
kubernetes   10.96.0.0/12
minikube   [10.244.0.0/24]
## control plane health
readyz check passed
```
Also check the known issues in the release notes of your version (https://github.com/kubernetes/kubernetes/releases).
Review the output before posting it publicly: it contains IPs and host names.
