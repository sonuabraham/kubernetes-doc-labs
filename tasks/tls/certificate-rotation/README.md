# Configure Certificate Rotation for the Kubelet – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/tls/certificate-rotation/

> The page has no files; it describes `--rotate-certificates` (kubelet), `--cluster-signing-duration` (kube-controller-manager) and the CSR flow.
> To *see* a rotation, the lab runs on a **throwaway profile `rot-lab`** with `--cluster-signing-duration=10m` and makes the kubelet bootstrap a
> fresh client certificate. [rot-lab.sh](rot-lab.sh) (not from the docs): `start` | `bootstrap` | `status` | `delete`. It needs ~15 minutes.
>
> **Notes from testing:**
> - minikube's kubelet already has `rotateCertificates: true` and `--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf`. Its first
>   client cert, though, is the **1-year** cert written by kubeadm, which isn't renewed for months. That's why `bootstrap` deletes it.
> - Certificates are backdated by 5 minutes, so a "10 minute" cert is valid for 15 minutes, and the 70–90% rotation window is measured on those 15.

## Key ideas (read first)

| Piece | Meaning |
|---|---|
| kubelet `rotateCertificates: true` (`--rotate-certificates`) | request a new client cert when 70–90% of the current one's lifetime has passed (random jitter) |
| `--cluster-signing-duration` | maximum validity the controller manager signs (default 1 year) |
| TLS bootstrap | no cert yet → kubelet uses the bootstrap token kubeconfig → CSR from `system:bootstrap:<id>` |
| Auto-approval | kubeadm's ClusterRoleBindings `node-autoapprove-bootstrap` (`…:nodeclient`) and `node-autoapprove-certificate-rotation` (`…:selfnodeclient`) |
| On disk | `/var/lib/kubelet/pki/kubelet-client-<timestamp>.pem` + symlink `kubelet-client-current.pem` |

---

## Lab 1 – Throwaway cluster with short certificates
```bash
cd tasks/tls/certificate-rotation
./rot-lab.sh start
minikube -p rot-lab ssh -- "ps -o args= -C kube-controller-manager | tr ' ' '\n' | grep signing"
#   --cluster-signing-cert-file=/var/lib/minikube/certs/ca.crt
#   --cluster-signing-key-file=/var/lib/minikube/certs/ca.key
#   --cluster-signing-duration=10m
minikube -p rot-lab ssh -- sudo grep rotate /var/lib/kubelet/config.yaml        # rotateCertificates: true
./rot-lab.sh status
#   subject=O = system:nodes, CN = system:node:rot-lab
#   notBefore=Sep 17 12:36:09 2026 GMT    notAfter=Nov 18 11:28:26 2027 GMT      <- kubeadm's 1-year cert
```

## Lab 2 – TLS bootstrap (docs "Understanding the certificate rotation configuration")
```bash
./rot-lab.sh bootstrap        # kubeadm token create → bootstrap-kubelet.conf; stop kubelet, delete client certs, start kubelet
kubectl --context rot-lab get csr
#   csr-flwmk   kubernetes.io/kube-apiserver-client-kubelet   system:bootstrap:fq27ke   Approved,Issued    <- Pending → Approved → Issued in <1 s
./rot-lab.sh status
#   notBefore=Nov 18 11:28:50 2026 GMT    notAfter=Nov 18 11:43:50 2026 GMT      <- issued 11:33:50, 10 min + 5 min backdating
#   kubelet-client-2026-11-18-11-33-50.pem
#   kubelet-client-current.pem -> …/kubelet-client-2026-11-18-11-33-50.pem
kubectl --context rot-lab get clusterrolebinding | grep autoapprove
#   kubeadm:node-autoapprove-bootstrap               ClusterRole/system:certificates.k8s.io:certificatesigningrequests:nodeclient
#   kubeadm:node-autoapprove-certificate-rotation    ClusterRole/system:certificates.k8s.io:certificatesigningrequests:selfnodeclient
```

## Lab 3 – Automatic rotation (docs)
```bash
# wait ~6–9 minutes, then:
kubectl --context rot-lab get csr --sort-by=.metadata.creationTimestamp
#   csr-flwmk   …   system:bootstrap:fq27ke   Approved,Issued
#   csr-rbczx   …   system:node:rot-lab       Approved,Issued      <- created 11:40:03 by the kubelet itself
./rot-lab.sh status
#   notBefore=Nov 18 11:35:03 2026 GMT    notAfter=Nov 18 11:50:03 2026 GMT
#   kubelet-client-2026-11-18-11-33-50.pem
#   kubelet-client-2026-11-18-11-40-03.pem
#   kubelet-client-current.pem -> …/kubelet-client-2026-11-18-11-40-03.pem    <- switched, node stays Ready
```
11:40:03 is 11.2 of the cert's 15 minutes = **75%**, inside the documented window (30% to 10% of the time remaining).
The same happens every ~11 minutes here; with the default 1-year duration it happens after roughly 9–11 months.
Kubelet **serving** certificates are not covered: they're self-signed unless `serverTLSBootstrap: true` (see
[managing-tls-in-a-cluster](../managing-tls-in-a-cluster/)).

## Cleanup
```bash
./cleanup.sh          # = ./rot-lab.sh delete
```
