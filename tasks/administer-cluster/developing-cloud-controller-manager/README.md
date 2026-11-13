# Developing Cloud Controller Manager – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/administer-cluster/developing-cloud-controller-manager/

> This follows the page's three "out of tree" steps literally and builds a **working CCM for an imaginary cloud `fakecloud`** in Go ([fakecloud-ccm/](fakecloud-ccm/)):
> 1. [pkg/fakecloud/fakecloud.go](fakecloud-ccm/pkg/fakecloud/fakecloud.go) implements `cloudprovider.Interface` (InstancesV2 + LoadBalancer).
> 2. [main.go](fakecloud-ccm/main.go) is `kubernetes/cmd/cloud-controller-manager/main.go` (release-1.37) used as the template.
> 3. The provider registers itself in `init()` with `cloudprovider.RegisterCloudProvider`.
>
> "The cloud" is a JSON file, [cloud-config.json](cloud-config.json), listing the VMs that exist. The binary is built in a `golang` container and run against a throwaway profile **`ccmdev-lab`** (kubelet `--cloud-provider=external`) with [run-ccm.sh](run-ccm.sh). For the operator's side, see [../running-cloud-controller](../running-cloud-controller/).

## Key ideas (read first)

| Piece | Meaning |
|---|---|
| **`cloudprovider.Interface`** | `Initialize`, `ProviderName`, `HasClusterID`, plus accessors that return `(impl, true)` for what your cloud supports: `InstancesV2`, `LoadBalancer`, `Routes`, `Zones`, `Clusters`, `Instances` (legacy). Return `false` for features you don't support. |
| **InstancesV2** | `InstanceExists`, `InstanceShutdown`, `InstanceMetadata` (providerID, type, region/zone, addresses, extra labels). Used by the **cloud-node** controller (initialize new nodes, remove the `uninitialized` taint) and the **cloud-node-lifecycle** controller (delete Nodes whose VM is gone). |
| **LoadBalancer** | `GetLoadBalancer`, `GetLoadBalancerName`, `EnsureLoadBalancer`, `UpdateLoadBalancer` (backend nodes changed), `EnsureLoadBalancerDeleted`. Used by the **service** controller. |
| **Registration** | `cloudprovider.RegisterCloudProvider(name, factory)` in `init()`. `--cloud-provider=<name>` selects it, and `--cloud-config` is handed to the factory as an `io.Reader`. |
| **main.go** | Mostly boilerplate: options, `app.NewCloudControllerManagerCommand(..., cloudInitializer, ...)`. The core template also wires the **node IPAM** controller from `k8s.io/kubernetes`. That block is removed here, as in `k8s.io/cloud-provider/sample/basic_main.go`, because out-of-tree code shouldn't import `k8s.io/kubernetes`. |

---

## Step 0 – build
```bash
cd tasks/administer-cluster/developing-cloud-controller-manager/fakecloud-ccm
docker run --rm -e GOTOOLCHAIN=auto -v $PWD:/src -w /src golang:1.25 sh -c '
  go get k8s.io/cloud-provider@v0.37.0 k8s.io/component-base@v0.37.0 k8s.io/api@v0.37.0 k8s.io/apimachinery@v0.37.0 k8s.io/klog/v2
  go mod tidy && CGO_ENABLED=0 go build -o bin/fakecloud-ccm . && chown -R 1000:1000 /src'
ls -la bin/fakecloud-ccm            # ~106 MB static binary (bin/ is gitignored); go.mod/go.sum are committed
cd ..
```

## Step 1 – a cluster waiting for a cloud provider
```bash
minikube start -p ccmdev-lab --memory 2200 --cpus 2 --kubernetes-version v1.37.0 --extra-config=kubelet.cloud-provider=external
kubectl config use-context minikube
kubectl config view --minify --flatten --context ccmdev-lab > fakecloud-ccm/bin/kubeconfig
K="kubectl --context ccmdev-lab"
$K get node ccmdev-lab -o jsonpath='taints={.spec.taints[*].key} providerID={.spec.providerID}{"\n"}'
#   taints=node.cloudprovider.kubernetes.io/uninitialized node.kubernetes.io/not-ready providerID=
```

## Lab 1 – Node controller: initialize the node
```bash
./run-ccm.sh start
#   (--cloud-provider=fakecloud --cloud-config=cloud-config.json --controllers=cloud-node,cloud-node-lifecycle,service ...)
$K get node ccmdev-lab -o jsonpath='taints={.spec.taints[*].key} providerID={.spec.providerID}{"\n"}'
#   taints=node.kubernetes.io/not-ready providerID=fakecloud://eu-lab-1a/ccmdev-lab        <- uninitialized taint removed
$K get node ccmdev-lab -L topology.kubernetes.io/region,topology.kubernetes.io/zone,node.kubernetes.io/instance-type,fakecloud.example.com/managed
#   ccmdev-lab   ...   eu-lab-1   eu-lab-1a   fake.large   true
grep -E "fakecloud:|Successfully initialized" fakecloud-ccm/bin/ccm.log
#   fakecloud.go:55] fakecloud: region "eu-lab-1" with 1 instances
#   fakecloud.go:95] fakecloud: InstanceMetadata(ccmdev-lab) = fakecloud://eu-lab-1a/ccmdev-lab eu-lab-1/eu-lab-1a
#   node_controller.go:477] Successfully initialized node ccmdev-lab with cloud provider
```

## Lab 2 – Service controller: a LoadBalancer
```bash
$K create deploy web --image=nginx && $K expose deploy web --type=LoadBalancer --port=80
$K get svc web
#   web   LoadBalancer   10.98.8.65   203.0.113.200   80:30328/TCP        <- IP returned by EnsureLoadBalancer
grep -E "LoadBalancer" fakecloud-ccm/bin/ccm.log
#   fakecloud: EnsureLoadBalancer(kubernetes-default-web) -> 203.0.113.200, backends: 0 nodes
#   "Event occurred" object="default/web" ... reason="EnsuredLoadBalancer" message="Ensured load balancer"
```
0 backends: the only node is a control plane carrying `node.kubernetes.io/exclude-from-external-load-balancers`.

## Lab 3 – Node lifecycle controller: a VM that doesn't exist
```bash
printf 'apiVersion: v1\nkind: Node\nmetadata:\n  name: ghost-vm\n' | $K apply -f -
$K get nodes              # ghost-vm   Unknown
sleep 30; $K get node ghost-vm       # NotFound
grep -E "ghost" fakecloud-ccm/bin/ccm.log
#   Updating backends for load balancer default/web with 1 nodes: [ghost-vm]      <- briefly an LB backend
#   fakecloud: UpdateLoadBalancer(kubernetes-default-web), backends: 1 nodes
#   fakecloud: InstanceExists(ghost-vm) = false
#   node_lifecycle_controller.go:182] deleting node since it is no longer present in cloud provider: ghost-vm
#   fakecloud: UpdateLoadBalancer(kubernetes-default-web), backends: 0 nodes
$K delete svc web
grep -E "EnsureLoadBalancerDeleted|DeletedLoadBalancer" fakecloud-ccm/bin/ccm.log
#   fakecloud: EnsureLoadBalancerDeleted(kubernetes-default-web) - releasing 203.0.113.200
#   ... reason="DeletedLoadBalancer" message="Deleted load balancer"
```

---

## Useful commands
```bash
fakecloud-ccm/bin/fakecloud-ccm --help | grep -E "cloud-provider|controllers|cloud-config"
kubectl get nodes -o custom-columns=NAME:.metadata.name,PROVIDER:.spec.providerID
kubectl get events -A --field-selector reason=EnsuredLoadBalancer
```

## Cleanup
```bash
./run-ccm.sh stop
minikube delete -p ccmdev-lab
```
