# Use Calico for NetworkPolicy – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/administer-cluster/network-policy-provider/calico-network-policy/

> The page offers a GKE cluster (`gcloud container clusters create my-calico-cluster --enable-network-policy`) or a local kubeadm cluster via the Calico Quickstart. The local equivalent here is minikube's built-in Calico (`--cni=calico`) on a throwaway profile. The policy test is [../np-test.sh](../np-test.sh).

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **Calico** | A CNI plugin (routing via BGP/VXLAN/IPIP) plus a policy engine that programs **iptables/eBPF** rules for every NetworkPolicy. |
| **Components** | `calico-node` DaemonSet (on every node: Felix programs the rules; IPAM, routing) and `calico-kube-controllers` Deployment. |
| **Extra APIs** | Beyond Kubernetes `NetworkPolicy`: `crd.projectcalico.org` NetworkPolicy / **GlobalNetworkPolicy** (cluster-wide, ordered, with deny rules), staged policies, and so on. |

---

## Step 0 – a Calico cluster
```bash
cd tasks/administer-cluster/network-policy-provider/calico-network-policy
minikube start -p np-calico --cni=calico --memory 2200 --cpus 2 --kubernetes-version v1.37.0
kubectl config use-context minikube
```

## Lab 1 – Verify the deployment (the docs' check)
```bash
kubectl --context np-calico get pods --namespace=kube-system
#   calico-kube-controllers-db57f7644-wsxzc   1/1   Running        <- names begin with "calico", all Running
#   calico-node-7md2p                         1/1   Running
#   coredns-... etcd-... kube-apiserver-... kube-proxy-...
kubectl --context np-calico get ds calico-node -n kube-system -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
#   quay.io/calico/node:v3.32.2
kubectl --context np-calico get crd -o name | grep -c projectcalico          # 22 Calico CRDs
kubectl --context np-calico get crd -o name | grep networkpolic
#   globalnetworkpolicies.crd.projectcalico.org   networkpolicies.crd.projectcalico.org   staged...
```

## Lab 2 – Is NetworkPolicy enforced?
```bash
../np-test.sh np-calico
```
```
1. no policy:                      allowed=reach denied=reach
2. default-deny-ingress:           allowed=BLOCKED denied=BLOCKED
3. + allow from access=true:       allowed=reach denied=BLOCKED
```
```bash
minikube ssh -p np-calico -- 'sudo iptables-save | grep -c "^-A cali-"'      # 146 rules in Calico's own chains
```
For the full walkthrough, continue with [../../declare-network-policy](../../declare-network-policy/).

---

## Useful commands
```bash
kubectl get pods -n kube-system -l k8s-app=calico-node
kubectl get networkpolicies.crd.projectcalico.org,globalnetworkpolicies.crd.projectcalico.org -A
```

## Cleanup
```bash
minikube delete -p np-calico
```
