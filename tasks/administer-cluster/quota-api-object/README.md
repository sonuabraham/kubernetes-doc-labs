# Configure Quotas for API Objects – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/administer-cluster/quota-api-object/

> The docs' YAML is copied **verbatim**: [01-quota-objects.yaml](01-quota-objects.yaml) (ResourceQuota `object-quota-demo`), [02](02-quota-objects-pvc.yaml) and [03](03-quota-objects-pvc-2.yaml) (PVCs on class `manual`). Namespace `quota-object-example`. [04-lb-without-nodeports.yaml](04-lb-without-nodeports.yaml) is extra and covers the Service limits in the same quota.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **Object-count quota** | Caps the **number** of objects per namespace: `persistentvolumeclaims`, `services`, `services.loadbalancers`, `services.nodeports`, `secrets`, `configmaps`, … or generically `count/<resource>.<group>` (e.g. `count/deployments.apps`). |
| **Counted at creation** | A PVC counts as soon as it exists, even while Pending. Here class `manual` has no provisioner and no PV, so it stays Pending and still uses the quota. |
| **LoadBalancers use NodePorts** | A normal `type: LoadBalancer` Service also allocates NodePorts. With `services.nodeports: "0"` it's rejected unless it sets `allocateLoadBalancerNodePorts: false`. |

---

## Step 0
```bash
cd tasks/administer-cluster/quota-api-object
kubectl create namespace quota-object-example
kubectl apply -f 01-quota-objects.yaml --namespace=quota-object-example
kubectl get resourcequota object-quota-demo --namespace=quota-object-example --output=yaml
#   status:
#     hard: {persistentvolumeclaims: "1", services.loadbalancers: "2", services.nodeports: "0"}
#     used: {persistentvolumeclaims: "0", services.loadbalancers: "0", services.nodeports: "0"}
```

## Lab 1 – PVC count (the docs' steps)
```bash
kubectl apply -f 02-quota-objects-pvc.yaml --namespace=quota-object-example
kubectl get persistentvolumeclaims --namespace=quota-object-example
#   pvc-quota-demo   Pending   ...   manual        <- counts even though it's Pending
kubectl apply -f 03-quota-objects-pvc-2.yaml --namespace=quota-object-example
#   Error from server (Forbidden): ... persistentvolumeclaims "pvc-quota-demo-2" is forbidden: exceeded quota: object-quota-demo,
#   requested: persistentvolumeclaims=1, used: persistentvolumeclaims=1, limited: persistentvolumeclaims=1
```

## Lab 2 (extra) – The Service limits in the same quota
```bash
kubectl -n quota-object-example create service nodeport np --tcp=80:80
#   ... services "np" is forbidden: exceeded quota: object-quota-demo, requested: services.nodeports=1, used: services.nodeports=0, limited: services.nodeports=0
kubectl -n quota-object-example create service loadbalancer lb1 --tcp=80:80
#   ... services "lb1" is forbidden: exceeded quota: ... requested: services.nodeports=1 ...     <- the LB wants a NodePort too!
for n in lb1 lb2 lb3; do sed s/NAME/$n/ 04-lb-without-nodeports.yaml | kubectl apply -n quota-object-example -f -; done
#   service/lb1 created
#   service/lb2 created
#   ... services "lb3" is forbidden: exceeded quota: object-quota-demo, requested: services.loadbalancers=1, used: services.loadbalancers=2, limited: services.loadbalancers=2
kubectl describe quota -n quota-object-example
#   persistentvolumeclaims  1  1
#   services.loadbalancers  2  2
#   services.nodeports      0  0
```

---

## Useful commands
```bash
kubectl describe quota -n quota-object-example
kubectl create quota demo --hard=count/deployments.apps=2,count/configmaps=5 -n <ns>     # generic object counts
```

## Cleanup
```bash
./cleanup.sh       # kubectl delete namespace quota-object-example
```
