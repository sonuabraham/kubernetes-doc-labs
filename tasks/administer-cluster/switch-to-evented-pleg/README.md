# Switching from Polling to CRI Event-based Updates to Container Status – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/administer-cluster/switch-to-evented-pleg/

> This uses two throwaway single-node profiles, one per runtime tab on the page: **`pleg-lab`** (containerd 2.3.4) and **`pleg-crio`** (CRI-O 1.35.7). [99-pod-events.conf](99-pod-events.conf) is the docs' CRI-O drop-in, **verbatim**. Node commands use [../kubeadm/node.sh](../kubeadm/node.sh).
>
> ⚠️ **Version note:** the page says "beta in v1.27, disabled by default". In v1.37 the gate shows as `kubernetes_feature_enabled{name="EventedPLEG",stage="ALPHA"} 0` (it went back to alpha after 1.27). The kubelet's log lines also differ from the page: in 1.37 events trigger a **fast relist after container termination**, and polling still runs.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **PLEG** | Pod Lifecycle Event Generator: how the kubelet notices container state changes. |
| **Generic PLEG** | Polls (`relist`) every container's status through the CRI. The cost grows with Pods × frequency. |
| **Evented PLEG** | Subscribes to the runtime's **`GetContainerEvents`** stream and reacts to events instead. |
| **Needs both sides** | The kubelet gate `EventedPLEG`, **and** a runtime that emits events. containerd ≥1.7 always does. CRI-O ≥1.26 needs `enable_pod_events = true`. Without events the kubelet falls back. |
| **Rollout** | Per node: gate in the kubelet config → drain → runtime with events → restart → verify in the logs / metrics. |

---

## Lab 1 – containerd
```bash
minikube start -p pleg-lab --memory 2200 --cpus 2 --kubernetes-version v1.37.0 && kubectl config use-context minikube
N(){ P=pleg-lab ../kubeadm/node.sh "$1"; }
N 'containerd --version'                                   # containerd v2.3.4  (>= 1.7: events built in)
# (single node: there is nothing to drain to. On real clusters: kubectl drain <node> --ignore-daemonsets)
N 'printf "featureGates:\n  EventedPLEG: true\n" >> /var/lib/kubelet/config.yaml
   sed -i "s/^  verbosity: 0/  verbosity: 4/" /var/lib/kubelet/config.yaml       # the docs: --v=4 for the detailed lines
   systemctl restart kubelet; sleep 15
   journalctl -u kubelet --since "-20s" | grep -i evented | head -3'
#   feature_gate.go:477] "Updated" featureGates={"EventedPLEG":true}        <- the docs' "feature gates: &{map[EventedPLEG:true]}"
kubectl --context pleg-lab run evt --image=busybox:1.36 -- sh -c 'sleep 5; exit 3'
sleep 20; N 'journalctl -u kubelet --since "-60s" | grep "Evented PLEG"'
#   evented.go:132] "Evented PLEG: requested pod relist after container termination" podUID="3f49d9fc-..." containerID="b0114ef4..."
kubectl --context pleg-lab get --raw /api/v1/nodes/pleg-lab/proxy/metrics | grep -E "^kubelet_evented_pleg_connection_(success|error)_count"
#   kubelet_evented_pleg_connection_error_count 0
#   kubelet_evented_pleg_connection_success_count 1         <- one long-lived event stream to containerd
minikube delete -p pleg-lab
```

## Lab 2 – CRI-O: the gate alone is not enough
```bash
minikube start -p pleg-crio --container-runtime=cri-o --memory 2200 --cpus 2 --kubernetes-version v1.37.0 && kubectl config use-context minikube
N(){ P=pleg-crio ../kubeadm/node.sh "$1"; }
N 'crio --version | head -1; crio config | grep enable_pod_events'
#   crio version 1.35.7
#   # enable_pod_events = false                      <- off by default
N 'printf "featureGates:\n  EventedPLEG: true\n" >> /var/lib/kubelet/config.yaml; systemctl restart kubelet; sleep 15
   journalctl -u kubelet --since "-20s" | grep "Evented PLEG"'
#   E... evented.go:81] "Evented PLEG: disabling container-termination fast path after exhausting event stream retries" err="EOF" retries=5
kubectl --context pleg-crio get --raw /api/v1/nodes/pleg-crio/proxy/metrics | grep -E "^kubelet_evented_pleg_connection_(success|error)_count"
#   kubelet_evented_pleg_connection_error_count 5     <- CRI-O closed the stream: the kubelet falls back to polling only
#   kubelet_evented_pleg_connection_success_count 5
```
Turn events on in CRI-O with the docs' drop-in:
```bash
minikube -p pleg-crio cp 99-pod-events.conf /etc/crio/crio.conf.d/99-pod-events.conf
N 'systemctl restart crio; crio config | grep enable_pod_events; systemctl restart kubelet'
#   enable_pod_events = true
sleep 20; kubectl --context pleg-crio get --raw /api/v1/nodes/pleg-crio/proxy/metrics | grep -E "^kubelet_evented_pleg_connection_(success|error)_count"
#   kubelet_evented_pleg_connection_error_count 0
#   kubelet_evented_pleg_connection_success_count 1
minikube delete -p pleg-crio
```

---

## Useful commands
```bash
journalctl -u kubelet | grep -i evented
kubectl get --raw /api/v1/nodes/<n>/proxy/metrics | grep -E "kubelet_(evented_pleg|pleg_relist)"
crio config | grep enable_pod_events
```

## Cleanup
Both profiles are deleted at the end of each lab: `minikube delete -p pleg-lab ; minikube delete -p pleg-crio`.
