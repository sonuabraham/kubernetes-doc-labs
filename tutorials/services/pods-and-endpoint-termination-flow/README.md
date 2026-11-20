# Explore Termination Behavior for Pods And Their Endpoints – Hands-on Lab

Based on: https://kubernetes.io/docs/tutorials/services/pods-and-endpoint-termination-flow/

> Runs on the default **minikube**. [explore-graceful-termination-nginx.yaml](explore-graceful-termination-nginx.yaml) and
> [pod-with-graceful-termination.yaml](pod-with-graceful-termination.yaml) are the docs examples **verbatim**.
>
> **Found:**
> - **The docs' Deployment can't be created.** Its preStop hook says `sleep: 180`:
>   `Deployment in version "v1" cannot be handled as a Deployment: json: cannot unmarshal number into Go struct field
>   LifecycleHandler.spec.template.spec.containers.lifecycle.preStop.sleep of type v1.SleepAction`. The sleep action is an object
>   (`sleep: {seconds: N}`). Written that way, 180 is still rejected:
>   `preStop.sleep: Invalid value: 180: must be non-negative and less than terminationGracePeriodSeconds (120)`.
>   [pod-with-graceful-termination-fixed.yaml](pod-with-graceful-termination-fixed.yaml) (NOT from the docs) uses `sleep: {seconds: 119}`,
>   the closest to the comment's intent ("hang around for the duration of terminationGracePeriodSeconds").
> - The page says "validate that there is one endpoint registered" but its sample `kubectl get endpointslice` output shows two
>   addresses. With 1 replica there is one (`10.244.0.33`).
> - The page has no cleanup. With a 120 s grace period, deleting the Deployment leaves the Pod `Terminating` for ~2 min.

## Key ideas (read first)

| Endpoint condition | Meaning |
|---|---|
| `ready` | may receive normal traffic; **always `false` while terminating** (backward compatibility) |
| `serving` | the Pod's readiness, also during termination; use it to drain connections |
| `terminating` | the Pod has a deletion timestamp |
| Lifetime | a terminating Pod's endpoint stays in the EndpointSlice until the Pod object is gone (preStop + grace period) |

## Lab
```bash
kubectl apply -f pod-with-graceful-termination.yaml        # rejected, see "Found"
kubectl apply -f pod-with-graceful-termination-fixed.yaml  # deployment.apps/nginx-deployment created
kubectl apply -f explore-graceful-termination-nginx.yaml   # service/nginx-service created
kubectl get endpointslice
#   nginx-service-kdf8p   IPv4   80   10.244.0.33   19s
kubectl get endpointslices -o json -l kubernetes.io/service-name=nginx-service
#   10.244.0.33  conditions: ready true, serving true, terminating false   (nginx-deployment-5565b85d49-kxpc9)
kubectl delete pod nginx-deployment-5565b85d49-kxpc9       # (add --wait=false, or it blocks ~2 min)
kubectl get pods
#   nginx-deployment-5565b85d49-dzfz9   1/1   Running       0   3s
#   nginx-deployment-5565b85d49-kxpc9   1/1   Terminating   0   14s
kubectl get endpointslice -o json nginx-service-kdf8p
#   +3 s:   kxpc9 10.244.0.33  ready false, serving true,  terminating true      <- old Pod, still serving while draining
#           dzfz9 10.244.0.34  ready true,  serving true,  terminating false     <- replacement
#   +128 s: only dzfz9 left    (old Pod removed after the 119 s preStop sleep, within the 120 s grace period; sampled every 10 s)
```

## Cleanup
```bash
./cleanup.sh      # Deployment (orphaning), the nginx Pod with --grace-period=1, Service  (the page has no cleanup)
```
