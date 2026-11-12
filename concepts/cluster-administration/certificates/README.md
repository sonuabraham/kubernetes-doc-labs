# Certificates – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/cluster-administration/certificates/

> The concept page is a one-line pointer to the task *Generate Certificates Manually*. This lab maps the **PKI your cluster actually uses** ([inspect-pki.sh](inspect-pki.sh), read-only). For *issuing* certificates through the API, see `../../security/controlling-access` (user `bob` via the CSR API) and `../../security/hardening-guide/authentication-mechanisms` (why client certs can't be revoked).

## Key ideas (read first)

| CA | Signs | Used for |
|---|---|---|
| **cluster CA** (`ca.crt`, here `minikubeCA`) | API server serving cert, kubelet client certs, admin/user client certs, CSR API signers | Most authentication: `--client-ca-file` |
| **etcd CA** | etcd server/peer certs, `apiserver-etcd-client` | mTLS to etcd (separate trust domain) |
| **front-proxy CA** | `front-proxy-client` | API aggregation (`--requestheader-client-ca-file`) |
| **kubelet self-signed** | `kubelet.crt` | kubelet serving cert (unless `serverTLSBootstrap` gets one from the cluster CA) |
| **Rotation** | `rotateCertificates: true` → kubelet renews its client cert via the CSR API | |

---

## Lab – Map the PKI
```bash
cd concepts/cluster-administration/certificates
./inspect-pki.sh
```
Measured (abridged):
| File | Subject | Issuer | Expires |
|---|---|---|---|
| `ca.crt` | minikubeCA | self | 2036 |
| `apiserver.crt` | O=system:masters, CN=minikube; SANs control-plane.minikube.internal, kubernetes.default.svc.cluster.local, … | minikubeCA | 2029 |
| `apiserver-kubelet-client.crt` | kube-apiserver-kubelet-client | minikubeCA | 2027 |
| `apiserver-etcd-client.crt` | kube-apiserver-etcd-client | **etcd-ca** | 2027 |
| `etcd/server.crt`, `etcd/peer.crt` | minikube; SANs localhost, 192.168.58.2, 127.0.0.1, ::1 | etcd-ca | 2027 |
| `front-proxy-client.crt` | front-proxy-client | **front-proxy-ca** | 2027 |
| `proxy-client.crt` | O=system:masters, CN=aggregator | proxyClientCA | 2029 |
| kubelet `kubelet-client-current.pem` | O=system:nodes, CN=system:node:minikube | minikubeCA | 2027 |
| kubelet `kubelet.crt` (serving) | minikube@1794041479 | **minikube-ca@1794041479** (self-signed) | 2027 |
```bash
kubectl get --raw /api/v1/nodes/minikube/proxy/configz | jq -c '.kubeletconfig | {rotateCertificates, serverTLSBootstrap}'
#   {"rotateCertificates":true,"serverTLSBootstrap":null}      <- client cert auto-renews; serving cert stays self-signed
```
Things to notice:
- The kubelet's **identity** is in its cert: `CN=system:node:<name>`, `O=system:nodes` (that's what the Node authorizer and NodeRestriction key on).
- The leaf certs expire in ~1 year (kubeadm default) while the CAs last 10 years. Renewal is a yearly chore (`kubeadm certs renew`, or minikube regenerates them).
- The kubelet serving cert isn't signed by the cluster CA, which is why `kubectl logs/exec` traffic from the API server to the kubelet is often run with `--kubelet-insecure-tls` in labs. `serverTLSBootstrap: true` fixes that.

---

## Useful commands
```bash
openssl x509 -in <cert> -noout -subject -issuer -dates -ext subjectAltName
kubectl get csr ; kubectl certificate approve <csr>
kubeadm certs check-expiration         # on kubeadm clusters
```

## Cleanup
Nothing to clean up.
