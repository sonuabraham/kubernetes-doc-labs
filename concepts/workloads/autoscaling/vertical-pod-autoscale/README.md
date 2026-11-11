# Vertical Pod Autoscaling – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/workloads/autoscaling/vertical-pod-autoscale/

> ⚠️ **VPA is an add-on.** It isn't part of Kubernetes: the CRD and three components come from the kubernetes/autoscaler project. Installing it means running external code, so it was **not installed or run** while writing this lab. Without it you get exactly the error in Step 1. Everything below is the documented flow, using the docs' manifests verbatim.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **VPA** | "Rightsizing": adjusts a workload's **requests/limits** to actual usage, up or down. Horizontal scaling adds Pods instead. |
| **API** | CRD `VerticalPodAutoscaler`, `autoscaling.k8s.io/v1`, with `targetRef` → Deployment/StatefulSet/… |
| **Recommender** | Watches usage history, peaks and OOMs. Writes `status.recommendation`: **target**, **lowerBound**, **upperBound** per container. |
| **Updater** | Applies recommendations to running Pods: evict, or resize in place. |
| **Admission controller** | Mutating webhook that writes the target into **new** Pods' requests. |
| **Needs** | metrics-server (`metrics.k8s.io`). |
| **updateMode** | `Off` (recommend only), `Initial` (only at Pod creation), `Recreate` (evict when far off), `InPlaceOrRecreate` (resize in place, evict if impossible), `InPlace` (alpha in VPA 1.7: resize in place, **never** evict, retry later). |
| **resourcePolicy** | Per container: `minAllowed`, `maxAllowed`, `controlledResources`, `controlledValues` (`RequestsAndLimits` keeps the ratio, `RequestsOnly`). |
| **With HPA** | Don't let both act on the **same** metric (CPU/memory). VPA on memory plus HPA on custom metrics is fine. |

## The demo app
The docs manifests are **verbatim**: [vpa-recreate.yaml](vpa-recreate.yaml), [vpa-inplace.yaml](vpa-inplace.yaml), [vpa-resource-policy.yaml](vpa-resource-policy.yaml) (all `my-app-vpa` → Deployment `my-app`).
[00-my-app.yaml](00-my-app.yaml) is the target they need: Deployment **`my-app`**, container **`application`**, with deliberately bad requests (CPU 50m while it uses ~300m, memory 512Mi while it uses a few MiB).

---

## Step 1 – Without VPA installed
```bash
cd concepts/workloads/autoscaling/vertical-pod-autoscale
minikube addons enable metrics-server
kubectl apply -f 00-my-app.yaml
kubectl apply -f vpa-recreate.yaml -n vpa-demo
#   error: resource mapping not found ... no matches for kind "VerticalPodAutoscaler" in version "autoscaling.k8s.io/v1"
kubectl top pods -n vpa-demo        # ~300m CPU each - far above the 50m request
```

## Step 2 – Install VPA (you run this; external code)
```bash
git clone --depth 1 https://github.com/kubernetes/autoscaler.git
cd autoscaler/vertical-pod-autoscaler && ./hack/vpa-up.sh && cd -
kubectl get pods -n kube-system | grep vpa         # vpa-recommender, vpa-updater, vpa-admission-controller
kubectl api-resources | grep verticalpodautoscaler
```

## Lab 1 – Recommendations only (updateMode Off)
```bash
sed 's/updateMode: "Recreate".*/updateMode: "Off"/' vpa-recreate.yaml | kubectl apply -n vpa-demo -f -
sleep 120
kubectl get vpa my-app-vpa -n vpa-demo
kubectl get vpa my-app-vpa -n vpa-demo -o jsonpath='{.status.recommendation.containerRecommendations}' | jq .
```
Expected (shape): for `application`, a **target** CPU near the real usage (~300m+) and a target memory far **below** 512Mi, plus lowerBound/upperBound. Nothing changes in the pods.

## Lab 2 – Recreate: the updater evicts, the webhook rewrites
```bash
kubectl apply -f vpa-recreate.yaml -n vpa-demo
kubectl get pods -n vpa-demo -w            # pods are evicted one at a time (respecting PDBs)
kubectl get pod -n vpa-demo -l app=my-app -o jsonpath='{.items[0].spec.containers[0].resources}' ; echo
#   new pods carry the recommended requests; annotation vpaUpdates: "Pod resources updated by my-app-vpa: container 0: cpu request, memory request"
```

## Lab 3 – Bounds and controlled values
```bash
kubectl apply -f vpa-resource-policy.yaml -n vpa-demo
```
Recommendations are now clamped to 100m–2 CPU and 128Mi–2Gi for container `application`. Because `controlledValues: RequestsAndLimits` is set, limits keep their original ratio to requests.

## Lab 4 – In place (VPA ≥ 1.7, alpha)
```bash
# VPA updater + admission controller need --feature-gates=InPlace=true (edit their Deployments)
kubectl apply -f vpa-inplace.yaml -n vpa-demo
kubectl get pods -n vpa-demo -w           # same pod names, RESTARTS unchanged - resized via the resize subresource
```
The cluster side is ready: `InPlacePodVerticalScaling` is on in v1.37 (`../../pods`, Lab 6).

---

## Useful commands
```bash
kubectl get vpa -A
kubectl describe vpa <name>
kubectl get vpa <name> -o jsonpath='{.status.recommendation}' | jq .
```

## Cleanup
```bash
./cleanup.sh       # namespace; see the script for uninstalling VPA itself
```
