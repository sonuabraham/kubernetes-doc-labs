# Debug Pods – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/debug/debug-application/debug-pods/

> The page is a checklist without manifests, so this lab **breaks things on purpose**: one manifest per case the page describes,
> in namespace `debug-pods-demo` (plus `debug-pods-rc`). Each case is then diagnosed with the page's own commands.
> Runs on the default **minikube** cluster. All files are not from the docs; [05-typo.yaml](05-typo.yaml) and the Service
> selector `name=nginx,type=frontend` are the docs' examples.
>
> **Found on 1.37:** (1) the docs' `commnd` typo is no longer "silently ignored". kubectl's default `--validate=strict` *rejects*
> it. (2) The docs' check for stuck-Terminating Pods only lists **webhooks**. A ValidatingAdmissionPolicy can block the same
> update and wouldn't show up.

## Key ideas (read first)

| Symptom | Meaning | Look at |
|---|---|---|
| `Pending` | not scheduled | `describe` → `FailedScheduling` message from the scheduler |
| `Waiting` (`ErrImagePull`, `ImagePullBackOff`…) | scheduled, can't start | `describe` → kubelet `Failed` events |
| `Terminating` forever | finalizer not removed (often a webhook/policy blocks the UPDATE) | `.metadata.finalizers`, admission configs |
| `Error` / `CrashLoopBackOff` | the process exits | `kubectl logs [--previous]`, exit code ([Determine the Reason for Pod Failure](../determine-reason-pod-failure/)) |
| Running, wrong behaviour | spec isn't what you think | `kubectl apply --validate=strict`, diff against `kubectl get -o yaml` |
| controller has fewer Pods | it can't create them | `describe rc/rs` → `FailedCreate` |
| Service doesn't answer | no endpoints, or wrong `targetPort` | EndpointSlices, `--selector`, ports |

---

## Step 0 – Break everything
```bash
cd tasks/debug/debug-application/debug-pods
kubectl apply -f 00-namespace.yaml; kubectl create ns debug-pods-rc
kubectl apply -f 01-pending.yaml -f 02-waiting.yaml -f 03-terminating.yaml -f 04-crashing.yaml -f 07-service.yaml -f 06-rc.yaml
N=debug-pods-demo
kubectl get pods -n $N -o wide
```
```
NAME                      READY  STATUS        RESTARTS  NODE
bad-image                 0/1    ErrImagePull  0         minikube
crasher                   0/1    Error         2         minikube
hostport-…-b2gns          1/1    Running       0         minikube
hostport-…-mmgwr          0/1    Pending       0         <none>
nginx-… (×3)              1/1    Running       0         minikube
stuck                     1/1    Running       0         minikube
too-big                   0/1    Pending       0         <none>
```

## Lab 1 – My pod stays pending
```bash
kubectl describe pod too-big -n $N          # Events: FailedScheduling
#   0/1 nodes are available: 1 Insufficient cpu. preemption: … Preemption is not helpful for scheduling.
kubectl describe pod -n $N -l app=hostport | grep FailedScheduling
#   0/1 nodes are available: 1 node(s) didn't have free ports for the requested pod ports. …
```
`hostPort: 18080` fits **once per node**. With one node, replica 2 can never be scheduled. Use a Service instead.

## Lab 2 – My pod stays waiting
```bash
kubectl describe pod bad-image -n $N | grep -E 'State:|Reason:|Failed'
#   State:   Waiting
#   Reason:  ErrImagePull
#   Warning  Failed  … Failed to pull image "busybox:1.36-typo": rpc error: code = NotFound desc = … "docker.io/library/busybox:1.36-typo": failed …
```
The page's three checks: is the name right (it isn't), was it pushed, can you pull it by hand (`minikube ssh -- sudo crictl pull busybox:1.36-typo`).

## Lab 3 – My pod stays terminating
```bash
kubectl delete pod stuck -n $N --wait=false
kubectl get pod stuck -n $N                                     # Terminating
kubectl get pod stuck -n $N -o jsonpath='{.metadata.deletionTimestamp} {.metadata.finalizers}{"\n"}'
#   2026-11-15T05:23:04Z ["example.com/cleanup"]
kubectl patch pod stuck -n $N --type=json -p '[{"op":"remove","path":"/metadata/finalizers"}]'
#   The pods "stuck" is invalid: : ValidatingAdmissionPolicy 'keep-pod-finalizers' … denied request: finalizers may not be removed
```
The docs' check (webhooks that intercept pod `UPDATE`) finds nothing here. Extend it to admission **policies**:
```bash
kubectl get validatingwebhookconfigurations,mutatingwebhookconfigurations -o json | jq -r '.items[] |
  select(any(.webhooks[]?.rules[]?; (.operations|index("UPDATE")) and (.resources|index("pods")))) | .metadata.name'
#   (nothing)
kubectl get validatingadmissionpolicies -o json | jq -r '.items[] |
  select(any(.spec.matchConstraints.resourceRules[]; (.operations|index("UPDATE")) and (.resources|index("pods")))) | .metadata.name'
#   keep-pod-finalizers
kubectl delete validatingadmissionpolicybinding keep-pod-finalizers
kubectl patch pod stuck -n $N --type=json -p '[{"op":"remove","path":"/metadata/finalizers"}]'    # pod/stuck patched
# gone after the 30 s grace period (busybox sleep ignores SIGTERM)
```

## Lab 4 – My pod is crashing
```bash
kubectl describe pod crasher -n $N | grep -E 'State:|Reason:|Exit Code'
#   State: Terminated  Reason: Error  Exit Code: 1   (Last State: the same)
kubectl logs crasher -n $N
#   FATAL: config file /etc/app.conf not found
```
`--previous` can fail with `unable to retrieve container logs for containerd://…` when the kubelet has already removed
the previous container during fast restarts. Then the current attempt's log is all you get. Next steps are in
[Debug Running Pods](../debug-running-pod/).

## Lab 5 – Running, but not doing what I said (the docs' `commnd`)
```bash
kubectl apply -f 05-typo.yaml
#   Error from server (BadRequest): … strict decoding error: unknown field "spec.containers[0].commnd"   <- 1.37: rejected
kubectl apply --validate=warn -f 05-typo.yaml
#   Warning: unknown field "spec.containers[0].commnd"
#   pod/mypod created
kubectl get pod mypod -n $N          # Completed / CrashLoopBackOff: busybox ran its default `sh`, not your command
kubectl get pods/mypod -n $N -o yaml > mypod-on-apiserver.yaml
grep -cE 'commnd|command' mypod-on-apiserver.yaml     # 0 - the field was dropped on the server, as the docs describe
```
The docs' `--validate` advice is now the default. `--validate=false` or `warn` reproduces the old silent behaviour.

## Lab 6 – Debugging Replication Controllers
```bash
kubectl get rc web-rc -n debug-pods-rc          # DESIRED 3  CURRENT 1
kubectl describe rc web-rc -n debug-pods-rc | grep FailedCreate
#   Error creating: pods "web-rc-…" is forbidden: exceeded quota: one-pod, requested: pods=1, used: pods=1, limited: pods=1
```

## Lab 7 – Debugging Services
```bash
for s in svc-mismatch svc-port; do kubectl get endpointslices -n $N -l kubernetes.io/service-name=$s -o json | jq -c '[.items[].endpoints[]?.addresses[0]]'; done
#   []                                             <- svc-mismatch: missing endpoints
#   ["10.244.0.18","10.244.0.16","10.244.0.17"]    <- svc-port: 3 endpoints, as expected for 3 replicas
kubectl get pods -n $N --selector=name=nginx,type=frontend     # No resources found  <- the docs' check finds the cause:
kubectl get pods -n $N -l name=nginx --show-labels | head -2   # …,type=front-end   (hyphen!)
kubectl get svc svc-port -n $N -o jsonpath='{.spec.ports[0].targetPort}'                         # 8080
kubectl get deploy nginx -n $N -o jsonpath='{.spec.template.spec.containers[0].ports[0].containerPort}'   # 80
kubectl run curl -n $N --image=busybox:1.36 --restart=Never -- sh -c 'wget -qO- -T 3 svc-mismatch; wget -qO- -T 3 svc-port'
kubectl logs curl -n $N
#   wget: can't connect to remote host (10.97.121.240): Connection refused     <- no endpoints: kube-proxy rejects
#   wget: can't connect to remote host (10.111.172.168): Connection refused    <- endpoints, but nothing on :8080
```
Both look the same to a client. Only the EndpointSlices and the port check tell them apart. More in [debug-service](../debug-service/).

## Useful commands
```bash
kubectl describe pod <p>
kubectl get events -n <ns> --sort-by=.lastTimestamp
kubectl get pod <p> -o jsonpath='{.status.containerStatuses[*].state}'
kubectl get endpointslices -l kubernetes.io/service-name=<svc>
```

## Cleanup
```bash
./cleanup.sh
```
