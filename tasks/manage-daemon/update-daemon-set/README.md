# Perform a Rolling Update on a DaemonSet – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/manage-daemon/update-daemon-set/

> Runs on the default **minikube** cluster (one node), namespace `kube-system` as in the docs. Files (docs, **verbatim**):
> [fluentd-daemonset.yaml](fluentd-daemonset.yaml), [fluentd-daemonset-update.yaml](fluentd-daemonset-update.yaml) (adds resources).
>
> **Found:**
> 1. The docs' `kubectl set image … fluentd:v2.6.0` **goes backwards** from the manifests' `v5.0.1`, and `v2.6.0` is a Docker schema-1 image
>    containerd ≥ 2.1 can't pull (`media type … manifest.v1+prettyjws is no longer supported`). The rollout gets stuck, which happens to
>    reproduce the page's "Broken rollout" section exactly.
> 2. With the docs' `maxUnavailable: 1` the old Pod is deleted **before** the new one works. On a node where the new image fails, the
>    daemon is gone until you fix the template. `maxSurge: 1, maxUnavailable: 0` keeps the old Pod running (Lab 3).

## Key ideas (read first)

| Strategy | Behaviour |
|---|---|
| `RollingUpdate` (default) | template change → per node: delete old Pod, create new one (`maxUnavailable` nodes at a time, default 1) |
| `RollingUpdate` + `maxSurge` | new Pod starts **next to** the old one on the same node; old one removed when the new one is available |
| `OnDelete` | template change does nothing until **you** delete a Pod |
| Stuck rollout | fix by updating the template again; a new rollout isn't blocked by the broken one |

---

## Lab 1 – Create and check the strategy (docs)
```bash
cd tasks/manage-daemon/update-daemon-set
kubectl apply -f fluentd-daemonset.yaml --dry-run=client -o go-template='{{.spec.updateStrategy.type}}{{"\n"}}'     # RollingUpdate
kubectl apply -f fluentd-daemonset.yaml
kubectl rollout status ds/fluentd-elasticsearch -n kube-system         # daemon set "fluentd-elasticsearch" successfully rolled out
kubectl get ds/fluentd-elasticsearch -o go-template='{{.spec.updateStrategy.type}}{{"\n"}}' -n kube-system           # RollingUpdate
```

## Lab 2 – Update, then a broken update (docs)
```bash
kubectl apply -f fluentd-daemonset-update.yaml                         # template changed (resources) → new Pod
kubectl rollout status ds/fluentd-elasticsearch -n kube-system
#   0 out of 1 new pods have been updated... / 0 of 1 updated pods are available... / successfully rolled out
kubectl get pods -l name=fluentd-elasticsearch -n kube-system -o jsonpath='{.items[0].spec.containers[0].resources}'
#   {"limits":{"memory":"200Mi"},"requests":{"cpu":"100m","memory":"200Mi"}}
kubectl set image ds/fluentd-elasticsearch fluentd-elasticsearch=quay.io/fluentd_elasticsearch/fluentd:v2.6.0 -n kube-system
kubectl rollout status ds/fluentd-elasticsearch -n kube-system --timeout=40s
#   Waiting for daemon set "fluentd-elasticsearch" rollout to finish: 0 of 1 updated pods are available...
#   error: timed out waiting for the condition
kubectl get pods -l name=fluentd-elasticsearch -n kube-system           # only the new Pod: ErrImagePull   (old one already deleted)
# message: … failed to pull and unpack image "quay.io/fluentd_elasticsearch/fluentd:v2.6.0": not implemented: media type … manifest.v1+prettyjws …
kubectl set image ds/fluentd-elasticsearch fluentd-elasticsearch=quay.io/fluentd_elasticsearch/fluentd:v5.0.1 -n kube-system
kubectl rollout status ds/fluentd-elasticsearch -n kube-system         # successfully rolled out   <- "update the template again"
```

## Lab 3 – maxSurge and OnDelete (not from the docs)
```bash
N="-n kube-system"; L="-l name=fluentd-elasticsearch"
kubectl patch ds fluentd-elasticsearch $N --type=merge -p '{"spec":{"updateStrategy":{"rollingUpdate":{"maxSurge":1,"maxUnavailable":0}}}}'
kubectl set image ds/fluentd-elasticsearch fluentd-elasticsearch=quay.io/fluentd_elasticsearch/fluentd:v2.6.0 $N
kubectl get pods $N $L
#   fluentd-elasticsearch-4mwcl   1/1   Running        <- old Pod keeps working
#   fluentd-elasticsearch-dwf4x   0/1   ErrImagePull   <- surge Pod on the same node
kubectl set image ds/fluentd-elasticsearch fluentd-elasticsearch=quay.io/fluentd_elasticsearch/fluentd:v5.0.1 $N
kubectl get pods $N $L                  # 4mwcl Running, dwf4x Terminating   <- the old Pod wasn't even restarted
kubectl patch ds fluentd-elasticsearch $N --type=json -p='[{"op":"replace","path":"/spec/updateStrategy","value":{"type":"OnDelete"}}]'
kubectl set env ds/fluentd-elasticsearch $N LAB=ondelete
kubectl get pods $N $L                  # still 4mwcl, without LAB   <- nothing happens
kubectl rollout status ds/fluentd-elasticsearch $N       # error: rollout status is only available for RollingUpdate strategy type
kubectl delete pod fluentd-elasticsearch-4mwcl $N
kubectl get pods $N $L -o jsonpath='{.items[0].metadata.name} {.items[0].spec.containers[0].env}'
#   fluentd-elasticsearch-rf7fn [{"name":"LAB","value":"ondelete"}]      <- the replacement uses the new template
```

## Cleanup
```bash
./cleanup.sh          # = kubectl delete ds fluentd-elasticsearch -n kube-system
```
