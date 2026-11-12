# Certificate Management with kubeadm – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-certs/

> Runs on the throwaway profile **`kubeadm-lab`** ([../start-kubeadm-lab.sh](../start-kubeadm-lab.sh)). minikube bootstraps its node **with kubeadm**, so the real `kubeadm` and a kubeadm-made PKI are on the node. [../node.sh](../node.sh) runs commands there as root (`$KUBEADM`, `$PKI`), and [../restart-control-plane.sh](../restart-control-plane.sh) restarts the static Pods.
>
> The docs' YAML is **verbatim**:
> - [encryption-algorithm.yaml](encryption-algorithm.yaml)
> - [validity-periods.yaml](validity-periods.yaml)
> - [kubelet-conf-excerpt.yaml](kubelet-conf-excerpt.yaml)
> - [signer-controller-manager.yaml](signer-controller-manager.yaml)
> - [kubelet-serving-certs.yaml](kubelet-serving-certs.yaml)
> - [kubeconfig-user-example.yaml](kubeconfig-user-example.yaml)
>
> **minikube difference:** the PKI lives in `/var/lib/minikube/certs`, not `/etc/kubernetes/pki`. Pass `--cert-dir`, or set `certificatesDir` in a config.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **What kubeadm creates** | CAs (`ca`, `etcd-ca`, `front-proxy-ca`; **10 years**) and leaf certs + kubeconfigs (**1 year**). Existing files are reused, so you can bring your own CA. |
| **Algorithm & validity** | `encryptionAlgorithm` (RSA-2048 default, RSA-3072/4096, ECDSA-P256/P384), `certificateValidityPeriod`, `caCertificateValidityPeriod` (v1beta4). |
| **check-expiration** | Lists every cert/kubeconfig, its CA and residual time. |
| **Automatic renewal** | `kubeadm upgrade` renews everything, so upgrading at least yearly keeps certs fresh (`--certificate-renewal=false` to opt out). |
| **Manual renewal** | `kubeadm certs renew <name>\|all`, then **restart** the control-plane static Pods (they aren't managed through the API, so move the manifests out and back). On HA clusters, run it on every control-plane node. |
| **External CA** | If only the CA cert (no key) is present, kubeadm runs in "external CA" mode. `kubeadm certs generate-csr` / `renew --csr-only` produce CSRs for your CA to sign. |
| **CSR API** | The controller-manager signs `CertificateSigningRequest`s with `--cluster-signing-cert/key-file`. |
| **kubelet serving certs** | Self-signed by default. `serverTLSBootstrap: true` makes the kubelet request a `kubernetes.io/kubelet-serving` CSR, which **you (or a tool) approve**. |
| **kubelet client cert** | Rotated automatically (`/var/lib/kubelet/pki/kubelet-client-current.pem`). Old clusters had it embedded in `kubelet.conf`; see the excerpt. |
| **CA rotation** | A manual, multi-step procedure (separate task page). |

---

## Step 0
```bash
cd tasks/administer-cluster/kubeadm
./start-kubeadm-lab.sh          # v1.36.0, ~1 min
cd kubeadm-certs
```

## Lab 1 – check-expiration
```bash
../node.sh '$KUBEADM certs check-expiration'
#   error: ... couldn't load the certificate file /etc/kubernetes/pki/ca.crt: no such file or directory
#   (even though the kubeadm-config ConfigMap says certificatesDir: /var/lib/minikube/certs)
../node.sh '$KUBEADM certs check-expiration --cert-dir $PKI'
#   CERTIFICATE                EXPIRES                  RESIDUAL TIME   CERTIFICATE AUTHORITY   EXTERNALLY MANAGED
#   admin.conf                 Nov 12, 2027 10:03 UTC   364d            ca                      no
#   apiserver                  Nov 11, 2029 10:03 UTC   2y364d          ca                      no     <- minikube made this one (3y)
#   apiserver-etcd-client      Nov 12, 2027 10:03 UTC   364d            etcd-ca                 no
#   ... etcd-peer, etcd-server, front-proxy-client, scheduler.conf, super-admin.conf: 364d
#   CERTIFICATE AUTHORITY   EXPIRES                  RESIDUAL TIME
#   ca                      Sep 15, 2036 12:36 UTC   9y        <- shared by all minikube profiles (~/.minikube/ca.crt)
#   etcd-ca                 Nov 09, 2036 10:03 UTC   9y
#   front-proxy-ca          Nov 09, 2036 10:03 UTC   9y
```

## Lab 2 – Manual renewal and restarting the control plane
```bash
IP=$(minikube ip -p kubeadm-lab)
served(){ echo | openssl s_client -connect $IP:8443 2>/dev/null | openssl x509 -noout -serial -startdate; }
served                                            # serial=02  notBefore=Nov 11 10:03:23 2026
../node.sh '$KUBEADM certs renew all --cert-dir $PKI'
#   certificate for serving the Kubernetes API renewed ... (11 lines)
#   Done renewing certificates. You must restart the kube-apiserver, kube-controller-manager, kube-scheduler and etcd, so that they can use the new certificates.
../node.sh 'openssl x509 -in $PKI/apiserver.crt -noout -startdate -enddate'
#   notBefore=Nov 12 09:59:16 2026 GMT   notAfter=Nov 12 10:04:16 2027 GMT     <- now kubeadm's 1 year (was 3y), backdated 5 min
served                                            # serial=07A5B7B5F10D77A7  <- already served, NO restart yet
```
kube-apiserver **reloads its serving cert from disk on its own**. The client certs (apiserver→etcd, →kubelet), the components' kubeconfigs and etcd's certs still need a restart:
```bash
../restart-control-plane.sh
#   all control-plane containers stopped
#   manifests back, apiserver container running
#   API server ready                                  (37s)
kubectl --context kubeadm-lab get pods -n kube-system -l tier=control-plane -o custom-columns=NAME:.metadata.name,STARTED:.status.containerStatuses[0].state.running.startedAt,RESTARTS:.status.containerStatuses[0].restartCount
#   etcd-kubeadm-lab                      2026-11-12T10:05:00Z   1      (mirror Pods catch up after ~15s)
```
`/etc/kubernetes/admin.conf` on the node was renewed too. Your laptop's `kubeadm-lab` context uses minikube's own client cert, which is separate.

## Lab 3 – A user kubeconfig from kubeadm
The docs' [kubeconfig-user-example.yaml](kubeconfig-user-example.yaml) has `controlPlaneEndpoint: some-dns-address:6443` and `/etc/kubernetes/pki`. On minikube the same file says `control-plane.minikube.internal:8443` and `/var/lib/minikube/certs`:
```bash
../node.sh 'printf "apiVersion: kubeadm.k8s.io/v1beta4\nkind: ClusterConfiguration\ncertificatesDir: /var/lib/minikube/certs\ncontrolPlaneEndpoint: control-plane.minikube.internal:8443\n" > /tmp/kc.yaml
  $KUBEADM kubeconfig user --config /tmp/kc.yaml --client-name=alice --org=devs --validity-period=24h > /tmp/alice.conf
  $(dirname $KUBEADM)/kubectl --kubeconfig /tmp/alice.conf auth whoami'
#   Username   alice
#   Groups     [devs system:authenticated]
#   (kubectl get pods -> Forbidden: authenticated, but no RBAC yet; cert subject O=devs, CN=alice, notAfter = +24h)
```

## Lab 4 – External CA: CSRs from kubeadm, signed elsewhere
```bash
../node.sh 'mkdir -p /tmp/csr; $KUBEADM certs generate-csr --cert-dir /tmp/csr --kubeconfig-dir /tmp/csr --config /tmp/kc.yaml; ls /tmp/csr'
#   admin.conf admin.conf.csr apiserver.csr apiserver.key apiserver-etcd-client.csr ... kubelet.conf.csr scheduler.conf.csr ...
../node.sh 'openssl req -in /tmp/csr/apiserver.csr -noout -subject'          # subject=CN = kube-apiserver  (+ all the SANs)
../node.sh 'openssl x509 -req -in /tmp/csr/apiserver.csr -CA $PKI/ca.crt -CAkey $PKI/ca.key -CAcreateserial -days 30 -copy_extensions copy -out /tmp/csr/apiserver.crt && openssl verify -CAfile $PKI/ca.crt /tmp/csr/apiserver.crt'
#   /tmp/csr/apiserver.crt: OK              <- openssl played the "external CA"; the key never left the node
```

## Lab 5 – Algorithm and validity (docs' encryption-algorithm.yaml + validity-periods.yaml)
A fresh PKI is generated into `/tmp/pki2` on the node. The live cluster isn't touched.
```bash
../node.sh 'printf "apiVersion: kubeadm.k8s.io/v1beta4\nkind: ClusterConfiguration\nencryptionAlgorithm: ECDSA-P256\ncertificateValidityPeriod: 720h\ncaCertificateValidityPeriod: 8760h\ncertificatesDir: /tmp/pki2\n" > /tmp/certcfg.yaml
  $KUBEADM init phase certs all --config /tmp/certcfg.yaml >/dev/null
  for c in ca apiserver etcd/ca front-proxy-client; do echo "$c $(openssl x509 -in /tmp/pki2/$c.crt -noout -enddate) $(openssl x509 -in /tmp/pki2/$c.crt -noout -text | grep -m1 "ASN1 OID")"; done'
#   ca                 notAfter=Nov 12 10:05:51 2027 GMT   ASN1 OID: prime256v1     <- CA: 8760h
#   apiserver          notAfter=Dec 12 10:05:51 2026 GMT   ASN1 OID: prime256v1     <- leaf: 720h
#   etcd/ca            notAfter=Nov 12 10:05:51 2027 GMT   ASN1 OID: prime256v1
#   front-proxy-client notAfter=Dec 12 10:05:51 2026 GMT   ASN1 OID: prime256v1
```
`--cert-dir` and `--config` can't be combined ("can not mix '--config' with arguments [cert-dir]"), so `certificatesDir` goes in the config instead.

## Lab 6 – Signed kubelet serving certificates (docs' kubelet-serving-certs.yaml)
minikube's controller-manager already signs CSRs (the docs' [signer-controller-manager.yaml](signer-controller-manager.yaml), with minikube paths):
```bash
kubectl --context kubeadm-lab get pod -n kube-system kube-controller-manager-kubeadm-lab -o jsonpath='{.spec.containers[0].command}' | tr , '\n' | grep signing
#   "--cluster-signing-cert-file=/var/lib/minikube/certs/ca.crt"   "--cluster-signing-key-file=/var/lib/minikube/certs/ca.key"
kub(){ echo | openssl s_client -connect $(minikube ip -p kubeadm-lab):10250 2>/dev/null | openssl x509 -noout -issuer -subject; }
kub          # issuer=CN=kubeadm-lab-ca@1794477805  subject=CN=kubeadm-lab@1794477805        <- self-signed
../node.sh 'echo "serverTLSBootstrap: true" >> /var/lib/kubelet/config.yaml; systemctl restart kubelet'
kubectl --context kubeadm-lab get csr
#   csr-dgf9z   4s   kubernetes.io/kubelet-serving   system:node:kubeadm-lab   Pending       <- nobody approves these automatically
kubectl --context kubeadm-lab certificate approve csr-dgf9z
kub          # issuer=CN=minikubeCA  subject=O=system:nodes, CN=system:node:kubeadm-lab   <- signed by the cluster CA
../node.sh 'ls -l /var/lib/kubelet/pki/'     # kubelet-server-current.pem -> kubelet-server-2026-11-12-10-06-11.pem
```
In a new cluster you'd pass `serverTLSBootstrap: true` in the KubeletConfiguration at `kubeadm init`. Approving these CSRs is then an ongoing task (or a job for an approver controller).

---

## Useful commands
```bash
kubeadm certs check-expiration ; kubeadm certs renew all ; kubeadm certs generate-csr
kubeadm kubeconfig user --client-name=<n> --org=<group>
kubectl get csr ; kubectl certificate approve <csr>
```

## Cleanup
Labs 1–6 only changed the throwaway profile. Keep it running for the next kubeadm labs, or `minikube stop -p kubeadm-lab`.
