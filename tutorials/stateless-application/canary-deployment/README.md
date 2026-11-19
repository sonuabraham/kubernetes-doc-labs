# Deploy a Release Using a Canary Deployment – Hands-on Lab

Based on: https://kubernetes.io/docs/tutorials/stateless-application/canary-deployment/

> Runs on the default **minikube**, namespace `default`. Files, **verbatim** from the docs:
> - `app-v1-deployment.yaml`, `app-v2-deployment.yaml`, `app-service.yaml` (`examples/application/canary/`)
> - the page's inline YAML: [track-services.yaml](track-services.yaml), [httproute-weighted.yaml](httproute-weighted.yaml),
>   [httproute-header.yaml](httproute-header.yaml)
>
> **Found:**
> - **The responses don't show "v1".** The page says "all responses should show version v1", but `hello-app` prints its *built-in*
>   version: `Version: 1.0.0` / `Version: 2.0.0`. The `VERSION` env variable in the manifests isn't used by the app.
> - **"Completing the rollout" makes two rollouts.** `kubectl set image` and then `kubectl set env` each change the Pod template, giving
>   revisions 2 **and** 3. The in-between ReplicaSet runs `hello-app:2.0` with `VERSION=v1`. Use `kubectl rollout pause` / `resume` around
>   both commands (or one `kubectl apply`) if that matters.
> - The `kubectl scale deployment/rollout-demo-stable --replicas=3` before the image update is a no-op here: stable was never scaled down.
> - The HTTPRoute part needs the Gateway API CRDs and a controller. minikube has neither:
>   `no matches for kind "HTTPRoute" in version "gateway.networking.k8s.io/v1" … ensure CRDs are installed first`. Installing external
>   manifests wasn't permitted in this environment (see [concepts/services-networking/gateway-api](../../../concepts/services-networking/gateway-api/)).
>   The two per-track Services from that section work on their own.
>
> **Note:** `kubectl run curl-test … --rm -it` prints nothing when the output isn't a terminal (as in this lab's shell). The same `curl` loops
> run here through `kubectl exec` in a long-running `curl-client` Pod (NOT from the docs). In a terminal, the docs' commands work as written.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| Two Deployments | `rollout-demo-stable` (`track: stable`, hello-app 1.0, 3 replicas) and `rollout-demo-canary` (`track: canary`, 2.0, 1 replica) |
| One Service | selects only `app.kubernetes.io/name: rollout-demo` → endpoints from **both** → traffic share ≈ replica share |
| Shifting traffic | change replica counts (coarse); exact weights need something like Gateway API `HTTPRoute` |
| Promote | update the stable Deployment to the new image, delete the canary |
| Roll back | canary to 0 replicas (kept for inspection), stable back to full size |

## Lab 1 – Stable version + Service
```bash
kubectl apply -f app-v1-deployment.yaml
kubectl get deployments -l app.kubernetes.io/name=rollout-demo      # rollout-demo-stable   3/3   3   3
kubectl get pods -l app.kubernetes.io/name=rollout-demo             # 3 × rollout-demo-stable-847999db9b-…  Running
kubectl apply -f app-service.yaml
kubectl get service rollout-demo-service                            # ClusterIP 10.106.209.231   80/TCP
kubectl run curl-test --image=curlimages/curl:latest --rm -it --restart=Never -- curl http://rollout-demo-service
#   Hello, world!
#   Version: 1.0.0
#   Hostname: rollout-demo-stable-847999db9b-f2fhm
```
Here (NOT from the docs): `kubectl run curl-client --image=curlimages/curl:latest --restart=Never --command -- sleep 3600`, then
`kubectl exec curl-client -- curl -s http://rollout-demo-service`.

## Lab 2 – Canary
```bash
kubectl apply -f app-v2-deployment.yaml
kubectl get deployments -l app.kubernetes.io/name=rollout-demo      # canary 1/1, stable 3/3
kubectl get pods -l app.kubernetes.io/name=rollout-demo -o wide     # 4 Pods, all on node minikube
kubectl run curl-test --image=curlimages/curl:latest --rm -it --restart=Never -- \
  sh -c 'for i in $(seq 1 10); do curl -s http://rollout-demo-service; echo; done'
#   7 × Version: 1.0.0   3 × Version: 2.0.0
#   (200 requests: 146 × 1.0.0, 54 × 2.0.0 = 27 % canary, expected 25 %)
kubectl get endpointslices -l kubernetes.io/service-name=rollout-demo-service
#   rollout-demo-service-xkjw6   IPv4   8080   10.244.0.9,10.244.0.11,10.244.0.10 + 1 more...
kubectl logs -l app.kubernetes.io/name=rollout-demo,track=canary --tail=50     # 2026/11/19 10:31:56 Serving request: /
kubectl get pods -l app.kubernetes.io/name=rollout-demo -w                     # Ctrl+C
kubectl top pods -l app.kubernetes.io/name=rollout-demo
#   stable Pods ~2m CPU, 2-4Mi  (a brand-new canary Pod isn't listed until metrics-server has scraped it)

kubectl scale deployment/rollout-demo-canary --replicas=2
kubectl get pods -l app.kubernetes.io/name=rollout-demo             # 5 Pods
#   200 requests: 120 × 1.0.0, 80 × 2.0.0 = 40 %
```

## Lab 3 – Complete the rollout
```bash
kubectl scale deployment/rollout-demo-stable --replicas=3
kubectl set image deployment/rollout-demo-stable rollout-demo=gcr.io/google-samples/hello-app:2.0
kubectl set env deployment/rollout-demo-stable VERSION=v2
kubectl rollout status deployment/rollout-demo-stable               # deployment "rollout-demo-stable" successfully rolled out
kubectl delete deployment rollout-demo-canary
kubectl rollout history deployment/rollout-demo-stable              # REVISION 1, 2, 3   <- two rollouts, see "Found"
kubectl get rs -l track=stable
#   rollout-demo-stable-657b4df6bf   0  …   (2.0 + VERSION=v1, the in-between one)
#   rollout-demo-stable-79dfdf8bdd   3  …   (2.0 + VERSION=v2)
#   rollout-demo-stable-847999db9b   0  …   (1.0)
#   50 requests → 50 × Version: 2.0.0
```

## Lab 4 – Roll back a canary (fresh start: stable v1 + canary v2)
```bash
kubectl delete deployment rollout-demo-stable
kubectl apply -f app-v1-deployment.yaml -f app-v2-deployment.yaml
kubectl scale deployment/rollout-demo-canary --replicas=0
kubectl scale deployment/rollout-demo-stable --replicas=3
kubectl get deploy -l app.kubernetes.io/name=rollout-demo           # canary 0/0 (kept), stable 3/3
#   50 requests → 50 × Version: 1.0.0
```

## Lab 5 – Per-track Services and HTTPRoute (optional section)
```bash
kubectl apply -f track-services.yaml
#   service/rollout-demo-stable-service created / service/rollout-demo-canary-service created
# (curl loops from curl-client)
#   rollout-demo-stable-service → only Version: 1.0.0
#   rollout-demo-canary-service → only Version: 2.0.0          <- handy for testing one version directly
kubectl apply -f httproute-weighted.yaml
#   error: resource mapping not found … no matches for kind "HTTPRoute" in version "gateway.networking.k8s.io/v1"
#   ensure CRDs are installed first
```
With Gateway API installed (and a Gateway `example-gateway`), `httproute-weighted.yaml` gives a fixed 90/10 split regardless of replicas,
and `httproute-header.yaml` sends requests with header `env: canary` to the canary only.

## Cleanup
```bash
./cleanup.sh      # docs: delete both Deployments, the Services (+ HTTPRoute); plus curl-client
```
