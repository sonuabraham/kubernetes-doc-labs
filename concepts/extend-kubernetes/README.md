# Extending Kubernetes – Hands-on Labs

Based on: https://kubernetes.io/docs/concepts/extend-kubernetes/

The overview page is a map of the places where Kubernetes can be changed **without changing its code**. Each extension point has a working lab in this repo:

| # | Extension point (overview page) | What runs where | Lab |
|---|---|---|---|
| — | **Configuration**: flags and config files of kube-apiserver, controller-manager, scheduler, kubelet, kube-proxy | the components themselves | throwaway-profile labs, e.g. `../cluster-administration/compatibility-version`, `../security/secrets-good-practices` (encryption config) |
| 1 | **Client extensions**: kubectl plugins | your machine | [plugins/kubectl-podcount](plugins/kubectl-podcount), below |
| 2 | **API access**: authentication, authorization, **admission webhooks** / ValidatingAdmissionPolicy | in the API server request path | `../security/controlling-access`, `../cluster-administration/admission-webhooks-good-practices` (a real webhook) |
| 3 | **API extensions**: CustomResourceDefinitions | API server + etcd | [api-extension/custom-resources](api-extension/custom-resources/) |
| 3 | **API extensions**: aggregation layer | your API server behind kube-apiserver | [api-extension/apiserver-aggregation](api-extension/apiserver-aggregation/) (a real extension API server) |
| 3+5 | **New APIs + automation** = Operator | a controller Deployment | [operator](operator/) (a working SampleDB operator) |
| 4 | **Scheduling extensions**: scheduler plugins/profiles, extra schedulers | kube-scheduler | `../scheduling-eviction/scheduling-framework`, `../scheduling-eviction/running-multiple-schedulers` |
| 5 | **Controllers** | anywhere with API access | [operator](operator/), plus the toy controllers in `../services-networking/ingress-controllers`, `../cluster-administration/node-autoscaling` |
| 6 | **Network plugins** (CNI) | container runtime on each node | [compute-storage-net/network-plugins](compute-storage-net/network-plugins/) |
| 6 | **Storage plugins** (CSI) | node + controller Pods | `../storage/*` (csi-hostpath-driver), `../storage/volume-populators-and-data-sources` (a toy populator) |
| 7 | **Device plugins** | DaemonSet talking to the kubelet | [compute-storage-net/device-plugins](compute-storage-net/device-plugins/) (a real gRPC device plugin) |
| — | **Kubelet image credential provider plugins** | executable called by the kubelet | not built here (needs a registry that requires credentials) |

Patterns from the page:
- **Controller pattern**: watch → compare → act → status. See [operator](operator/).
- **Webhook pattern**: the API server calls *you*, for admission, authentication or authorization.
- **Binary plugin pattern**: a component execs *your* binary, as with kubectl plugins, CNI, and credential providers.

## kubectl plugins
```bash
cd concepts/extend-kubernetes
export PATH=$PWD/plugins:$PATH          # a plugin is any executable named kubectl-<name> on PATH
kubectl plugin list
#   /home/sonu/study/kubernetes/k8s-docs/concepts/extend-kubernetes/plugins/kubectl-podcount
kubectl podcount
#   14 minikube   Running
```

## Labs in this section
- [compute-storage-net/network-plugins](compute-storage-net/network-plugins/): CNI chain, hostPort, bandwidth shaping, CNI by hand
- [compute-storage-net/device-plugins](compute-storage-net/device-plugins/): toy device plugin, Allocate, health, PodResources API
- [api-extension/custom-resources](api-extension/custom-resources/): CRD features, field selectors, RBAC aggregation
- [api-extension/apiserver-aggregation](api-extension/apiserver-aggregation/): APIService, front-proxy authentication, failure modes
- [operator](operator/): the docs' SampleDB operator, end to end
