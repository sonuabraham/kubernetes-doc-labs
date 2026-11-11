# Communication between Nodes and the Control Plane – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/architecture/control-plane-node-communication/

> Cluster: the 2-node profile **`arch-lab`** (see [../README.md](../README.md)). Control plane `arch-lab` = 192.168.67.2, worker `arch-lab-m02` = 192.168.67.3. Your IPs may differ: `kubectl get nodes -o wide`.

## Key ideas (read first)

| Path | How it's secured | Safe on untrusted networks? |
|---|---|---|
| **Node / Pod → API server** | Hub-and-spoke: **all** traffic ends at the API server's HTTPS port. Clients authenticate: the kubelet with a **client certificate** (from TLS bootstrapping), pods with a **ServiceAccount token** plus the cluster CA, injected automatically. The `kubernetes` Service (`default` ns) routes to the API server via kube-proxy. | **Yes**, secure by default |
| **Other control-plane components** | Scheduler and controller-manager don't expose remote services. They talk to the API server over the secure port. | yes |
| **API server → kubelet** | Used for **logs, attach/exec, port-forward**. HTTPS to the kubelet, but the API server does **not verify** the kubelet's serving cert unless you set `--kubelet-certificate-authority`. Turn on kubelet authn/authz. | **No** (MITM risk) unless verified or tunnelled |
| **API server → node/pod/service (proxy)** | Plain **HTTP** by default. An `https:` prefix encrypts, but doesn't validate the certificate or send credentials. | **No** |
| **SSH tunnels** | Deprecated. | – |
| **Konnectivity** | Beta replacement. Agents on the nodes dial **out** to a Konnectivity server, and all control-plane→node traffic flows through those connections. | yes |

## The demo app
[00-demo-app.yaml](00-demo-app.yaml) creates namespace `comm-demo` with Deployment and Service `web` (agnhost, pinned to the worker), plus ServiceAccount `pod-reader` (may list pods in `comm-demo` only) and pod `api-client` (curl, on the worker).

---

## Step 1
```bash
cd concepts/architecture/control-plane-node-communication
kubectl config use-context arch-lab
kubectl apply -f 00-demo-app.yaml
kubectl wait --for=condition=Ready pod/api-client -n comm-demo --timeout=120s
```

## Lab 1 – Hub and spoke: who listens where
```bash
minikube ssh -p arch-lab -n arch-lab -- "sudo ss -tlnp | grep -E 'kube|etcd'"
```
Expected (summarised):
```
*:8443           kube-apiserver        <- the ONLY control-plane port meant for remote clients
127.0.0.1:10257  kube-controller       <- localhost only - "not designed to expose remote services"
127.0.0.1:10259  kube-scheduler        <- localhost only
127.0.0.1:2379 / 192.168.67.2:2379  etcd   (clients: the API server)
*:10250          kubelet               <- the kubelet API (Lab 4)
```
The worker's only control-plane connection goes to the API server:
```bash
minikube ssh -p arch-lab -n arch-lab-m02 -- "sudo ss -tnp | grep 8443"     # ... 192.168.67.2:8443 users:(("kubelet",...))
```

## Lab 2 – Node → API server: the kubelet's client certificate
```bash
minikube ssh -p arch-lab -n arch-lab-m02 -- "sudo openssl x509 -in /var/lib/kubelet/pki/kubelet-client-current.pem -noout -subject -issuer -enddate"
#   subject=O = system:nodes, CN = system:node:arch-lab-m02     <- identity the Node authorizer uses
#   issuer=CN = minikubeCA
kubectl get csr
#   csr-xxxxx  kubernetes.io/kube-apiserver-client-kubelet  system:bootstrap:75nxvc  Approved,Issued   <- TLS bootstrapping
kubectl get pod -n kube-system kube-apiserver-arch-lab -o jsonpath='{.spec.containers[0].command}' | tr ',' '\n' | grep -E 'client-ca|authorization-mode'
#   --authorization-mode=Node,RBAC        --client-ca-file=/var/lib/minikube/certs/ca.crt
```
The worker joined with a short-lived **bootstrap token**, asked for a certificate through a CSR, and got one signed by the cluster CA. That's kubelet TLS bootstrapping.

## Lab 3 – Pod → API server: ServiceAccount token + CA + the `kubernetes` Service
```bash
kubectl get svc kubernetes -o jsonpath='{.spec.clusterIP}{"\n"}'          # 10.96.0.1
kubectl get endpointslice -n default -l kubernetes.io/service-name=kubernetes -o jsonpath='{.items[0].endpoints[0].addresses} {.items[0].ports[0].port}{"\n"}'
#   ["192.168.67.2"] 8443              <- kube-proxy maps 10.96.0.1:443 to the API server's real address
kubectl exec -n comm-demo api-client -- sh -c '
  SA=/var/run/secrets/kubernetes.io/serviceaccount; ls $SA; env | grep KUBERNETES_SERVICE_HOST
  curl -s --cacert $SA/ca.crt -H "Authorization: Bearer $(cat $SA/token)" https://kubernetes.default.svc/api/v1/namespaces/comm-demo/pods | grep -m2 "\"name\""
  curl -s --cacert $SA/ca.crt -H "Authorization: Bearer $(cat $SA/token)" https://kubernetes.default.svc/api/v1/namespaces/kube-system/pods | grep "\"reason\""
  curl -s --cacert $SA/ca.crt https://kubernetes.default.svc/api/v1/namespaces/comm-demo/pods | grep "\"message\""
  curl -s -o /dev/null -w "without the CA: %{errormsg}\n" https://kubernetes.default.svc/version'
```
Expected:
```
ca.crt namespace token                              <- injected automatically
KUBERNETES_SERVICE_HOST=10.96.0.1
"name": "api-client" ...                            <- token + CA: allowed (RBAC: comm-demo pods)
"reason": "Forbidden"                               <- kube-system: authenticated, but not authorized
"message": "... User \"system:anonymous\" cannot list ..."   <- no token -> anonymous -> denied
without the CA: SSL certificate problem: unable to get local issuer certificate
```

## Lab 4 – API server → kubelet (logs, exec, port-forward)
```bash
kubectl logs deploy/web -n comm-demo -v=6 2>&1 | grep Response | tail -1 | cut -c1-150
#   GET https://192.168.67.2:8443/api/v1/namespaces/comm-demo/pods/web-…/log   <- you ask the API server; it calls the kubelet
kubectl exec deploy/web -n comm-demo -- hostname
kubectl port-forward deploy/web 8080:8080 -n comm-demo &  sleep 2; curl -s localhost:8080/hostname; echo; kill %1
```
What the API server does **not** check:
```bash
kubectl get pod -n kube-system kube-apiserver-arch-lab -o jsonpath='{.spec.containers[0].command}' | tr ',' '\n' | grep kubelet
#   --kubelet-client-certificate=... --kubelet-client-key=...   (the API server authenticates TO the kubelet)
#   no --kubelet-certificate-authority                          (but it does NOT verify the kubelet's cert)
echo | openssl s_client -connect 192.168.67.3:10250 2>/dev/null | openssl x509 -noout -subject -issuer
#   subject=CN=arch-lab-m02@…  issuer=CN=arch-lab-m02-ca@…     <- self-signed serving cert: nothing to verify it against
```
The kubelet itself is protected by authn/authz:
```bash
curl -sk https://192.168.67.3:10250/pods -o /dev/null -w '%{http_code}\n'      # 401 - anonymous callers are rejected
```
To harden this: kubelet `serverTLSBootstrap: true` (CA-signed serving certs) plus `--kubelet-certificate-authority` on the API server, or Konnectivity.

## Lab 5 – API server → node / pod / service proxy
```bash
kubectl get --raw /api/v1/namespaces/comm-demo/services/web:http/proxy/hostname ; echo          # web-…  (service proxy)
P=$(kubectl get pod -n comm-demo -l app=web -o jsonpath='{.items[0].metadata.name}')
kubectl get --raw /api/v1/namespaces/comm-demo/pods/$P:8080/proxy/hostname ; echo              # pod proxy - plain HTTP to the pod
kubectl get --raw "/api/v1/namespaces/comm-demo/pods/https:$P:8080/proxy/hostname"
#   ServiceUnavailable: ... tls: first record does not look like a TLS handshake    <- "https:" prefix: the API server tried TLS (the pod only speaks HTTP)
kubectl get --raw /api/v1/nodes/arch-lab-m02/proxy/healthz ; echo                              # ok - node proxy reaches the kubelet
kubectl get --raw /api/v1/nodes/arch-lab-m02/proxy/pods | jq -r '.items[].metadata.name'       # the kubelet's own view of its pods
```
The `https:` prefix only encrypts. It doesn't check who answers and sends no client credentials, so the docs call these paths **not safe** on public networks.

## Lab 6 – Konnectivity (not installed here)
```bash
kubectl get pod -n kube-system kube-apiserver-arch-lab -o jsonpath='{.spec.containers[0].command}' | tr ',' '\n' | grep -c egress-selector   # 0
kubectl get pods -n kube-system | grep -c konnectivity                                                                                     # 0
```
With Konnectivity, `--egress-selector-config-file` tells the API server to send all node-bound traffic (logs, exec, port-forward, proxy) through a Konnectivity server. **Agents on the nodes dial out** to it, so nodes need no inbound ports from the control plane. Managed clouds use this pattern. Setup: https://kubernetes.io/docs/tasks/extend-kubernetes/setup-konnectivity/

---

## Useful commands
```bash
kubectl get csr                                       # kubelet client cert requests
kubectl get --raw /api/v1/nodes/<node>/proxy/<path>   # reach the kubelet API (stats/summary, pods, healthz)
kubectl get --raw /api/v1/namespaces/<ns>/services/<svc>:<port>/proxy/<path>
kubectl auth can-i --list --as=system:serviceaccount:<ns>:<sa>
```

## Cleanup
```bash
./cleanup.sh
```
