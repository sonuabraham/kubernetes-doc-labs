# Kubernetes Gateway API – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/services-networking/gateway/

> **From the docs:** Gateway API is a family of API kinds for dynamic infrastructure provisioning and advanced traffic routing. It is an **add-on**: the kinds are **Custom Resources (CRDs)**, not built into Kubernetes, and a controller ("implementation") does the actual work. It is the successor to Ingress (see `../ingress`), whose API is frozen.
> This lab uses **Envoy Gateway** as the implementation. Its install manifest also installs the Gateway API CRDs. The API objects are the same for every conformant implementation (Cilium, Istio, NGINX Gateway Fabric, Traefik, kgateway…). Only the GatewayClass `controllerName` and how the proxy gets deployed differ.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Role-oriented** | Different objects for different people. **Infrastructure provider** → GatewayClass. **Cluster operator** → Gateway. **Application developer** → HTTPRoute/GRPCRoute. Ingress mixed all three into one object plus annotations. |
| **Portable / Expressive / Extensible** | Same CRDs everywhere. Header matching, weighting, rewrites and redirects are real fields, not annotations. Custom resources can be plugged in at several layers. |
| **GatewayClass** | Cluster-scoped. `spec.controllerName` names the controller that manages Gateways of this class. Similar to an IngressClass. |
| **Gateway** | An instance of traffic-handling infrastructure: a cloud LB or an in-cluster proxy. It has `listeners` (name, protocol, port, optional hostname, TLS, `allowedRoutes`). With no `addresses` set, the controller assigns one. |
| **HTTPRoute** | HTTP routing from a Gateway listener to backends. `parentRefs` (which Gateway) + `hostnames` + `rules[]` (`matches`, `filters`, `backendRefs`). |
| **GRPCRoute** | Same idea for gRPC. Matches on gRPC **service / method**. A Gateway that supports it must speak HTTP/2 without an HTTP/1 upgrade. |
| **Bidirectional trust** | A route names its Gateway (`parentRefs`), and the Gateway listener must also **allow** the route (`allowedRoutes`). By default only routes in the **same namespace** are allowed. |
| **ReferenceGrant** | Lets objects in namespace A refer to objects in namespace B, for example an HTTPRoute → a Service, or a Gateway → a TLS Secret. It lives in **B**, the namespace being referenced. |
| **Status** | Controllers write conditions back to the objects: GatewayClass `Accepted`, Gateway `Accepted`/`Programmed` plus `addresses`, Route `status.parents[]` `Accepted`/`ResolvedRefs`. **Always read status when something doesn't work.** |
| **Request flow** | Client resolves DNS → Gateway IP. The proxy matches the **Host** against listener and route hostnames, then optionally path/headers (`matches`), then optionally modifies the request (`filters`), then forwards to one or more `backendRefs` (weighted). |
| **Conformance / channels** | Features are graded **Core** (every implementation), **Extended** (optional but portable), or **Implementation-specific**. CRDs ship in a **Standard** channel (GA/beta) and an **Experimental** channel. |
| **Migrating from Ingress** | Gateway API has no Ingress kind, so you do a **one-time conversion** (by hand or with `ingress2gateway`). |

## The demo app

```
 your laptop                         minikube
 curl --connect-to                 ┌ envoy-gateway-system ────────────┐   ┌ example-namespace ─────────────────────┐
 host:80:<minikube-ip>:<nodePort>─▶│ envoy proxy (one per Gateway)    │──▶│ example-svc :8080 (echo) :50051 (gRPC) │
                                   │  configured by envoy-gateway     │   │ foo-svc               :50051 (gRPC)    │
 grpc-client pod (grpcurl) ───────▶│  from GatewayClass/Gateway/Routes│   │ service1 / service1-canary / service2  │
                                   └──────────────────────────────────┘   │                       :80 (echo)       │
                                                                          └────────────────────────────────────────┘
```

**The docs examples are used verbatim.** `01a`, `02`, `03`, `10a` and `10b` are copied unchanged from the docs page: namespace `example-namespace`, Gateway `example-gateway`, hosts `www.example.com` and `svc.example.com`, and backends `example-svc:8080`, `example-svc:50051` and `foo-svc:50051`. The demo app is built to fit them. The docs HTTPRoute and GRPCRoutes have no `metadata.namespace`, so apply them with `-n example-namespace`.
Every other file is an extra lab for topics the page mentions but gives no YAML for: matching, filters, weighting, cross-namespace, TLS and migration.

The HTTP backends run `echo-basic`, the echo server the Gateway API conformance tests use. It replies with JSON: pod name, host, path and headers. `example-svc` and `foo-svc` pods also run `grpcbin`, a gRPC demo server, on the docs' port 50051.
`./req.sh <host> <path>...` sends requests through the Gateway with that Host header. It prints which **deployment** answered and the **path the backend saw**, or `HTTP 404`, `HTTP 301 -> <location>` and so on.
Options: `H='name: value'` adds a header, `X=DELETE` sets the method, `SCHEME=https`, and `RAW=1` shows the full response with headers.
`./grpc.sh <host> <method|list>` runs grpcurl from the `grpc-client` pod against the Gateway. `PROTO=1` uses the bundled `login.proto` for the docs' `com.example/Login`.

---

## Step 0 – Install the Gateway API CRDs + an implementation

```bash
export EG_VERSION=v1.10.0     # Envoy Gateway release; check https://github.com/envoyproxy/gateway/releases
kubectl apply --server-side -f https://github.com/envoyproxy/gateway/releases/download/$EG_VERSION/install.yaml
kubectl wait --timeout=5m -n envoy-gateway-system deploy/envoy-gateway --for=condition=Available

kubectl get crd | grep gateway.networking.k8s.io     # gatewayclasses, gateways, httproutes, grpcroutes, referencegrants, ...
kubectl get crd gateways.gateway.networking.k8s.io \
  -o jsonpath='{.metadata.annotations.gateway\.networking\.k8s\.io/bundle-version}{"  "}{.metadata.annotations.gateway\.networking\.k8s\.io/channel}{"\n"}'
kubectl api-resources --api-group=gateway.networking.k8s.io
```
The CRDs alone do nothing, in the same way an Ingress without a controller does nothing. `envoy-gateway` is the controller.
Installing only the CRDs, with no implementation, is `kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/<version>/standard-install.yaml`.

## Step 1 – Deploy the app
```bash
cd concepts/services-networking/gateway-api
kubectl apply -f 00-demo-app.yaml
kubectl wait --for=condition=Available deploy --all -n example-namespace --timeout=180s
```
**Convention:** from Lab 4 on, run `./cleanup.sh routes` before each lab (unless a lab says otherwise) so earlier routes don't overlap with the current one. The Gateway is kept.

## Lab 1 – GatewayClass
```bash
First apply the docs' class exactly as written:
```bash
kubectl apply -f 01a-gatewayclass.yaml
kubectl get gatewayclass                          # example-class  example.com/gateway-controller  ACCEPTED Unknown
kubectl describe gatewayclass example-class       # Reason: Pending / "Waiting for controller"
```
`example.com/gateway-controller` is a placeholder. No controller claims it, so nothing ever sets its status, and Gateways of this class would never get an address. The **controllerName** is the only value that changes per implementation, and it's immutable, so replace the class:
```bash
kubectl delete -f 01a-gatewayclass.yaml
kubectl apply  -f 01b-gatewayclass-envoy.yaml     # same name, controllerName gateway.envoyproxy.io/gatewayclass-controller
kubectl get gatewayclass                          # ACCEPTED True
kubectl describe gatewayclass example-class       # Conditions: Accepted / SupportedVersion
```

## Lab 2 – Gateway
```bash
kubectl apply -f 02-gateway.yaml
kubectl get gateway -n example-namespace -w            # wait for PROGRAMMED True (ADDRESS may stay empty without minikube tunnel)
kubectl describe gateway example-gateway -n example-namespace     # Listeners: http, Attached Routes: 0
```
See what the controller built for this Gateway:
```bash
kubectl get deploy,svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=example-gateway
```
You get one Envoy Deployment and one `LoadBalancer` Service per Gateway. That is the "instance of traffic handling infrastructure".
On minikube the LoadBalancer stays `<pending>` unless `minikube tunnel` runs. `req.sh` uses the Service's **NodePort** instead, so the tunnel is optional. To use the tunnel instead, run `minikube tunnel` in another terminal, then:
`export GATEWAY_IP=$(kubectl get gateway example-gateway -n example-namespace -o jsonpath='{.status.addresses[0].value}')`.
```bash
./req.sh www.example.com /                        # HTTP 404 - listener exists, but no routes yet
```

## Lab 3 – HTTPRoute (the docs example)
```bash
kubectl apply -f 03-httproute.yaml -n example-namespace   # docs YAML has no namespace
kubectl get httproute -n example-namespace             # HOSTNAMES www.example.com
./req.sh www.example.com /login /login/form /loginx /
./req.sh other.example.com /login
```
Expected:
```
www.example.com    /login        -> example-svc  (backend saw /login)
www.example.com    /login/form   -> example-svc  (PathPrefix matches sub-paths)
www.example.com    /loginx       -> HTTP 404     (prefix matches whole path elements)
www.example.com    /             -> HTTP 404     (no rule)
other.example.com  /login        -> HTTP 404     (listener hostname is www.example.com)
```
Look at the status the controller wrote:
```bash
kubectl get httproute example-httproute -n example-namespace -o jsonpath='{range .status.parents[*].conditions[*]}{.type}={.status} ({.reason}){"\n"}{end}'
# Accepted=True (Accepted)   ResolvedRefs=True (ResolvedRefs)
kubectl describe gateway example-gateway -n example-namespace | grep -i 'attached routes'   # 1
```

## Lab 4 – Matching: path, header, query, method
```bash
./cleanup.sh routes
kubectl apply -f 04-gateway-open.yaml             # listener without hostname: routes decide hosts now
kubectl apply -f 04-matching.yaml
./req.sh match.example.com /foo /foo/ /foo/bar /foobar /users/42 /users/abc
H='env: canary' ./req.sh match.example.com / /anything /foo
./req.sh match.example.com '/?version=2' '/?version=3'
X=DELETE ./req.sh match.example.com /
```
Expected:

| Request | Backend | Why |
|---|---|---|
| `/foo` | service2 | **Exact** beats PathPrefix |
| `/foo/`, `/foo/bar` | service1 | PathPrefix `/foo` |
| `/foobar` | example-svc | Not an element-wise prefix, so it falls to the catch-all |
| `/users/42` | example-svc (rule E) | RegularExpression (Extended support) |
| `env: canary` + `/`, `/anything` | service1-canary | Header match on prefix `/` |
| `env: canary` + `/foo` | service2 | Path precedence is checked **before** header count |
| `?version=2` | service2 | Query param match |
| `?version=3` | example-svc | Catch-all |
| `DELETE /` | service2 | Method match. Rule D has two `matches` entries, which are **OR**ed |

Experiment: add a second header to rule C's match. Every condition inside one match must then be true (**AND**).

## Lab 5 – Filters (modify requests and responses)
```bash
./cleanup.sh routes
kubectl apply -f 05-filters.yaml
RAW=1 H='x-secret: hunter2' ./req.sh filters.example.com /headers | grep -iE 'x-served-by|X-Lab|User-Agent|X-Secret'
./req.sh filters.example.com /api/v1/orders /api/v1
./req.sh filters.example.com /old /old/page
./req.sh filters.example.com /mirror
kubectl logs -n example-namespace deploy/service2 --tail=3       # the mirrored copy arrived here too
```
Expected:
- `/headers`: the response has `x-served-by: example-gateway`. The backend's JSON shows `X-Lab: gateway-api` and `User-Agent: rewritten-by-gateway`, and **no** `X-Secret`.
- `/api/v1/orders` → service2 sees `/orders`. `ReplacePrefixMatch` is the portable version of the nginx `rewrite-target` annotation.
- `/old`, `/old/page` → `HTTP 301 -> https://www.example.com/new`. No backend is involved.
- `/mirror` → service1 answers. service2 gets a copy, and its response is thrown away.

## Lab 6 – Traffic splitting (canary)
```bash
./cleanup.sh routes
kubectl apply -f 06-traffic-split.yaml
for i in $(seq 20); do ./req.sh canary.example.com /; done | awk '{print $5}' | sort | uniq -c
```
Expected: about 16 × `service1` and 4 × `service1-canary`. Edit the weights to `50/50`, then `0/100`, and re-apply. The traffic shifts with **no** extra objects and no annotations.

## Lab 7 – Cross-namespace routes, allowedRoutes and ReferenceGrant
A team in namespace `team-a` wants to use the shared Gateway in `example-namespace` and the Service `service1` there.
```bash
./cleanup.sh routes
kubectl apply -f 04-gateway-open.yaml             # from: Same
kubectl apply -f 07a-other-namespace-route.yaml
kubectl get httproute team-a-route -n team-a -o jsonpath='{range .status.parents[*].conditions[*]}{.type}={.status} ({.reason}){"\n"}{end}'
./req.sh team-a.example.com /                     # HTTP 404
```
Expected: `Accepted=False (NotAllowedByListeners)`. **The Gateway doesn't trust namespace `team-a`.**

Step 2: the cluster operator allows namespaces labelled `shared-gateway-access=true`.
```bash
kubectl apply -f 07b-gateway-allow-selector.yaml
kubectl get httproute team-a-route -n team-a -o jsonpath='{range .status.parents[*].conditions[*]}{.type}={.status} ({.reason}){"\n"}{end}'
./req.sh team-a.example.com /
```
Expected: `Accepted=True`, but `ResolvedRefs=False (RefNotPermitted)`. The route may attach, but it may not point at a Service in another namespace, so the request fails with HTTP 500.

Step 3: the owner of `example-namespace` grants the reference.
```bash
kubectl apply -f 07c-referencegrant.yaml
./req.sh team-a.example.com /                     # service1
```
Remove the label (`kubectl label ns team-a shared-gateway-access-`). The route becomes NotAllowedByListeners again. Both sides must agree.
```bash
kubectl apply -f 04-gateway-open.yaml              # restore from: Same
```

## Lab 8 – Multiple listeners, sectionName and hostname intersection
```bash
./cleanup.sh routes
kubectl apply -f 08-listeners-hostnames.yaml
kubectl describe gateway example-gateway -n example-namespace | grep -A3 -E 'Name: +(http|wildcard)$'
./req.sh shop.apps.example.com /                  # service2
./req.sh a.b.apps.example.com /                   # 404 - route hostnames don't include it
./req.sh foo.other.com /                          # 404 - outside the listener's *.apps.example.com
```
The route is attached only to the `wildcard` listener (`sectionName`). The hostnames it actually serves are the **intersection** of the listener hostname and the route's `hostnames`.
Note: a Gateway API wildcard (`*.apps.example.com`) matches **one or more** labels. An Ingress wildcard matches exactly one.
```bash
kubectl apply -f 04-gateway-open.yaml             # back to a single listener
```

## Lab 9 – HTTPS listener (TLS termination) + HTTP→HTTPS redirect
```bash
./cleanup.sh routes
openssl req -x509 -nodes -days 30 -newkey rsa:2048 \
  -keyout /tmp/gw-tls.key -out /tmp/gw-tls.crt \
  -subj "/CN=secure.example.com" -addext "subjectAltName=DNS:secure.example.com"
kubectl create secret tls secure-example-tls -n example-namespace --cert=/tmp/gw-tls.crt --key=/tmp/gw-tls.key
kubectl apply -f 09-https-gateway.yaml
kubectl get gateway example-gateway -n example-namespace -o jsonpath='{range .status.listeners[*]}{.name}: {range .conditions[*]}{.type}={.status} {end}{"\n"}{end}'
SCHEME=https ./req.sh secure.example.com / /x     # service1
./req.sh secure.example.com /x                    # HTTP 301 -> https://secure.example.com/x
```
Check the certificate the Gateway presents. SNI selects it:
```bash
PORT443=$(kubectl get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=example-gateway \
  -o jsonpath='{.items[0].spec.ports[?(@.port==443)].nodePort}')
curl -kv --connect-to secure.example.com:443:$(minikube ip):$PORT443 https://secure.example.com/ 2>&1 | grep -E 'subject:|issuer:'
```
Try deleting the Secret. The `https` listener becomes `ResolvedRefs=False (InvalidCertificateRef)` and `Programmed=False`.
TLS settings belong to the **Gateway** (the operator), not the route (the developer). Compare this with Ingress, where `spec.tls` sits in the same object as the routing rules.
The `TLS` protocol (passthrough plus TLSRoute) and `BackendTLSPolicy` (re-encrypting to the pod) are covered in the TLS guide linked from the docs.
```bash
kubectl apply -f 04-gateway-open.yaml ; kubectl delete secret secure-example-tls -n example-namespace
```

## Lab 10 – GRPCRoute
```bash
./cleanup.sh routes
kubectl apply -f 04-gateway-open.yaml             # the docs Gateway only listens for www.example.com
kubectl apply -f 10a-grpcroute.yaml -n example-namespace
kubectl get grpcroute -n example-namespace
./grpc.sh svc.example.com list                            # grpcbin.GRPCBin, grpc.reflection...
./grpc.sh svc.example.com grpcbin.GRPCBin/Index           # {"description": "gRPC testing server", ...}
PROTO=1 ./grpc.sh svc.example.com com.example/Login       # reaches example-svc: "unknown service com.example"
./grpc.sh other.example.com list                          # fails - no GRPCRoute for this authority
```
Why `/com.example/Login` gives that error: the docs' method doesn't exist in grpcbin, so the **backend** answers `Unimplemented: unknown service com.example`. Getting that error proves the gateway routed the call.

Now apply the docs' method-match route. It has the same name, so it replaces 10a. Only `com.example` / `Login` goes through, to `foo-svc`:
```bash
kubectl apply -f 10b-grpcroute-method.yaml -n example-namespace
PROTO=1 ./grpc.sh svc.example.com com.example/Login       # "unknown service com.example" from foo-svc -> routed
./grpc.sh svc.example.com grpcbin.GRPCBin/Index           # fails: reflection call has no route (HTTP 404 from the gateway)
kubectl logs -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=example-gateway -c envoy --tail=3
```
The Envoy access log shows `/com.example/Login` with status 200 (grpc-status 12), and the reflection call with a 404 and no upstream. **The match is on the gRPC service and method, which form the HTTP/2 path `/<service>/<method>`.**
The `appProtocol: kubernetes.io/h2c` on port 50051 (see `00-demo-app.yaml`) tells the Gateway to use HTTP/2 cleartext to the pod.

## Lab 11 – Migrating from Ingress
Read [11a-ingress-equivalent.yaml](11a-ingress-equivalent.yaml), which is not applied, next to [11b-migrated.yaml](11b-migrated.yaml).
```bash
./cleanup.sh routes
kubectl apply -f 11b-migrated.yaml
./req.sh legacy.example.com /app /app/x /other
```
Expected: `/app` → service1 sees `/`, and `/app/x` → service1 sees `/x`. `/other` → 404.

| Ingress | Gateway API |
|---|---|
| IngressClass | GatewayClass |
| Implicit LB owned by the controller | Explicit **Gateway** + listeners |
| `spec.rules` (host/path) | **HTTPRoute** `hostnames` + `rules.matches` |
| `spec.tls` | HTTPS listener + `certificateRefs` on the Gateway |
| Annotations (rewrite, canary, headers…) | Filters, weights, header/query/method matches |
| Same namespace only | `allowedRoutes` + **ReferenceGrant** |

The tool `ingress2gateway` (kubernetes-sigs) converts existing Ingresses automatically: `ingress2gateway print --providers ingress-nginx -A`.

## Lab 12 – Debugging with status
```bash
./cleanup.sh routes
kubectl apply -f 12-broken-route.yaml
kubectl get httproute broken -n example-namespace -o yaml | sed -n '/^status:/,$p'
./req.sh broken.example.com /                     # HTTP 500 - route attached, but backend missing
```
Expected: one `parents[]` entry for `example-gateway`, with `Accepted=True` and `ResolvedRefs=False (BackendNotFound)`. There is **no** entry for `no-such-gateway`, because no controller owns it and so nobody reports on it.
Checklist when a route "does nothing":
1. `kubectl get gatewayclass`: is it Accepted? Does `controllerName` match the controller you installed?
2. `kubectl get gateway`: is it Programmed? What do the listener conditions say? How many routes are attached?
3. Route `status.parents`: Accepted (allowedRoutes, hostname intersection, sectionName)? ResolvedRefs (Service name/port, ReferenceGrant)?
4. Controller logs: `kubectl logs -n envoy-gateway-system deploy/envoy-gateway --tail=50`.

---

## Useful commands
```bash
kubectl get gatewayclass,gateway,httproute,grpcroute,referencegrant -A
kubectl describe gateway <name> -n example-namespace     # listeners, addresses, attached routes, conditions
kubectl explain httproute.spec.rules.matches
kubectl explain gateway.spec.listeners.allowedRoutes
kubectl get svc,deploy -n envoy-gateway-system      # the proxies the controller created
kubectl logs -n envoy-gateway-system deploy/envoy-gateway --tail=20
```

## Cleanup
```bash
./cleanup.sh routes   # remove routes, ReferenceGrants, team-a (keep Gateway + app)
./cleanup.sh all      # delete example-namespace, team-a and the lab GatewayClasses
./cleanup.sh envoy    # also uninstall Envoy Gateway and the Gateway API CRDs
rm -f /tmp/gw-tls.key /tmp/gw-tls.crt
```

## What's next (from the docs)
- Installing Gateway API: https://gateway-api.sigs.k8s.io/guides/#installing-gateway-api
- Implementations: https://gateway-api.sigs.k8s.io/implementations/
- TLS guide: https://gateway-api.sigs.k8s.io/guides/tls/
- Migrating from Ingress: https://gateway-api.sigs.k8s.io/guides/getting-started/migrating-from-ingress
- API spec: https://gateway-api.sigs.k8s.io/reference/api-spec/main/spec/
