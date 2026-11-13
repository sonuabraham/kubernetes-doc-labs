# Cloud Controller Manager Administration – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/administer-cluster/running-cloud-controller/

> There's no cloud here, so the lab shows the parts that depend on Kubernetes, not on a cloud, on a throwaway profile **`ccm-lab`** whose kubelet runs with `--cloud-provider=external`:
> - the `uninitialized` taint and what it blocks
> - the docs' example DaemonSet [ccm-example.yaml](ccm-example.yaml), applied **verbatim**
> - a toy CCM, [fake-ccm.sh](fake-ccm.sh), that does a real CCM's node-controller and service-controller jobs for an imaginary cloud `fakecloud`

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **Why a CCM** | Cloud-specific loops live outside `kube-controller-manager`, so each provider ships its own CCM (`cloudprovider.Interface`) on its own schedule. |
| **`--cloud-provider=external`** | Set on the kubelet (and the KCM). The kubelet registers its node **tainted** `node.cloudprovider.kubernetes.io/uninitialized=true:NoSchedule` and waits for the CCM to fill in cloud data. **No CCM → nothing without a toleration schedules.** |
| **Node controller** | Sets `spec.providerID`, addresses, `topology.kubernetes.io/region/zone`, `node.kubernetes.io/instance-type`, then removes the taint. It also deletes Nodes whose VM is gone. |
| **Service controller** | Creates cloud load balancers for `type: LoadBalancer` and writes `status.loadBalancer.ingress`. |
| **Route controller** | Programs cloud routes for Pod CIDRs (`--configure-cloud-routes`). |
| **Requirements** | Cloud credentials (IAM), RBAC to the API server, leader election for HA. |
| **Limitations** | No volume controllers (use CSI), cloud API rate limits on big clusters, and chicken-and-egg issues (kubelet TLS bootstrap vs node addresses). |

---

## Step 0 – a cluster that expects an external cloud provider
```bash
cd tasks/administer-cluster/running-cloud-controller
minikube start -p ccm-lab --memory 2200 --cpus 2 --kubernetes-version v1.37.0 --extra-config=kubelet.cloud-provider=external
kubectl config use-context minikube
K="kubectl --context ccm-lab"
```

## Lab 1 – The uninitialized taint
```bash
until $K get node ccm-lab | grep -q ' Ready'; do sleep 3; done
$K get node ccm-lab -o jsonpath='{.spec.taints}{"\n"}'
#   [{"effect":"NoSchedule","key":"node.cloudprovider.kubernetes.io/uninitialized","value":"true"}]
$K get node ccm-lab -o jsonpath='providerID={.spec.providerID}{"\n"}'          # empty: nobody asked the cloud yet
$K get po -A
#   coredns-...           0/1   Pending      <- even cluster DNS can't start
#   storage-provisioner   0/1   Pending
#   etcd/apiserver/...    Running             (static Pods and DaemonSets with tolerations are fine)
$K -n kube-system describe po -l k8s-app=kube-dns | tail -1
#   FailedScheduling  0/1 nodes are available: 1 node(s) had untolerated taint(s).
```

## Lab 2 – The docs' example DaemonSet
```bash
$K apply -f ccm-example.yaml
#   serviceaccount/cloud-controller-manager created
#   clusterrolebinding.rbac.authorization.k8s.io/system:cloud-controller-manager created
#   daemonset.apps/cloud-controller-manager created
$K -n kube-system get ds cloud-controller-manager
#   NAME                       DESIRED   CURRENT   READY   ...   NODE SELECTOR
#   cloud-controller-manager   0         0         0       ...   node-role.kubernetes.io/master=      <- 0!
$K get nodes -l node-role.kubernetes.io/master          # No resources found
$K get nodes -l node-role.kubernetes.io/control-plane   # ccm-lab
$K delete -f ccm-example.yaml
```
It's a guideline, not a drop-in:
- **Node selector:** the `master` role label was removed from nodes in v1.24, so use `node-role.kubernetes.io/control-plane`.
- **Image:** `cloud-controller-manager:v1.8.0` (2017) still exists, but it's ancient.
- **Provider:** `--cloud-provider=[YOUR_CLOUD_PROVIDER]` must name a provider compiled into the binary.
- **Networking:** `--cluster-cidr=172.17.0.0/16` must match your Pod network.

Today each cloud ships its own CCM (AWS, GCP, Azure, OpenStack, vSphere, ...).

## Lab 3 – Play the CCM
[fake-ccm.sh](fake-ccm.sh) loops every 3 s doing two controllers' jobs for an imaginary cloud:
```bash
$K create deploy web --image=nginx
$K expose deploy web --type=LoadBalancer --port=80
$K get po,svc
#   pod/web-...   0/1   Pending                 service/web   LoadBalancer   10.98.132.203   <pending>
./fake-ccm.sh start
cat fake-ccm.log
#   23:16:04 node controller: initialized ccm-lab (providerID fakecloud://eu-lab-1a/ccm-lab)
#   23:16:04 service controller: load balancer 192.168.184.200 for default/web
$K get node ccm-lab -o jsonpath='taints={.spec.taints} providerID={.spec.providerID}{"\n"}'
#   taints= providerID=fakecloud://eu-lab-1a/ccm-lab
$K get node ccm-lab -L topology.kubernetes.io/zone,node.kubernetes.io/instance-type
#   ccm-lab   Ready   control-plane   v1.37.0   eu-lab-1a   fake.large
$K get po -A | grep -E "coredns|storage|web"
#   web-...  1/1 Running     coredns-... 1/1 Running     storage-provisioner 1/1 Running      <- unblocked
$K get svc web
#   web   LoadBalancer   10.98.132.203   192.168.184.200   80:31877/TCP
```
`providerID` can be set once, and then it's immutable:
```bash
$K patch node ccm-lab --type=merge -p '{"spec":{"providerID":"fakecloud://other"}}'
#   The Node "ccm-lab" is invalid: spec.providerID: Invalid value: null: field cannot be modified once set
```

---

## Useful commands
```bash
kubectl get nodes -o custom-columns=NAME:.metadata.name,PROVIDER:.spec.providerID,TAINTS:.spec.taints[*].key
kubectl get nodes -L topology.kubernetes.io/region,topology.kubernetes.io/zone,node.kubernetes.io/instance-type
kubectl get svc -A --field-selector spec.type=LoadBalancer
```

## Cleanup
```bash
./fake-ccm.sh stop
minikube delete -p ccm-lab
```
