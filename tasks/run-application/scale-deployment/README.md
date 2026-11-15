# Horizontal Manual Scaling for a Deployment – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/run-application/scale-deployment/

> Runs on the default **minikube** cluster (metrics-server enabled), `default` namespace.
> File: [deployment.yaml](deployment.yaml) (docs, **verbatim**, the same as in [run-stateless-application-deployment](../run-stateless-application-deployment/)).
>
> **Found:** the "save with `kubectl get -o yaml`, edit, `apply`" workflow works only if nothing changed in between. The exported file
> carries `metadata.resourceVersion`, so a stale copy gives `Conflict: the object has been modified`. It also copies `status` and
> server-filled defaults into `last-applied-configuration`. Remove `resourceVersion`/`uid`/`status` first, or edit the source manifest.

## Key ideas (read first)

| Way | Command | Note |
|---|---|---|
| Imperative | `kubectl scale --replicas=N` | `--current-replicas=M` = precondition |
| Declarative | edit file, `kubectl diff`, `kubectl apply` | `diff` exits 1 when there are changes |
| Patch | `kubectl patch -p '{"spec":{"replicas":N}}'` | JSON patch `test` op = precondition |
| Scale to zero | `--replicas=0` | Deployment + ReplicaSet kept; an HPA stops acting (`ScalingDisabled`) |
| With an HPA | don't | HPA puts back at least `minReplicas` within seconds |

---

## Step 0
```bash
cd tasks/run-application/scale-deployment
kubectl apply -f deployment.yaml
kubectl get deployment nginx-deployment          # 2/2
```

## Lab 1 – Scale up (docs)
```bash
kubectl scale deployment/nginx-deployment --replicas=4     # deployment.apps/nginx-deployment scaled
kubectl get deployment nginx-deployment                    # 4/4
```

### Declarative
```bash
kubectl get deployment nginx-deployment -o yaml > /tmp/nginx-deployment.yaml
sed -i 's/^  replicas: 4/  replicas: 3/' /tmp/nginx-deployment.yaml
kubectl diff -f /tmp/nginx-deployment.yaml; echo "exit=$?"
#   -  generation: 2
#   +  generation: 3
#   -  replicas: 4
#   +  replicas: 3
#   exit=1
kubectl apply -f /tmp/nginx-deployment.yaml               # configured → 3/3
```
Now apply the same (now stale) file again (not from the docs):
```bash
sed -i 's/^  replicas: 3/  replicas: 5/' /tmp/nginx-deployment.yaml
kubectl apply -f /tmp/nginx-deployment.yaml
#   Error from server (Conflict): … Operation cannot be fulfilled on deployments.apps "nginx-deployment":
#   the object has been modified; please apply your changes to the latest version and try again
```

## Lab 2 – Scale down and to zero (docs)
```bash
kubectl scale deployment/nginx-deployment --replicas=2
kubectl get pods -l app=nginx          # 2 Running, the extra ones shown as Completed/Terminating for a moment
kubectl scale deployment/nginx-deployment --replicas=0
kubectl get deployment nginx-deployment                    # 0/0   0   0
kubectl get rs -l app=nginx                                # nginx-deployment-54fd4d6d4c   0   0   0   <- kept
```

## Lab 3 – Patch with a precondition (docs)
```bash
kubectl scale deployment/nginx-deployment --replicas=2
kubectl patch deployment nginx-deployment -p '{"spec":{"replicas":4}}'
kubectl patch deployment nginx-deployment --type=json -p='[
  {"op": "test", "path": "/spec/replicas", "value": 2},
  {"op": "replace", "path": "/spec/replicas", "value": 4}
]'
#   The request is invalid: the server rejected our request due to an error in our request    <- replicas is 4, not 2
kubectl scale deployment/nginx-deployment --replicas=2
# … same JSON patch again …                                 # patched → 4
kubectl scale deployment/nginx-deployment --replicas=5 --current-replicas=3
#   error: Expected replicas to be 3, was 4                 <- kubectl's own precondition (not from the docs)
```

## Lab 4 – Manual scaling vs. an HPA (not from the docs)
```bash
kubectl scale deployment/nginx-deployment --replicas=2
kubectl autoscale deployment nginx-deployment --min=3 --max=5 --cpu=50%
kubectl get deploy nginx-deployment                        # 3 within seconds
kubectl scale deployment/nginx-deployment --replicas=1     # "scaled" …
kubectl get deploy nginx-deployment                        # … back to 3 almost at once
kubectl get events --field-selector involvedObject.kind=HorizontalPodAutoscaler -o custom-columns=REASON:.reason,MSG:.message
#   SuccessfulRescale   New size: 3; reason: Current number of replicas below Spec.MinReplicas
kubectl scale deployment/nginx-deployment --replicas=0
kubectl get hpa nginx-deployment -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.reason}{"\n"}{end}'
#   AbleToScale=True SucceededGetScale
#   ScaledToZero=False NotScaledToZero
#   ScalingActive=False ScalingDisabled      <- zero replicas = HPA paused, stays at 0
```
`minReplicas` is enforced even without metrics (`cpu: <unknown>`). Zero is the only manual value an HPA accepts.

## Cleanup
```bash
./cleanup.sh
```
