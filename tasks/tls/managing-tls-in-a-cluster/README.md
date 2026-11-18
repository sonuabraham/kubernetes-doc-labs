# Manage TLS Certificates in a Cluster – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/tls/managing-tls-in-a-cluster/

> Runs on the default **minikube** cluster. File (docs, **verbatim**): [server-signing-config.json](server-signing-config.json).
> Not from the docs: [bin/cfssl](bin/cfssl) / [bin/cfssljson](bin/cfssljson) (run cfssl v1.6.5 from its container image, no install),
> [https-demo.yaml](https-demo.yaml) (uses the issued certificate: HTTPS nginx behind `my-svc.my-namespace` + a client Pod).
> Keys and certificates are created in `work/` (gitignored, removed by [cleanup.sh](cleanup.sh)).
>
> **Notes:**
> - `server-signing-config.json` signs for `876000h`, i.e. **100 years** (`notAfter=Oct 25 11:38:00 2126`). Fine for a demo, not for real use.
> - `kubectl certificate approve` alone leaves a custom-signer CSR at `Approved` (no `Issued`); for `example.com/serving` *you* are the signer.
> - The page's Secret/ConfigMap commands use the default namespace; this lab puts them in `my-namespace`, next to the Pod that uses them.

## Key ideas (read first)

| Role | Who | Action |
|---|---|---|
| Requester | you (or a Pod) | key + CSR with the DNS names/IPs, `CertificateSigningRequest` with `signerName: example.com/serving` |
| Approver | admin / automated controller | `kubectl certificate approve` = checks the subject owns the key **and** may use those names |
| Signer | whoever owns `example.com/serving` (here: you with cfssl) | signs approved CSRs and writes `status.certificate` via the `/status` subresource |
| Consumers | clients | trust the signer's CA (ConfigMap), **not** `kube-root-ca.crt` |

---

## Lab 1 – CSR, approve, sign (docs, verbatim commands)
```bash
cd tasks/tls/managing-tls-in-a-cluster
export PATH=$PWD/bin:$PATH && mkdir -p work && cd work && cp ../server-signing-config.json .
cat <<EOF | cfssl genkey - | cfssljson -bare server
{ "hosts": ["my-svc.my-namespace.svc.cluster.local","my-pod.my-namespace.pod.cluster.local","192.0.2.24","10.0.34.2"],
  "CN": "my-pod.my-namespace.pod.cluster.local", "key": {"algo": "ecdsa", "size": 256} }
EOF
#   [INFO] generating key: ecdsa-256 … encoded CSR        -> server.csr, server-key.pem
cat <<EOF | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: my-svc.my-namespace
spec:
  request: $(cat server.csr | base64 | tr -d '\n')
  signerName: example.com/serving
  usages:
  - digital signature
  - key encipherment
  - server auth
EOF
kubectl describe csr my-svc.my-namespace
#   Requesting User:  minikube-user   Signer: example.com/serving   Status: Pending
#   DNS Names: my-svc.my-namespace.svc.cluster.local, my-pod.my-namespace.pod.cluster.local   IP Addresses: 192.0.2.24, 10.0.34.2
kubectl certificate approve my-svc.my-namespace
kubectl get csr my-svc.my-namespace          # … example.com/serving   minikube-user   <none>   Approved     <- nobody signs yet
cat <<EOF | cfssl gencert -initca - | cfssljson -bare ca
{ "CN": "My Example Signer", "key": { "algo": "rsa", "size": 2048 } }
EOF
kubectl get csr my-svc.my-namespace -o jsonpath='{.spec.request}' | base64 --decode | \
  cfssl sign -ca ca.pem -ca-key ca-key.pem -config server-signing-config.json - | cfssljson -bare ca-signed-server
kubectl get csr my-svc.my-namespace -o json | \
  jq '.status.certificate = "'$(base64 ca-signed-server.pem | tr -d '\n')'"' | \
  kubectl replace --raw /apis/certificates.k8s.io/v1/certificatesigningrequests/my-svc.my-namespace/status -f -
kubectl get csr                              # … Approved,Issued
kubectl get csr my-svc.my-namespace -o jsonpath='{.status.certificate}' | base64 --decode > server.crt
openssl x509 -in server.crt -noout -subject -issuer -enddate -ext subjectAltName,extendedKeyUsage
#   subject=CN=my-pod.my-namespace.pod.cluster.local   issuer=CN=My Example Signer   notAfter=Oct 25 11:38:00 2126 GMT
#   TLS Web Server Authentication
#   DNS:my-svc.my-namespace.svc.cluster.local, DNS:my-pod.my-namespace.pod.cluster.local, IP Address:192.0.2.24, IP Address:10.0.34.2
```

## Lab 2 – Use it (docs' last step + a real server, not from the docs)
```bash
kubectl create namespace my-namespace
kubectl -n my-namespace create secret tls server --cert server.crt --key server-key.pem
kubectl -n my-namespace create configmap example-serving-ca --from-file ca.crt=ca.pem
kubectl apply -f ../https-demo.yaml
C="kubectl -n my-namespace exec client --"
$C curl -s --cacert /ca/ca.crt https://my-svc.my-namespace.svc.cluster.local/
#   hello over TLS from my-pod
$C curl -s --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt https://my-svc.my-namespace.svc.cluster.local/
#   SSL certificate problem: unable to get local issuer certificate     <- kube-root-ca.crt is the cluster CA, not this signer
$C curl -s --cacert /ca/ca.crt https://my-svc/
#   SSL: no alternative certificate subject name matches target hostname 'my-svc'      <- only the names in the CSR
$C sh -c 'curl -s --cacert /ca/ca.crt https://$MY_SVC_SERVICE_HOST/'
#   SSL: no alternative certificate subject name matches target ipv4 address '10.100.163.239'   <- 192.0.2.24 was the docs' example IP
```

## Cleanup
```bash
cd .. && ./cleanup.sh
```
