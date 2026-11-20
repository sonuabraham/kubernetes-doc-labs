# Options for Highly Available Topology – Hands-on Lab

Based on: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/ha-topology/

> The page compares two layouts and has no commands. Both were built in this repo with real kubeadm clusters:
> - **Stacked etcd:** [../high-availability](../high-availability/). cp1–cp3, each with its own etcd member, behind HAProxy.
> - **External etcd:** [../setup-ha-etcd-with-kubeadm](../setup-ha-etcd-with-kubeadm/). A 3-member etcd cluster on its own machines,
>   used by a control plane node.
>
> Observed there: in the stacked layout, freezing one node took out its API server **and** its etcd member at the same time (the
> "coupling" the page warns about). The cluster stayed writable because 2 of 3 etcd members remained.

## Key ideas (read first)

| | Stacked etcd | External etcd |
|---|---|---|
| etcd runs on | every control-plane node (static Pod, `kubeadm join --control-plane` adds it) | separate hosts |
| Each apiserver talks to | its **local** etcd member (`--etcd-servers=https://127.0.0.1:2379`) | **all** etcd members (`etcd.external.endpoints`) |
| Losing one node costs | 1 apiserver + 1 etcd member | 1 apiserver **or** 1 etcd member |
| Minimum for HA | 3 hosts | 3 control-plane + 3 etcd = 6 hosts |
| Set up | default in kubeadm, simpler | etcd first, then `ClusterConfiguration.etcd.external` |
| Quorum | 3 members tolerate 1 failure, 5 tolerate 2 | same |

## Lab
Check the stacked layout in the HA lab:
```bash
./machines.sh x cp2 'grep -- --etcd-servers /etc/kubernetes/manifests/kube-apiserver.yaml'    # - --etcd-servers=https://127.0.0.1:2379
./machines.sh x cp2 'ls /etc/kubernetes/manifests'          # etcd.yaml kube-apiserver.yaml kube-controller-manager.yaml kube-scheduler.yaml
```
Check the external layout in the HA-etcd lab:
```bash
grep -- --etcd-servers /etc/kubernetes/manifests/kube-apiserver.yaml     # three https://172.30.0.x:2379 endpoints
ls /etc/kubernetes/manifests                                             # no etcd.yaml
```

## Cleanup
Nothing of its own; see the two linked labs.
