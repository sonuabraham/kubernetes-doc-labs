# Updating Configuration via a ConfigMap – Hands-on Lab

Based on: https://kubernetes.io/docs/tutorials/configuration/updating-configuration-via-a-configmap/

> Runs on the default **minikube** in namespace `default`. The 7 YAML files here are the docs examples **verbatim**
> (`https://k8s.io/examples/...`; `kubectl apply -f <local file>` is the same).
>
> **Found:**
> - **Volume update delay: 77–86 s**, measured three times (sport 80 s, color 77 s, color 86 s). The docs say "after few seconds" and
>   "almost immediately"; the note "as long as kubelet sync period" is the real figure: about 60 s sync plus the kubelet's ConfigMap cache.
> - The sidecar part runs `kubectl create configmap color --from-literal=color=blue`. If you continue from the multi-container part, `color`
>   already exists (and is already `blue`) → `Error: failed to create configmap: configmaps "color" already exists`. That's harmless, as the page says.
> - After `rollout restart`, the old `configmap-env-var` Pods stay `Terminating` for **~30 s**. The `sh` loop is PID 1 and ignores SIGTERM,
>   so each Pod waits out the grace period. That's why the docs say "wait for the older Pods to fully terminate". Until then
>   `kubectl logs deployment/…` can still pick an old Pod and print `apples`.
>
> **Notes:**
> - The page edits with `kubectl edit` (interactive). This lab uses the equivalent non-interactive `kubectl patch` (NOT from the docs). The result is the same.
> - `kubectl port-forward … &` keeps running; stop it with `kill %1` or run [cleanup.sh](cleanup.sh).
> - The sample edited manifest for `color` shows `namespace: configmap`; that's cosmetic. Everything here runs in `default`.

## Key ideas (read first)

| How the ConfigMap is used | What happens when you change it |
|---|---|
| `configMap` volume | the file in the Pod changes after the kubelet sync (~1 min here); the app sees it only if it re-reads the file (here: every 10 s) |
| `env` / `configMapKeyRef` | **never** changes in a running container → `kubectl rollout restart` (new Pods read the new value) |
| Helper container writes `index.html` | nginx serves the new content once the helper picks up the new file |
| Native sidecar (`initContainers` + `restartPolicy: Always`) | same as the helper, but it starts **before** nginx, so the HTML exists when nginx is ready |
| `immutable: true` | `data` (and `immutable` itself) can't be changed. Create a new ConfigMap with a new name and point the Deployment at it, which causes a rollout. The kubelet doesn't watch immutable ConfigMaps, so it does less work |

## Lab 1 – ConfigMap as a volume
```bash
kubectl create configmap sport --from-literal=sport=football
kubectl apply -f deployment-with-configmap-as-volume.yaml
kubectl get pods --selector=app.kubernetes.io/name=configmap-volume       # 3 × 1/1 Running
kubectl logs deployments/configmap-volume
#   Thu Nov 19 08:38:41 UTC 2026 My preferred sport is football
kubectl edit configmap sport            # football -> cricket
#   non-interactive (NOT from the docs): kubectl patch configmap sport -p '{"data":{"sport":"cricket"}}'
kubectl logs deployments/configmap-volume --follow
#   Thu Nov 19 08:39:52 UTC 2026 My preferred sport is football
#   Thu Nov 19 08:40:02 UTC 2026 My preferred sport is football
#   Thu Nov 19 08:40:13 UTC 2026 My preferred sport is cricket          <- 80 s after the patch
```

## Lab 2 – ConfigMap as an environment variable
```bash
kubectl create configmap fruits --from-literal=fruits=apples
kubectl apply -f deployment-with-configmap-as-envvar.yaml
kubectl get pods --selector=app.kubernetes.io/name=configmap-env-var
kubectl logs deployment/configmap-env-var
#   Thu Nov 19 08:40:28 UTC 2026 The basket is full of apples
kubectl edit configmap fruits           # apples -> mangoes   (patch: -p '{"data":{"fruits":"mangoes"}}')
kubectl logs deployments/configmap-env-var --follow
#   … The basket is full of apples      <- unchanged, as the docs say (watched 25 s; env vars are fixed at container start)
kubectl rollout restart deployment configmap-env-var
kubectl rollout status deployment configmap-env-var --watch=true    # deployment "configmap-env-var" successfully rolled out
kubectl get deployment configmap-env-var                            # 3/3   3   3
kubectl get pods --selector=app.kubernetes.io/name=configmap-env-var
#   configmap-env-var-5dd6dfd47d-…   1/1   Terminating   (×3, ~30 s, see heads-up)
#   configmap-env-var-fb66cb59c-…    1/1   Running       (×3)
kubectl logs deployment/configmap-env-var
#   Thu Nov 19 08:40:55 UTC 2026 The basket is full of mangoes
```

## Lab 3 – Multi-container Pod (nginx + helper)
```bash
kubectl create configmap color --from-literal=color=red
kubectl apply -f deployment-with-configmap-two-containers.yaml
kubectl get pods --selector=app.kubernetes.io/name=configmap-two-containers    # 3 × 2/2 Running
kubectl expose deployment configmap-two-containers --name=configmap-service --port=8080 --target-port=80
kubectl port-forward service/configmap-service 8080:8080 &
curl http://localhost:8080
#   Thu Nov 19 08:41:44 UTC 2026 My preferred color is red
kubectl edit configmap color            # red -> blue
while true; do curl --connect-timeout 7.5 http://localhost:8080; sleep 10; done
#   … My preferred color is red
#   Thu Nov 19 08:43:04 UTC 2026 My preferred color is blue            <- 77 s after the patch
```
`port-forward service/…` picks **one** Pod behind the Service, so you watch that Pod only.

## Lab 4 – Pod with a sidecar container
```bash
kubectl create configmap color --from-literal=color=blue
#   Error: failed to create configmap: configmaps "color" already exists     <- continuing from Lab 3 (already blue)
kubectl apply -f deployment-with-configmap-and-sidecar-container.yaml
kubectl get pods --selector=app.kubernetes.io/name=configmap-sidecar-container # 3 × 2/2 Running (the sidecar counts in READY)
kubectl get pod -l app.kubernetes.io/name=configmap-sidecar-container \
  -o jsonpath='{.items[0].spec.initContainers[0].restartPolicy}'               # Always    (check NOT from the docs)
kubectl expose deployment configmap-sidecar-container --name=configmap-sidecar-service --port=8081 --target-port=80
kubectl port-forward service/configmap-sidecar-service 8081:8081 &
curl http://localhost:8081
#   Thu Nov 19 08:43:14 UTC 2026 My preferred color is blue
kubectl edit configmap color            # blue -> green
while true; do curl --connect-timeout 7.5 http://localhost:8081; sleep 10; done
#   Thu Nov 19 08:44:44 UTC 2026 My preferred color is green           <- 86 s after the patch
```

## Lab 5 – Immutable ConfigMap
```bash
kubectl apply -f immutable-configmap.yaml                   # configmap/company-name-20150801 created
kubectl apply -f deployment-with-immutable-configmap-as-volume.yaml
kubectl get pods --selector=app.kubernetes.io/name=immutable-configmap-volume
kubectl logs deployments/immutable-configmap-volume
#   Thu Nov 19 08:45:00 UTC 2026 The name of the company is ACME, Inc.

# NOT from the docs – prove it really is immutable:
kubectl patch configmap company-name-20150801 -p '{"data":{"company_name":"X"}}'
#   The ConfigMap "company-name-20150801" is invalid: data: Forbidden: field is immutable when `immutable` is set
kubectl patch configmap company-name-20150801 -p '{"immutable":false}'
#   The ConfigMap "company-name-20150801" is invalid: immutable: Forbidden: field is immutable when `immutable` is set

kubectl apply -f new-immutable-configmap.yaml               # configmap/company-name-20240312 created
kubectl get configmap                                       # both company-name-* listed
kubectl edit deployment immutable-configmap-volume          # volumes[0].configMap.name: company-name-20240312
#   non-interactive (NOT from the docs):
#   kubectl patch deployment immutable-configmap-volume --type=json \
#     -p '[{"op":"replace","path":"/spec/template/spec/volumes/0/configMap/name","value":"company-name-20240312"}]'
kubectl get pods --selector=app.kubernetes.io/name=immutable-configmap-volume
#   new Pods Running; old ones Terminating for ~30 s, then gone
kubectl logs deployment/immutable-configmap-volume
#   Thu Nov 19 08:45:01 UTC 2026 The name of the company is Fiktivesunternehmen GmbH
kubectl delete configmap company-name-20150801
```

## Cleanup
The docs' cleanup commands plus stopping the port-forwards:
```bash
./cleanup.sh
```
