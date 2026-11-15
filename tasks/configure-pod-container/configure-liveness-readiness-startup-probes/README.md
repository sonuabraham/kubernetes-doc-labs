# Configure Liveness, Readiness and Startup Probes – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/

> Labs 1–7 run on the default **minikube** cluster, in the `default` namespace as in the docs. Lab 8 needs two **alpha** gates
> and uses a throwaway profile ([start-probe-lab.sh](start-probe-lab.sh)).
> Docs examples (**verbatim**): [exec-liveness.yaml](exec-liveness.yaml), [http-liveness.yaml](http-liveness.yaml),
> [h2c-liveness.yaml](h2c-liveness.yaml), [tcp-liveness-readiness.yaml](tcp-liveness-readiness.yaml),
> [grpc-liveness.yaml](grpc-liveness.yaml), [grpc-tls-liveness.yaml](grpc-tls-liveness.yaml).
> Not from the docs: [startup-probe.yaml](startup-probe.yaml) (wraps the docs' named-port + startup snippet),
> [readiness-service.yaml](readiness-service.yaml) (wraps the docs' readiness snippet), [grpc-tls-etcd.yaml](grpc-tls-etcd.yaml).
>
> **Found on 1.37:** with `GRPCContainerProbeTLS` on, the docs' `grpc-tls-app` **fails** its probe. Its agnhost server
> only speaks plaintext gRPC. It only looks healthy on a default cluster because the gate is off and `mode: TLS` is
> silently dropped.

## Key ideas (read first)

| Probe | Fails ⇒ | Typical use |
|---|---|---|
| **liveness** | container is **killed and restarted** (`restartPolicy`) | deadlocks, wedged processes |
| **readiness** | Pod removed from Service endpoints. **No restart**; runs for the whole lifetime. | warming up, dependency down, overload |
| **startup** | Liveness and readiness are **held off** until it succeeds once. If it never does: killed after `failureThreshold × periodSeconds`. | slow first start |

| Mechanism | Success | Notes |
|---|---|---|
| `exec` | exit code 0 | `timeoutSeconds` enforced (`ExecProbeTimeout` GA) |
| `httpGet` | 200 ≤ status < 400 | to Pod IP. `httpHeaders`, named ports. Proxy env vars ignored. `protocol: HTTP2` (h2c) is alpha. |
| `tcpSocket` | connect works | |
| `grpc` | `SERVING` from grpc.health.v1 | numeric port only (no named port). Plaintext unless `mode: TLS` (alpha, InsecureSkipVerify). |

---

## Step 0
```bash
cd tasks/configure-pod-container/configure-liveness-readiness-startup-probes
kubectl get --raw /metrics | grep -E 'kubernetes_feature_enabled\{name="(H2CContainerProbe|GRPCContainerProbeTLS)"'
#   GRPCContainerProbeTLS  ALPHA 0
#   H2CContainerProbe      ALPHA 0
ev(){ kubectl get events --field-selector involvedObject.name=$1 -o custom-columns=REASON:.reason,COUNT:.count,MSG:.message --no-headers \
      | grep -vE 'Scheduled|Pulling|Pulled|Created|Started'; }
```

## Lab 1 – exec liveness (docs)
```bash
kubectl apply -f exec-liveness.yaml
sleep 70; kubectl get pod liveness-exec; ev liveness-exec
#   liveness-exec   1/1   Running   1 (3s ago)
#   Unhealthy  3  Liveness probe failed: cat: can't open '/tmp/healthy': No such file or directory
#   Killing    1  Container liveness failed liveness probe, will be restarted
```
The file disappears at 30 s. After 3 failures (`failureThreshold` default 3, every 5 s), the kubelet restarts the container.
The new container recreates the file, and the cycle repeats.

## Lab 2 – HTTP liveness (docs)
```bash
kubectl apply -f http-liveness.yaml
sleep 70; kubectl get pod liveness-http; ev liveness-http
#   liveness-http   0/1   CrashLoopBackOff   3
#   Unhealthy  12  Liveness probe failed: HTTP probe failed with statuscode: 500
#   Killing     4  Container liveness failed liveness probe, will be restarted
#   BackOff     2  Back-off restarting failed container liveness …
```
agnhost returns 500 after 10 s. Each restart then waits longer (CrashLoopBackOff).

## Lab 3 – TCP liveness + readiness (docs) and gRPC liveness (docs)
```bash
kubectl apply -f tcp-liveness-readiness.yaml -f grpc-liveness.yaml
sleep 30; kubectl get pod goproxy etcd-with-grpc        # both 1/1 Running, 0 restarts, no Unhealthy events
kubectl describe pod etcd-with-grpc | grep Liveness
#   Liveness:  grpc <pod>:2379  delay=10s timeout=1s period=10s #success=1 #failure=3
```
To see gRPC fail, use the agnhost Pod's switch (agnhost serves plaintext gRPC, so it works here with the gate off):
```bash
kubectl apply -f grpc-tls-liveness.yaml
IP=$(kubectl get pod grpc-tls-app -o jsonpath='{.status.podIP}')
kubectl run curl --image=busybox:1.36 --restart=Never -- wget -qO- http://$IP:8080/make-not-serving
sleep 35; ev grpc-tls-app
#   Unhealthy 3  Liveness probe failed: service unhealthy (responded with "NOT_SERVING")
#   Killing   1  Container app failed liveness probe, will be restarted
kubectl delete pod curl --now
```

## Lab 4 – Alpha fields with the gates off (docs h2c / gRPC TLS)
```bash
kubectl apply -f h2c-liveness.yaml
kubectl get pod h2c-app -o json | jq -c .spec.containers[0].livenessProbe.httpGet
#   {"path":"/healthz","port":8080,"scheme":"HTTP"}            <- "protocol: HTTP2" was dropped by the API server
kubectl get pod grpc-tls-app -o json | jq -c .spec.containers[0].livenessProbe.grpc
#   {"port":8443,"service":""}                                <- "mode: TLS" was dropped
sleep 70; ev h2c-app
#   Unhealthy 6  Liveness probe failed: Get "http://10.244.0.26:8080/healthz": net/http: HTTP/1.x transport connection broken:
#                malformed HTTP response "\x00\x00$\x04…"     <- HTTP/1.1 probe vs an h2c-only server (HTTP/2 frames)
```

## Lab 5 – Startup probe + named port (the docs' snippet, wrapped)
```bash
kubectl apply -f startup-probe.yaml     # both Pods: httpd starts after 45 s; liveness failureThreshold 1
sleep 80; kubectl get pod slow-start startup-probe-missing
#   slow-start              1/1   Running   0
#   startup-probe-missing   1/1   Running   1 (36s ago)     <- and it never stops: killed before it can ever start
ev slow-start
#   Unhealthy  4  Startup probe failed: Get "http://10.244.0.29:8080/healthz": dial tcp …: connect: connection refused
ev startup-probe-missing
#   Unhealthy  2  Liveness probe failed: … connection refused
#   Killing    2  Container app failed liveness probe, will be restarted
```
Up to 30 × 10 s = 300 s are allowed for start-up, and then liveness reacts within 10 s.

## Lab 6 – Readiness behind a Service (the docs' snippet, wrapped)
```bash
kubectl apply -f readiness-service.yaml; kubectl rollout status deploy/ready-demo
P=$(kubectl get pod -l app=ready-demo -o jsonpath='{.items[0].metadata.name}')
kubectl exec $P -- rm -v /tmp/healthy; sleep 12
kubectl get pods -l app=ready-demo                    # $P: 0/1 Running, RESTARTS 0 (no restart!)
kubectl get endpointslices -l kubernetes.io/service-name=ready-demo -o json | jq -c '[.items[].endpoints[]|{pod:.targetRef.name, ready:.conditions.ready}]'
#   [{"pod":"ready-demo-…-vkgnj","ready":true},{"pod":"ready-demo-…-4wmcs","ready":false}]
kubectl run curl --image=busybox:1.36 --restart=Never -- sh -c 'for i in 1 2 3 4 5 6; do wget -qO- ready-demo; done'
sleep 6; kubectl logs curl | sort | uniq -c
#   6 ready-demo-…-vkgnj                              <- all traffic to the ready Pod
kubectl exec $P -- touch /tmp/healthy; sleep 8; kubectl get pods -l app=ready-demo    # back to 1/1
kubectl delete pod curl --now
```

## Lab 7 – Probe status at a glance
```bash
kubectl get pods
kubectl describe pod <p> | grep -E 'Liveness|Readiness|Startup'
```

## Lab 8 – h2c and gRPC TLS with the alpha gates on (not from the docs)
```bash
./cleanup.sh; minikube stop                 # free inotify for the second cluster
./start-probe-lab.sh                        # profile probe-lab: H2CContainerProbe, GRPCContainerProbeTLS
K="kubectl --context probe-lab"
$K apply -f h2c-liveness.yaml -f grpc-tls-liveness.yaml -f grpc-tls-etcd.yaml
$K get pod grpc-tls-app -o json | jq -c .spec.containers[0].livenessProbe.grpc     # {"mode":"TLS","port":8443,…} kept now
sleep 75; $K get pods
```
| Pod | Result |
|---|---|
| h2c-app (docs) | `Running`, 0 restarts: the h2c probe works |
| grpc-tls-app (docs) | **restarts**: `Liveness probe failed: timeout: failed to connect service "10.244.0.4:8443" within 1s`. A TLS handshake against a plaintext gRPC server. |
| etcd-with-grpc-tls | `Running`, 0 restarts: a real TLS gRPC server (self-signed, not verified) |
```bash
$K get pod h2c-app -o json | jq '.spec.containers[0].livenessProbe.httpGet.scheme="HTTPS" | .metadata={name:"h2c-https"} | del(.status)' \
  | $K apply --dry-run=server -f -
#   … httpGet.protocol: Invalid value: "HTTP2": is only supported with HTTP (H2C)
minikube delete -p probe-lab; minikube start
```

## Useful commands
```bash
kubectl get events --field-selector reason=Unhealthy
kubectl get pod <p> -o jsonpath='{.status.containerStatuses[0].restartCount}'
kubectl explain pod.spec.containers.livenessProbe
```

## Cleanup
```bash
./cleanup.sh      # every Pod/Deployment/Service in this folder (+ the probe-lab profile if it exists)
```
