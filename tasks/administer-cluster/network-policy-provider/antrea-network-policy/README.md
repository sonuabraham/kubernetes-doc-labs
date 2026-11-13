# Use Antrea for NetworkPolicy – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/administer-cluster/network-policy-provider/antrea-network-policy/

> The page points to Antrea's Getting Started guide: apply the release manifest `antrea.yml` to a cluster that has no CNI yet. Here that is a throwaway minikube profile started with `--network-plugin=cni`. The policy test is [../np-test.sh](../np-test.sh).

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **Antrea** | A CNI built on **Open vSwitch**. Pod traffic goes through an OVS bridge, and NetworkPolicies become **OpenFlow** rules (not iptables). |
| **Components** | `antrea-agent` DaemonSet (2 containers: agent + OVS) and `antrea-controller` Deployment. The controller computes policy for each node and serves it through an aggregated API (`controlplane.antrea.io`, `stats.antrea.io`). |
| **Extra APIs** | Antrea-native policies (`crd.antrea.io`: tiered, ordered, with deny/drop actions), plus webhooks that validate them. |
| **Host requirement** | The **openvswitch** kernel module. kic nodes share the host kernel, and on this host it loaded without help. |

---

## Step 0 – minikube without a CNI
```bash
cd tasks/administer-cluster/network-policy-provider/antrea-network-policy
minikube start -p np-antrea --network-plugin=cni --memory 2200 --cpus 2 --kubernetes-version v1.37.0
kubectl config use-context minikube
```

## Lab 1 – Deploy Antrea (Getting Started)
```bash
TAG=$(curl -sSL https://api.github.com/repos/antrea-io/antrea/releases/latest | python3 -c 'import json,sys;print(json.load(sys.stdin)["tag_name"])')
echo $TAG                                                            # v2.7.0 when tested
kubectl --context np-antrea apply -f https://github.com/antrea-io/antrea/releases/download/$TAG/antrea.yml
#   ... apiservice.apiregistration.k8s.io/v1alpha1.stats.antrea.io created
#   mutatingwebhookconfiguration.admissionregistration.k8s.io/crdmutator.antrea.io created
#   validatingwebhookconfiguration.admissionregistration.k8s.io/crdvalidator.antrea.io created
kubectl --context np-antrea -n kube-system get po -l app=antrea
#   antrea-agent-vhzdn                   2/2   Running
#   antrea-controller-746bff87b8-4r9xr   1/1   Running
kubectl --context np-antrea get nodes                                  # Ready
```

## Lab 2 – Is NetworkPolicy enforced?
```bash
../np-test.sh np-antrea
```
```
1. no policy:                      allowed=reach denied=reach
2. default-deny-ingress:           allowed=BLOCKED denied=BLOCKED
3. + allow from access=true:       allowed=reach denied=BLOCKED
```

---

## Useful commands
```bash
kubectl get apiservice | grep antrea
kubectl -n kube-system exec ds/antrea-agent -c antrea-ovs -- ovs-vsctl show
```

## Cleanup
```bash
minikube delete -p np-antrea
```
