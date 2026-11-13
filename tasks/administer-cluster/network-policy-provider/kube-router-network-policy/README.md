# Use Kube-router for NetworkPolicy – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/administer-cluster/network-policy-provider/kube-router-network-policy/

> The page describes the Kube-router add-on's Network Policy Controller. Here it's installed with kube-router's kubeadm manifest (`daemonset/kubeadm-kuberouter.yaml`: pod networking + firewall, kube-proxy left in place) on a CNI-less throwaway profile. The policy test is [../np-test.sh](../np-test.sh).

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **Kube-router** | One binary, three optional roles: `--run-router` (pod networking/BGP), `--run-firewall` (**NetworkPolicy controller**), `--run-service-proxy` (IPVS kube-proxy replacement). This manifest runs router + firewall. |
| **How it enforces** | It watches NetworkPolicies, Pods and Namespaces, and programs **iptables chains + ipsets** on each node (chains named `KUBE-ROUTER-*`, `KUBE-POD-FW-*`, `KUBE-NWPLCY-*`). |
| **CNI** | Its init container writes a bridge CNI config (`cniVersion 1.0.0`) using the node's `podCIDR`. |

---

## Step 0 – minikube without a CNI
```bash
cd tasks/administer-cluster/network-policy-provider/kube-router-network-policy
minikube start -p np-kuberouter --network-plugin=cni --memory 2200 --cpus 2 --kubernetes-version v1.37.0
kubectl config use-context minikube
```

## Lab 1 – Install the add-on
```bash
curl -sSLo /tmp/kuberouter.yaml https://raw.githubusercontent.com/cloudnativelabs/kube-router/master/daemonset/kubeadm-kuberouter.yaml
grep -nE "image:|--run-" /tmp/kuberouter.yaml
#   image: docker.io/cloudnativelabs/kube-router
#   - --run-router=true   - --run-firewall=true   - --run-service-proxy=false
kubectl --context np-kuberouter apply -f /tmp/kuberouter.yaml
#   daemonset.apps/kube-router created   serviceaccount/kube-router created   clusterrole(binding).../kube-router created
kubectl --context np-kuberouter -n kube-system get po -l k8s-app=kube-router
kubectl --context np-kuberouter get nodes          # Ready once the init container has written the CNI config
```

## Lab 2 – Is NetworkPolicy enforced?
```bash
../np-test.sh np-kuberouter
```
```
1. no policy:                      allowed=reach denied=reach
2. default-deny-ingress:           allowed=BLOCKED denied=BLOCKED
3. + allow from access=true:       allowed=reach denied=BLOCKED
```
```bash
minikube ssh -p np-kuberouter -- 'sudo iptables-save | grep -c KUBE-ROUTER'      # 44 rules
```

---

## Useful commands
```bash
kubectl -n kube-system logs ds/kube-router | grep -i policy
iptables-save | grep -E "KUBE-(ROUTER|POD-FW|NWPLCY)"
```

## Cleanup
```bash
minikube delete -p np-kuberouter
```
