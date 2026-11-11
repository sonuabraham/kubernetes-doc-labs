# Kubernetes Ingress – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/services-networking/ingress/

> **Heads-up from the docs:** the Ingress API is **frozen**. It is GA (stable since v1.19) and won't be removed, but it gets no new features. The Kubernetes project recommends **Gateway API** for new work.
> The minikube addon used here runs **ingress-nginx**. SIG Network retired that controller in March 2026, so it gets no more fixes. It's fine for learning, but choose a maintained controller or Gateway API for real clusters. The Ingress concepts below are the same for every controller.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Ingress** | HTTP(S) routing rules (host + path → Service) for traffic coming from outside the cluster. Layer 7 only, so no arbitrary TCP/UDP. Use NodePort or LoadBalancer for those. |
| **Ingress controller** | The proxy that actually implements the rules (nginx, Traefik, HAProxy, cloud LBs…). **Without a controller an Ingress does nothing.** |
| **IngressClass** | A cluster-scoped object that names a controller (`spec.controller`) plus optional `parameters`. Ingresses select one with `spec.ingressClassName`. |
| **Default class** | An IngressClass annotated `ingressclass.kubernetes.io/is-default-class: "true"` is filled in for Ingresses without `ingressClassName`. Keep at most **one** default. |
| `kubernetes.io/ingress.class` | The old annotation from before v1.18. Deprecated; use `ingressClassName`. |
| **Rule** | Optional `host` + a list of `paths`. Each path has a `pathType` and a `backend`. Host **and** path must match. |
| `pathType` | **Required.** `Exact` (exact and case-sensitive), `Prefix` (prefix by `/`-separated element: `/foo` matches `/foo/x` but not `/foobar`), `ImplementationSpecific` (the controller decides). |
| **Precedence** | Longest matching path wins. On a tie, `Exact` beats `Prefix`. |
| **Host wildcard** | `*.foo.com` matches exactly **one** extra label: `bar.foo.com` yes; `baz.bar.foo.com` and `foo.com` no. |
| `defaultBackend` | Receives requests that match no rule. Required if `rules` is empty. Usually configured on the controller instead. |
| **Backend** | A `service` (name + port number **or** port name) or a `resource` (a reference to a custom object). They are mutually exclusive. |
| **TLS** | `spec.tls[].hosts` + `secretName` (a `kubernetes.io/tls` Secret with `tls.crt` and `tls.key`). TLS ends at the controller on port 443; traffic to the pods is plain HTTP. |
| **Same namespace** | Backend Services and TLS Secrets must be in the Ingress's namespace. |

## The demo app

```
 your laptop                minikube node
 curl --resolve             ┌───────────────────────────── ingress-demo ns ─┐
 foo.bar.com:80:<ip>  ───▶  │ ingress-nginx controller ──▶ service1 (80,4200) │
                            │   reads all Ingress      ──▶ service2 (80,8080) │
                            │   objects and routes     ──▶ service3 (80)      │
                            │   by Host + path         ──▶ test     (80)      │
                            └────────────────────────────────────────────────┘
```

Every backend is `http-echo` and answers `hello from <name>` for **any** path, so you can see where each request went.
`./req.sh <host> <path>...` sends requests to the controller with that `Host` header (using `curl --resolve`, so no `/etc/hosts` editing).
It prints the response body, or `HTTP 404` and similar on errors.

---

## Step 0 – Install an Ingress controller

```bash
minikube addons enable ingress
kubectl get pods -n ingress-nginx -w            # wait for ingress-nginx-controller Running
kubectl get ingressclass                        # -> nginx  (controller k8s.io/ingress-nginx)
kubectl get ingressclass nginx -o yaml | grep is-default-class   # is it the default?
```
On Linux with the docker driver, `minikube ip` can be reached directly. If it can't (macOS, Windows), run `minikube tunnel` and use `export INGRESS_IP=127.0.0.1`.

## Step 1 – Deploy the app
```bash
cd ingress
kubectl apply -f 00-demo-app.yaml
kubectl wait --for=condition=Available deploy --all -n ingress-demo --timeout=120s
```
**Convention:** run `./cleanup.sh ingresses` before each lab (except where noted) so earlier rules don't overlap with the current one.

## Lab 1 – Minimal Ingress
```bash
kubectl apply -f 01-minimal-ingress.yaml
kubectl get ingress -n ingress-demo -w          # wait until ADDRESS is filled in
./req.sh - /testpath /testpath/abc /testpathX /
```
Expected:
```
/testpath      -> hello from test
/testpath/abc  -> hello from test      (Prefix matches sub-paths)
/testpathX     -> HTTP 404             (not a path-element prefix)
/              -> HTTP 404             (no rule -> controller's built-in default backend)
```
`kubectl describe ingress minimal-ingress -n ingress-demo` shows the host `*`, the path, and the backend pod IPs.

## Lab 2 – defaultBackend (keep Lab 1 applied)
```bash
kubectl apply -f 02-default-backend.yaml
./req.sh - /testpath /anything /
```
Expected: `/testpath` still goes to `test`. Everything that used to return 404 now goes to `service3`.
An Ingress with only `defaultBackend` and no rules is the "Ingress backed by a single Service" from the docs.

## Lab 3 – Path types and precedence
```bash
./cleanup.sh ingresses
kubectl apply -f 03-path-types.yaml
./req.sh paths.example.com /foo /foo/ /foo/x /foobar /FOO /aaa/bbb /aaa/bbb/ /aaa/bbb/ccc /aaa/bbbxyz /aaa/bb /ccc
```
Expected (compare with the table in the docs):

| Request | Backend | Why |
|---|---|---|
| `/foo` | service1 | Exact and Prefix `/foo` both match the same length → **Exact wins** |
| `/foo/`, `/foo/x` | service2 | Only Prefix `/foo` matches |
| `/foobar` | test | `/foo` isn't an element-wise prefix, so it falls to `/` |
| `/FOO` | test | Matching is case-sensitive |
| `/aaa/bbb`, `/aaa/bbb/`, `/aaa/bbb/ccc` | service3 | Prefix matches the path, a trailing slash, and sub-paths |
| `/aaa/bbbxyz`, `/aaa/bb`, `/ccc` | test | Only `/` matches |

Experiment: remove `pathType:` from one path and apply again. The API server rejects it because `pathType` is required.

## Lab 4 – Hostname wildcards
```bash
./cleanup.sh ingresses
kubectl apply -f 04-wildcard-host.yaml
./req.sh foo.bar.com      /bar        # service1  (exact host)
./req.sh bar.foo.com      /foo        # service2  (*.foo.com, one label)
./req.sh anything.foo.com /foo        # service2
./req.sh baz.bar.foo.com  /foo        # 404 - wildcard covers ONE label only
./req.sh foo.com          /foo        # 404 - the bare domain doesn't match either
./req.sh bar.foo.com      /bar        # 404 - host matches but path doesn't
```

## Lab 5 – Simple fanout (one host, many Services by path)
```bash
./cleanup.sh ingresses
kubectl apply -f 05-simple-fanout.yaml
./req.sh foo.bar.com /foo /foo/api /bar /baz
kubectl describe ingress simple-fanout-example -n ingress-demo
```
Expected: `/foo…` → service1 (port 4200), `/bar` → service2 (port 8080), `/baz` → 404.
`describe` lists `/foo service1:4200 (<pod-ip>:5678)`. The Ingress refers to the **Service port**, and the controller sends traffic straight to the pod endpoints.
Note: the backend receives the **original** path (`/foo/api`). Path rewriting is a controller-specific annotation (e.g. `nginx.ingress.kubernetes.io/rewrite-target`) and isn't part of the Ingress API.

## Lab 6 – Name-based virtual hosting
```bash
./cleanup.sh ingresses
kubectl apply -f 06-name-virtual-host.yaml
./req.sh foo.bar.com /  /x
./req.sh bar.foo.com /  /x
./req.sh other.com   /
./req.sh -           /
```
Expected: same IP, different backend by `Host`: foo.bar.com → service1, bar.foo.com → service2. Unknown hosts and requests to the bare IP get 404.

## Lab 7 – Virtual hosts + a host-less catch-all
```bash
./cleanup.sh ingresses
kubectl apply -f 07-virtual-host-catch-all.yaml
./req.sh first.bar.com /
./req.sh second.bar.com /
./req.sh whatever.example /
./req.sh - /
```
Expected: service1, service2, then **service3** for any other host and for the bare IP. A rule without `host` matches every Host header.

## Lab 8 – TLS
```bash
./cleanup.sh ingresses
# 1. Self-signed cert whose CN/SAN = the host in the rule
openssl req -x509 -nodes -days 30 -newkey rsa:2048 \
  -keyout /tmp/tls.key -out /tmp/tls.crt \
  -subj "/CN=https-example.foo.com" -addext "subjectAltName=DNS:https-example.foo.com"
# 2. Secret of type kubernetes.io/tls (keys tls.crt / tls.key)
kubectl create secret tls testsecret-tls -n ingress-demo --cert=/tmp/tls.crt --key=/tmp/tls.key
kubectl get secret testsecret-tls -n ingress-demo -o yaml | head -8
# 3. Ingress with a tls section
kubectl apply -f 08-tls-ingress.yaml
SCHEME=https ./req.sh https-example.foo.com /
```
Check the certificate the controller presents (SNI picks it):
```bash
curl -kv --resolve https-example.foo.com:443:$(minikube ip) https://https-example.foo.com/ 2>&1 | grep -E 'subject:|issuer:|hello'
curl -sI --resolve https-example.foo.com:80:$(minikube ip) http://https-example.foo.com/ | head -3
```
Expected: `subject: CN=https-example.foo.com`, then the body `hello from service1`. Plain HTTP gets a **308 redirect** to HTTPS. That redirect is ingress-nginx's default behaviour, not part of the Ingress API.
Without SNI, or for another host, the controller serves its own fake certificate. This is why `tls.hosts` has to match the rule's `host`.

## Lab 9 – IngressClass and the default class
```bash
./cleanup.sh ingresses
kubectl get ingressclass                         # nginx (from the addon)
kubectl apply -f 09-ingressclass.yaml
kubectl get ingressclass
kubectl describe ingressclass external-lb-2      # parameters: scope Namespace + namespace
```
Now there may be **two** defaults (`nginx` and `example-class`). Try an Ingress with no class:
```bash
kubectl apply -f 09b-ingress-no-class.yaml
kubectl get ingress no-class -n ingress-demo -o jsonpath='{.spec.ingressClassName}{"\n"}'
```
The docs warn that with more than one default class, the admission controller **rejects** Ingresses that have no `ingressClassName`. Note what your cluster version does: it either rejects the Ingress or assigns a class.
If it was accepted with `example-class`, then `kubectl get ingress no-class -n ingress-demo` never gets an ADDRESS and `./req.sh noclass.example.com /` returns 404. **No controller watches that class, so the Ingress does nothing.**
Fix: keep one default.
```bash
kubectl delete -f 09b-ingress-no-class.yaml --ignore-not-found
kubectl delete -f 09-ingressclass.yaml
```

## Lab 10 – Updating an Ingress
```bash
./cleanup.sh ingresses
kubectl apply -f 10a-update-before.yaml
./req.sh foo.bar.com /foo ; ./req.sh bar.baz.com /foo      # service1 ; 404
kubectl replace -f 10b-update-after.yaml       # or: kubectl edit ingress test -n ingress-demo
kubectl describe ingress test -n ingress-demo  # both hosts listed; Events show "Sync"
./req.sh foo.bar.com /foo ; ./req.sh bar.baz.com /foo      # service1 ; service2
```
The API server stores the change, the controller sees it, and it reloads its proxy config. There's no downtime and the IP doesn't change.

## Lab 11 – Resource backend (read-only)
```bash
kubectl apply -f 11-resource-backend.yaml
kubectl describe ingress ingress-resource-backend -n ingress-demo
kubectl delete -f 11-resource-backend.yaml
```
`describe` shows `Default backend: APIGroup: k8s.example.com, Kind: StorageBucket, Name: static-assets`. A backend can reference a custom object, such as an object-storage bucket, if your controller supports it.

---

## Load balancing, health checks, multiple zones (from the docs)
- The **controller** decides the LB algorithm and weights for all Ingresses. The Ingress API has no fields for them. Session affinity and similar settings are controller annotations or Service settings.
- There is no health-check field. The controller sends traffic only to **Ready** endpoints, so readiness probes do that job. Try `kubectl scale deploy service1 -n ingress-demo --replicas=0` and the route returns 503.
- Spreading across availability zones depends on the cloud provider and controller.
- **Alternatives** for exposing a single Service: `type: LoadBalancer` or `type: NodePort` (see `../service`).

## Useful commands
```bash
kubectl get ingress -n ingress-demo               # short name: ing
kubectl describe ingress <name> -n ingress-demo   # rules, backends, events
kubectl get ingressclass
kubectl explain ingress.spec.rules.http.paths
kubectl logs -n ingress-nginx deploy/ingress-nginx-controller --tail=20   # access log
kubectl create ingress quick -n ingress-demo --class=nginx \
  --rule="quick.example.com/*=service1:80"        # imperative; /* means Prefix
```

## Cleanup
```bash
./cleanup.sh ingresses   # remove all Ingresses (keep the app)
./cleanup.sh all         # delete the namespace + lab IngressClasses
minikube addons disable ingress
rm -f /tmp/tls.key /tmp/tls.crt
```
