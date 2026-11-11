# EndpointSlices – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/services-networking/endpoint-slices/

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **EndpointSlice** | `discovery.k8s.io/v1` (stable 1.21). A list of network endpoints (IPs + ports) backing a Service. kube-proxy, ingress controllers and service meshes read these. It replaced the old `Endpoints` API, which is deprecated since v1.33. |
| **Linked to its Service** | By the label **`kubernetes.io/service-name`**. A Service can have **several** slices (default max **100 endpoints** each, `--max-endpoints-per-slice`). |
| **addressType** | `IPv4`, `IPv6` or `FQDN`. A dual-stack Service gets a slice per family. |
| **Conditions** | `ready` (ready **and** not terminating), `serving` (passes readiness, even while terminating), `terminating`. Lets proxies drain gracefully. |
| **Topology** | Per endpoint: `nodeName`, `zone`, and `hints` (for topology-aware routing). |
| **Management** | `endpointslice.kubernetes.io/managed-by`: `endpointslice-controller.k8s.io` for Services with a selector, the mirroring controller for legacy Endpoints, or **your own value** for slices you manage. Controller slices are **owned** by the Service. |
| **Selector-less Services** | Create the slices yourself, to point a Service at external IPs or anything else. |
| **Duplicates** | The same endpoint may briefly appear in two slices. Clients must deduplicate. |
| **Mirroring** (deprecated) | A legacy `Endpoints` object for a selector-less Service is copied into an EndpointSlice. |

## The demo app
[endpointslice-example-abc.yaml](endpointslice-example-abc.yaml) is the docs manifest **verbatim**: slice `example-abc` for Service `example`, with endpoint `10.1.2.3`, `hostname: pod-1`, `nodeName: node-1`, `zone: us-west2-a`.
[00-demo-app.yaml](00-demo-app.yaml) (namespace `eps-demo`) has Deployment + Service `web` (preStop sleep 20s, readiness probe) and a **selector-less** Service `example` for the docs slice. [01-legacy-endpoints.yaml](01-legacy-endpoints.yaml) is a legacy Endpoints object, for mirroring.

---

## Lab 1 – Slices the control plane manages
```bash
cd concepts/services-networking/endpoint-slices
kubectl apply -f 00-demo-app.yaml ; kubectl rollout status deploy/web -n eps-demo
kubectl get endpointslices -n eps-demo -l kubernetes.io/service-name=web
#   web-bbzts   IPv4   80   10.244.0.159,10.244.0.157,10.244.0.158
kubectl get endpointslice -n eps-demo -l kubernetes.io/service-name=web -o json \
  | jq '.items[0] | {labels: .metadata.labels, owner: .metadata.ownerReferences[0].kind, ports, endpoints: [.endpoints[] | {addr: .addresses[0], conditions, nodeName, pod: .targetRef.name}]}'
#   labels: managed-by=endpointslice-controller.k8s.io, kubernetes.io/service-name=web
#   owner: Service
#   each endpoint: ready/serving true, terminating false, nodeName minikube, targetRef → the Pod
```

## Lab 2 – Conditions during graceful termination
```bash
P=$(kubectl get pod -n eps-demo -l app=web -o jsonpath='{.items[0].metadata.name}')
kubectl delete pod $P -n eps-demo --wait=false ; sleep 4
kubectl get endpointslice -n eps-demo -l kubernetes.io/service-name=web -o json | jq -c --arg p $P '.items[].endpoints[] | select(.targetRef.name==$p) | .conditions'
#   {"ready":false,"serving":true,"terminating":true}
```
The Pod is shutting down (its preStop holds it for 20s) but still able to serve. kube-proxy stops sending **new** traffic (`ready=false`), and could still fall back to it (`serving=true`) if no other endpoint were left.

## Lab 3 – Your own slice for a selector-less Service (docs example)
```bash
kubectl apply -f endpointslice-example-abc.yaml -n eps-demo
kubectl get endpointslices -n eps-demo -l kubernetes.io/service-name=example
#   example-abc   IPv4   80   10.1.2.3
kubectl get svc example -n eps-demo           # ClusterIP Service with NO selector - traffic goes to 10.1.2.3:80
```
No controller touches this slice: no managed-by label, no owner. `node-1` and `us-west2-a` are just data. Nothing checks them against real nodes.

## Lab 4 – Changes are tracked
```bash
kubectl scale deploy/web -n eps-demo --replicas=5
kubectl get endpointslices -n eps-demo -l kubernetes.io/service-name=web -w
```
Endpoints are added to the existing slice. A slice is split only beyond 100 endpoints (that needs more pods than a single minikube node allows, max 110 pods per node).

## Lab 5 – Mirroring legacy Endpoints (deprecated)
```bash
kubectl apply -f 01-legacy-endpoints.yaml
#   Warning: v1 Endpoints is deprecated in v1.33+; use discovery.k8s.io/v1 EndpointSlice
kubectl get endpointslice -n eps-demo -l kubernetes.io/service-name=legacy -o json \
  | jq -c '.items[0] | {managedBy: .metadata.labels["endpointslice.kubernetes.io/managed-by"], addrs: [.endpoints[].addresses[0]]}'
#   {"managedBy":"endpointslicemirroring-controller.k8s.io","addrs":["10.9.9.10","10.9.9.9"]}
```

---

## Useful commands
```bash
kubectl get endpointslices -l kubernetes.io/service-name=<svc>
kubectl get endpointslice <name> -o yaml
kubectl explain endpointslice.endpoints.conditions
```

## Cleanup
```bash
./cleanup.sh
```
