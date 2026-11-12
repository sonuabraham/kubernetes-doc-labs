# Cluster Administration – Hands-on Labs

Based on: https://kubernetes.io/docs/concepts/cluster-administration/

Most labs run on the main `minikube` cluster. Pages that need kubelet or API-server flags use a **throwaway profile** started by a `start-*.sh` script in the lab folder; stop it afterwards (`minikube stop -p <profile>`).

| Page | Environment | Lab shows |
|---|---|---|
| [node-shutdown](node-shutdown/) | `shutdown-lab` profile + fake nodes | graceful shutdown by priority; non-graceful shutdown with the `out-of-service` taint |
| [swap-memory-management](swap-memory-management/) | `swap-lab` profile (LimitedSwap) | which QoS classes may swap, and how much |
| [node-autoscaling](node-autoscaling/) | fake nodes + [toy-autoscaler.sh](node-autoscaling/toy-autoscaler.sh) | provisioning for pending Pods and consolidation |
| [certificates](certificates/) | main cluster, read-only | the PKI the cluster actually uses |
| [networking](networking/) | main cluster, read-only | Pod, Service and node ranges, and the CNI |
| [observability](observability/) | main cluster | one example of each signal |
| [admission-webhooks-good-practices](admission-webhooks-good-practices/) | main cluster + a toy webhook | timeouts, failurePolicy, scoping, idempotence, VAP alternative |
| [dra](dra/) | fake DRA driver | admin vs. user permissions, DRA metrics |
| [logging](logging/) | main cluster | container logs, where they live on the node, streaming sidecars |
| [compatibility-version](compatibility-version/) | `compat-lab` profile (`--emulated-version=1.36`) | APIs and gates as of the emulated version |
| [system-metrics](system-metrics/) | main cluster | scraping component `/metrics`, stability levels, label allow-lists |
| [kube-state-metrics](kube-state-metrics/) | main cluster + kube-state-metrics add-on | object-state metrics and the docs' alert |
| [system-logs](system-logs/) | main cluster + throwaway profile | text vs. JSON logs, verbosity, kubelet log query |
| [system-traces](system-traces/) | `trace-lab` profile + OTel collector | API-server and kubelet spans |
| [proxies](proxies/) | main cluster | kubectl proxy, apiserver proxy, kube-proxy, LB |
| [flow-control](flow-control/) | main cluster | the docs' FlowSchemas, APF metrics and debug endpoints |
| [addons](addons/) | main cluster, read-only | what this cluster runs, by add-on category |
| [coordinated-leader-election](coordinated-leader-election/) | `cle-lab` profile + [candidate.sh](coordinated-leader-election/candidate.sh) | LeaseCandidates, `preferredHolder` handover, failover |

Related: fake nodes come from `../scheduling-eviction/fake-nodes.sh`, the fake DRA driver from `../resource-management/dynamic-resource-allocation/fake-dra.sh`, and Leases in general from `../architecture/leases`.
