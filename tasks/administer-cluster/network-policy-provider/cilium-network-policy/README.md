# Use Cilium for NetworkPolicy – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/administer-cluster/network-policy-provider/cilium-network-policy/

> This follows the page's minikube route: start minikube with `--network-plugin=cni` (no CNI), download the `cilium` CLI, then `cilium install`. The CLI goes into `../bin/` (gitignored) instead of `/usr/local/bin`, so no sudo is needed. The policy test is [../np-test.sh](../np-test.sh).

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **Cilium** | A CNI built on **eBPF**. Policies are enforced in the kernel by BPF programs, not iptables chains, and can go up to **L7** (HTTP, Kafka, DNS) with `CiliumNetworkPolicy`. |
| **cilium install** | Detects the cluster (name, kube-proxy present, ...) and installs with Helm under the hood: CA Secret `cilium-ca`, ServiceAccounts, RBAC, ConfigMap, the `cilium` agent DaemonSet, `cilium-operator`, and in 1.20 also a `cilium-envoy` DaemonSet for L7. |
| **Status** | `cilium status --wait` shows Cilium, Operator and Envoy as OK, and "Cluster Pods managed by Cilium". |

---

## Step 0 – minikube without a CNI
```bash
cd tasks/administer-cluster/network-policy-provider/cilium-network-policy
minikube version
minikube start -p np-cilium --network-plugin=cni --memory 2200 --cpus 2 --kubernetes-version v1.37.0
#   ! With --network-plugin=cni, you will need to provide your own CNI. See --cni flag as a user-friendly alternative
kubectl config use-context minikube
kubectl --context np-cilium get nodes            # NotReady - no network plugin yet
```

## Lab 1 – Install the CLI and Cilium
```bash
mkdir -p ../bin && cd ../bin
curl -LO https://github.com/cilium/cilium-cli/releases/latest/download/cilium-linux-amd64.tar.gz
tar xzvfC cilium-linux-amd64.tar.gz .        # docs: sudo tar xzvfC cilium-linux-amd64.tar.gz /usr/local/bin
rm cilium-linux-amd64.tar.gz
./cilium version --client
#   cilium-cli: v0.20.3   cilium image (default): v1.20.3
cd ../cilium-network-policy
../bin/cilium install --context np-cilium
#   ℹ️  Using Cilium version 1.20.3
#   🔮 Auto-detected cluster name: np-cilium
#   🔮 Auto-detected kube-proxy has been installed
../bin/cilium status --context np-cilium --wait
#   Cilium: OK   Operator: OK   Envoy DaemonSet: OK   Hubble Relay: disabled   ClusterMesh: disabled
#   DaemonSet  cilium  Desired: 1, Ready: 1/1 ...   Deployment cilium-operator  Ready: 1/1
#   Cluster Pods:  1/1 managed by Cilium
```

## Lab 2 – Cilium components
```bash
kubectl --context np-cilium get pods --namespace=kube-system -l k8s-app=cilium
#   NAME           READY   STATUS    RESTARTS   AGE
#   cilium-zxlj9   1/1     Running   0          88s       <- one agent per node, enforcing policy with BPF
kubectl --context np-cilium -n kube-system get secret cilium-ca
kubectl --context np-cilium get nodes                     # Ready now
```

## Lab 3 – Is NetworkPolicy enforced?
```bash
../np-test.sh np-cilium
```
```
1. no policy:                      allowed=reach denied=reach
2. default-deny-ingress:           allowed=BLOCKED denied=BLOCKED
3. + allow from access=true:       allowed=reach denied=BLOCKED
```

---

## Useful commands
```bash
cilium status ; cilium connectivity test      # (the latter deploys a large test suite)
kubectl get ciliumnetworkpolicies -A ; kubectl get ciliumendpoints -A
```

## Cleanup
```bash
minikube delete -p np-cilium ; rm -rf ../bin
```
