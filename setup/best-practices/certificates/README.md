# Kubernetes PKI Certificates and Requirements – Hands-on Lab

Based on: https://kubernetes.io/docs/setup/best-practices/certificates/

> Runs on the real kubeadm lab machines from [../../production-environment/tools/kubeadm](../../production-environment/tools/kubeadm/)
> (`machines.sh`): **cp1** = the existing kubeadm cluster (kubeadm-generated PKI), **cp2** = a fresh control plane built on a PKI made
> by hand from the page's tables. The page has no YAML; every file here is NOT from the docs:
> [cert-report.sh](cert-report.sh) (dump what a node really has), [shared-apiserver-cert.sh](shared-apiserver-cert.sh) ("Shared
> Certificates"), [gen-all-certs.sh](gen-all-certs.sh) ("All certificates" + "user accounts" tables + the page's 4 `kubectl config`
> commands), [kubeadm-init-external-ca.yaml](kubeadm-init-external-ca.yaml), [reissue-apiserver.sh](reissue-apiserver.sh).
>
> **What the page gets wrong / leaves out (verified on kubeadm v1.37.2):**
> - The "Default CN" column is not what kubeadm generates: CA = `kubernetes` (not `kubernetes-ca`), front-proxy CA = `front-proxy-ca`
>   (not `kubernetes-front-proxy-ca`), etcd `server`/`peer` = the **node name** (not `kube-etcd`/`kube-etcd-peer`). Both work – only
>   the issuer chain, usages and SANs matter.
> - `kube-apiserver-kubelet-client` from kubeadm has **no O at all** (not `system:masters`, not `kubeadm:cluster-admins` as the note
>   says): kubeadm binds the *user* with ClusterRoleBinding `kubeadm:apiserver-kubelet-client` → `system:kubelet-api-admin`.
> - **The apiserver SAN list misses the Service ClusterIP** (`10.96.0.1`). With exactly the page's SANs, every in-cluster client
>   (kindnet, CoreDNS…) fails `x509: certificate is valid for 172.30.0.3, not 10.96.0.1` and the node stays NotReady.
> - "Shared Certificates" (reuse `apiserver.crt` as the kubelet client cert) does **not** work with kubeadm's `apiserver.crt`: it has only
>   `serverAuth` → the kubelet rejects it (`x509: certificate specifies an incompatible key usage`, `kubectl logs` → "You must be logged
>   in"). A shared cert needs `serverAuth,clientAuth` **and** kubelet-API RBAC for its CN.
> - The kubelet's **serving** certificate (listed under "Server certificates") is not in `/etc/kubernetes/pki` and not from the cluster CA:
>   by default it is self-signed (`/var/lib/kubelet/pki/kubelet.crt`, issuer `cp1-ca@…`).
> - `kubelet.conf` from kubeadm doesn't embed a cert: `kubelet-finalize` rewrites it to `/var/lib/kubelet/pki/kubelet-client-current.pem`
>   (also when you supplied an embedded one).
> - Certificate paths table: the apiserver also uses `sa.key` (`--service-account-signing-key-file`), not only `sa.pub`.
> - Without the CA keys on the node ("external CA") kube-controller-manager runs with `--cluster-signing-cert-file=` empty → the CSR
>   signer is skipped: approved CSRs never get a certificate, kubelet client certs can't rotate, `kubeadm certs renew` refuses.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| 3 CAs | `ca` (cluster), `etcd/ca` (etcd only), `front-proxy-ca` (aggregation layer); + the `sa.key`/`sa.pub` pair (not a cert) |
| Server certs | apiserver, etcd server/peer, kubelet serving, (front-proxy) |
| Client certs | apiserver→etcd, apiserver→kubelet, kcm, scheduler, kubelet, kube-proxy, admins, front-proxy-client |
| kind → key usage | server = digitalSignature, keyEncipherment, **serverAuth**; client = same + **clientAuth** |
| Identity | client cert **CN = user**, **O = groups** (`system:nodes`, `system:masters`, `kubeadm:cluster-admins`) |
| `system:masters` | break-glass group that bypasses RBAC – kubeadm keeps it only in `super-admin.conf` (init node only) |
| Single root CA | give kubeadm the CA cert+key, it makes the rest |
| All certificates / external CA | give kubeadm every cert + kubeconfig but no CA key – the CA key stays offline |

## The lab setup

```
 laptop ── docker network kubeadm-lab-net 172.30.0.0/24
   ├── kadm-cp1  172.30.0.2   kubeadm cluster, kubeadm-made PKI          (Lab 1, 2)
   ├── kadm-cp2  172.30.0.3   kubeadm init on a hand-made PKI, no CA keys (Lab 3, 4)
   │      /root/pki-out        "offline CA side" (CA keys) – would be another machine in real life
   └── kadm-w1                 stopped for this lab (host inotify: max 3 kubelets)
```

## Step 0 – Machines
```bash
cd setup/best-practices/certificates
M=../../production-environment/tools/kubeadm/machines.sh
minikube stop                      # inotify: minikube + cp1 + cp2 is one kubelet too many ("too many open files" -> containerd CRI fails)
docker stop kadm-w1; docker start kadm-cp2
$M x cp2 'kubeadm reset -f; rm -rf /etc/kubernetes/* /etc/cni/net.d/*'
$M x cp2 "$(cat ../../production-environment/tools/kubeadm/prepare-runtime.sh)"
```

## Lab 1 – What kubeadm generated (compare with the page's tables)
```bash
$M x cp1 "$(cat cert-report.sh)"
```
**Expected** (trimmed):
```
FILE                         | SUBJECT                           | ISSUER(CN)     | USAGE          | SANs
apiserver-etcd-client.crt    | /CN=kube-apiserver-etcd-client    | etcd-ca        | Client         |
apiserver-kubelet-client.crt | /CN=kube-apiserver-kubelet-client | kubernetes     | Client         |      <- no O
apiserver.crt                | /CN=kube-apiserver                | kubernetes     | Server         | cluster-endpoint, cp1, kubernetes, kubernetes.default,
                                                                                                    kubernetes.default.svc, …cluster.local, 10.96.0.1, 172.30.0.2
ca.crt                       | /CN=kubernetes                    | kubernetes     | CA             |      <- page: kubernetes-ca
etcd/healthcheck-client.crt  | /CN=kube-etcd-healthcheck-client  | etcd-ca        | Client         |
etcd/peer.crt                | /CN=cp1                           | etcd-ca        | Server, Client | cp1, localhost, 172.30.0.2, 127.0.0.1, ::1
etcd/server.crt              | /CN=cp1                           | etcd-ca        | Server, Client | (same)                 <- page: kube-etcd(-peer)
front-proxy-ca.crt           | /CN=front-proxy-ca                | front-proxy-ca | CA             |      <- page: kubernetes-front-proxy-ca
front-proxy-client.crt       | /CN=front-proxy-client            | front-proxy-ca | Client         |
keys without certs: sa.key sa.pub

admin.conf               user=kubernetes-admin                /O=kubeadm:cluster-admins/CN=kubernetes-admin
controller-manager.conf  user=system:kube-controller-manager  /CN=system:kube-controller-manager
kubelet.conf             user=system:node:cp1                 (file: /var/lib/kubelet/pki/kubelet-client-current.pem)
scheduler.conf           user=system:kube-scheduler           /CN=system:kube-scheduler
super-admin.conf         user=kubernetes-super-admin          /O=system:masters/CN=kubernetes-super-admin

== kubelet serving cert
subject=/CN=cp1@1795171887   issuer=/CN=cp1-ca@1795171887     <- self-signed, not from ca.crt

== flags that point at the files                               (every row of the "Certificate paths" table, plus:)
--service-account-signing-key-file=/etc/kubernetes/pki/sa.key  <- apiserver signs ServiceAccount tokens with sa.key
```
```bash
$M x cp1 'export KUBECONFIG=/etc/kubernetes/admin.conf
  kubectl get clusterrolebinding kubeadm:apiserver-kubelet-client kubeadm:cluster-admins -o wide
  kubeadm certs check-expiration'
#   kubeadm:apiserver-kubelet-client   ClusterRole/system:kubelet-api-admin   user  kube-apiserver-kubelet-client
#   kubeadm:cluster-admins             ClusterRole/cluster-admin              group kubeadm:cluster-admins
#   … certs 364d, CAs 9y, EXTERNALLY MANAGED no
```

## Lab 2 – The apiserver's kubelet client certificate: separate vs shared
"Separate" is what kubeadm does (`apiserver-kubelet-client.crt`). Try "shared" with kubeadm's own `apiserver.crt`:
```bash
$M x cp1 'cp /etc/kubernetes/manifests/kube-apiserver.yaml /root/kube-apiserver.yaml.orig
  sed -i "s|--kubelet-client-certificate=.*|--kubelet-client-certificate=/etc/kubernetes/pki/apiserver.crt|;
          s|--kubelet-client-key=.*|--kubelet-client-key=/etc/kubernetes/pki/apiserver.key|" /etc/kubernetes/manifests/kube-apiserver.yaml
  sleep 30; kubectl --kubeconfig /etc/kubernetes/admin.conf -n kube-system logs etcd-cp1 --tail=1
  journalctl -u kubelet --since -1min | grep x509'
```
**Expected**
```
error: You must be logged in to the server (the server has asked for the client to provide credentials ( pods/log etcd-cp1))
kubelet: "Unable to authenticate the request due to an error" err="verifying certificate … failed: x509: certificate specifies an incompatible key usage"
```
`apiserver.crt` is a **server** cert (EKU serverAuth only). A cert that is really shared needs both usages and RBAC for its CN:
```bash
$M x cp1 "$(cat shared-apiserver-cert.sh)"
#   subject=CN = kube-apiserver
#   X509v3 Extended Key Usage: TLS Web Server Authentication, TLS Web Client Authentication
#   clusterrolebinding …/lab:apiserver-shared-kubelet-client created   (user kube-apiserver -> system:kubelet-api-admin)
#   --kubelet-client-certificate=…/apiserver-shared.crt   --tls-cert-file=…/apiserver-shared.crt
#   {"level":"info",…}                                                  <- kubectl logs works again
$M x cp1 "MODE=undo; $(cat shared-apiserver-cert.sh)"                  # back to kubeadm's files
```
> Deleting the ClusterRoleBinding right away does not break `kubectl logs` at once: the kubelet caches allowed SubjectAccessReviews
> (`authorization.webhook.cacheAuthorizedTTL`, 5 min).

## Lab 3 – "All certificates": a PKI from the page's tables, CA keys kept off the node
```bash
$M x cp2 "HOST_NAME=cp2 HOST_IP=172.30.0.3; $(cat gen-all-certs.sh)"
#   /root/pki-out/etc-kubernetes/admin.conf … super-admin.conf, pki/… (24 files – the page's two path lists minus the 3 CA .key)
docker cp kubeadm-init-external-ca.yaml kadm-cp2:/root/
$M x cp2 'cp -r /root/pki-out/etc-kubernetes/* /etc/kubernetes/; kubeadm init --config kubeadm-init-external-ca.yaml'
#   [certs] Using existing … (every cert)   [kubeconfig] Using existing kubeconfig file …
#   [kubelet-finalize] Updating "/etc/kubernetes/kubelet.conf" to point to a rotatable kubelet client certificate and key
#   Your Kubernetes control-plane has initialized successfully!
docker cp ../../production-environment/tools/kubeadm/kindnet.yaml kadm-cp2:/root/
$M x cp2 'export KUBECONFIG=/etc/kubernetes/admin.conf; kubectl apply -f kindnet.yaml; sleep 60
  kubectl get nodes; kubectl -n kube-system logs -l app=kindnet --tail=1'
```
**Expected** – the page's SAN list is not enough:
```
cp2    NotReady   control-plane
"Failed to watch" err="… Get \"https://10.96.0.1:443/api/v1/nodes…\": tls: failed to verify certificate:
                        x509: certificate is valid for 172.30.0.3, not 10.96.0.1"
```
Pods reach the API through the `kubernetes` Service (`KUBERNETES_SERVICE_HOST=10.96.0.1`) – kubeadm always adds that IP. Re-sign on
the CA side and copy only the new cert in (the node still never sees `ca.key`):
```bash
$M x cp2 "HOST_NAME=cp2 HOST_IP=172.30.0.3; $(cat reissue-apiserver.sh)"
#   DNS:cp2, IP Address:172.30.0.3, DNS:kubernetes, … DNS:kubernetes.default.svc.cluster.local, IP Address:10.96.0.1
$M x cp2 'KUBECONFIG=/etc/kubernetes/admin.conf kubectl get nodes,pods -A'
#   cp2 Ready; coredns ×2, etcd, kindnet, kube-apiserver, kcm, kube-proxy, scheduler Running
$M x cp2 "$(cat cert-report.sh)" | head -12
#   ca.crt CN=kubernetes-ca · etcd/server.crt CN=kube-etcd · etcd/peer.crt CN=kube-etcd-peer · front-proxy-ca CN=kubernetes-front-proxy-ca
#   apiserver-kubelet-client.crt /O=system:masters/CN=kube-apiserver-kubelet-client      <- exactly the page's tables
```

## Lab 4 – Living with an external CA (user accounts + what stops working)
```bash
$M x cp2 'export KUBECONFIG=/etc/kubernetes/admin.conf
  for k in admin super-admin; do kubectl --kubeconfig /etc/kubernetes/$k.conf auth whoami; done
  kubectl config get-contexts
  openssl x509 -in /var/lib/kubelet/pki/kubelet-client-current.pem -noout -subject -issuer -nameopt compat
  kubectl -n kube-system exec etcd-cp2 -- etcdctl --cacert /etc/kubernetes/pki/etcd/ca.crt \
     --cert /etc/kubernetes/pki/etcd/healthcheck-client.crt --key /etc/kubernetes/pki/etcd/healthcheck-client.key \
     --endpoints https://127.0.0.1:2379 endpoint health
  kubeadm certs check-expiration | grep -E "apiserver |^ca "
  grep cluster-signing /etc/kubernetes/manifests/kube-controller-manager.yaml
  kubeadm certs renew apiserver'
```
**Expected**
```
Username kubernetes-admin         Groups [kubeadm:cluster-admins system:authenticated]
Username kubernetes-super-admin   Groups [system:masters system:authenticated]
*  default-system   default-cluster   default-admin            <- names from the page's kubectl config commands
subject=/O=system:nodes/CN=system:node:cp2   issuer=/CN=kubernetes-ca   (our cert, moved out of kubelet.conf into the .pem)
https://127.0.0.1:2379 is healthy                                <- the etcdctl row of the Certificate paths table
apiserver  … ca  yes          ca … 9y  yes                       <- EXTERNALLY MANAGED
    - --cluster-signing-cert-file=
    - --cluster-signing-key-file=
Detected external ca, certificate for serving the Kubernetes API can't be renewed
```
No signer in the cluster → CSRs are approved but never issued:
```bash
$M x cp2 'export KUBECONFIG=/etc/kubernetes/admin.conf; cd /root
  openssl req -new -newkey rsa:2048 -nodes -keyout jane.key -subj "/CN=jane" -out jane.csr
  printf "apiVersion: certificates.k8s.io/v1\nkind: CertificateSigningRequest\nmetadata: {name: jane}\nspec:\n  request: %s\n  signerName: kubernetes.io/kube-apiserver-client\n  usages: [client auth]\n" "$(base64 -w0 jane.csr)" | kubectl apply -f -
  kubectl certificate approve jane; sleep 10; kubectl get csr jane
  kubectl get csr jane -o jsonpath={.status.certificate} | wc -c
  kubectl -n kube-system logs kube-controller-manager-cp2 | grep -i "csr signer"'
#   jane   kubernetes.io/kube-apiserver-client   kubernetes-admin   Approved        (never Approved,Issued)
#   0
#   "Skipping CSR signer controller because no csr cert/key was specified"
```
So with an external CA you also sign kubelet client renewals, new nodes' certs (TLS bootstrap needs the signer) and every
renewal yourself – the price of keeping the CA key off the cluster.

## Useful commands
```bash
openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -subject -issuer -ext subjectAltName,keyUsage,extendedKeyUsage
echo | openssl s_client -connect 172.30.0.3:6443 2>/dev/null | openssl x509 -noout -ext subjectAltName   # what is served
grep client-certificate-data /etc/kubernetes/admin.conf | awk '{print $2}' | base64 -d | openssl x509 -noout -subject
openssl verify -CAfile /etc/kubernetes/pki/etcd/ca.crt /etc/kubernetes/pki/etcd/server.crt
kubeadm certs check-expiration
kubectl auth whoami
```

## Cleanup
```bash
./cleanup.sh            # cp1 back to kubeadm's certs, kubeadm reset + stop cp2, minikube start
# all kubeadm lab machines, volumes and the network:  ../../production-environment/tools/kubeadm/machines.sh down
```
