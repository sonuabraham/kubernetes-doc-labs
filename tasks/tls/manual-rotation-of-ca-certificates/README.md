# Manual Rotation of CA Certificates – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/tls/manual-rotation-of-ca-certificates/

> Rewrites every certificate trust in the cluster, so it runs on a **throwaway profile `ca-lab`** (single API server: short outages at each
> API server restart, as the docs warn). [ca-rotation.sh](ca-rotation.sh) (not from the docs) runs **one docs step per call** with minikube's paths
> (`/var/lib/minikube/certs`, `/etc/kubernetes/*.conf`, `/var/lib/kubelet/config.yaml`). It uses its own kubeconfig `./kubeconfig-ca-lab` with the
> CA data embedded; your `~/.minikube` files are never modified. Old CA = minikube's `minikubeCA`, new CA = `new-ca` (plus `new-front-proxy-ca`).
>
> **Found (things the page doesn't say, each hit in this run):**
> 1. **The control plane's own kubeconfigs need the CA bundle before the API server switches certificate.** After step 9 (apiserver.crt from the new CA)
>    kube-scheduler and kube-controller-manager failed with `x509: certificate signed by unknown authority` (scheduling stopped, Pods got no events)
>    until `scheduler.conf` / `controller-manager.conf` trusted old + new. The page only mentions kubeconfigs for *user accounts* (step 7).
>    The script's phase `8-cp-kubeconfigs` does this.
> 2. **`admin.conf` / `super-admin.conf` also carry old-CA client certs.** After dropping the old CA, `kubeadm token create --kubeconfig admin.conf`
>    failed. They need re-issuing (`kubeadm kubeconfig user …`) together with the scheduler/controller-manager ones.
> 3. The docs' annotate loop sets `ca-rotation: "1"`. Running it a **second** time (after the final step) changes nothing, so no Pod restarts.
>    Use a new value, e.g. a timestamp, or `kubectl rollout restart`.
> 4. "ServiceAccount … Secrets that include both CAs" is pre-1.24 wording: today the CA reaches Pods through the **`kube-root-ca.crt` ConfigMap**
>    in every namespace, which kube-controller-manager publishes from `--root-ca-file`.
> 5. On kubeadm/minikube, kube-scheduler has **no `--client-ca-file`** (it reads the CA from `kube-system/extension-apiserver-authentication`) and
>    kube-apiserver has no `--kubelet-certificate-authority`, so those parts of steps 5–6 don't apply.
> 6. Lab gotcha: with `KUBECONFIG` pointing at the lab file, `minikube start/stop` writes contexts **there**. The script now clears `KUBECONFIG` for minikube itself.

## Key ideas (read first)

| Trust direction | Where the CA lives | Changed in phase |
|---|---|---|
| Pods → API server | `kube-root-ca.crt` ConfigMap (from KCM `--root-ca-file`) | 2 (bundle), 12 (new only) |
| clients → API server (client certs) | apiserver `--client-ca-file` | 5 (bundle), 12 (new) |
| aggregator → extension servers | apiserver `--requestheader-client-ca-file` (front-proxy CA) | 5, 12 |
| control plane / users → API server (server cert) | `certificate-authority-data` in each kubeconfig | 7, **8**, 9a, 12 |
| API server → kubelet (client cert) | kubelet `clientCAFile` | 9a (bundle), 12 (new) |
| new certificates for the API server | `apiserver.crt`, `apiserver-kubelet-client.crt`, `front-proxy-client.crt` | 9b |
| CSR signing (kubelet certs, CSR API) | KCM `--cluster-signing-cert-file` (can't be a bundle) | 12 (ca.crt := new CA) |

---

## Lab – Phase by phase
```bash
cd tasks/tls/manual-rotation-of-ca-certificates
export KUBECONFIG=$PWD/kubeconfig-ca-lab      # what the script uses as well
./ca-rotation.sh start                         # stops minikube, starts ca-lab, writes ./kubeconfig-ca-lab
./ca-rotation.sh backup                        # docs caution: /root/ca-backup/{certs, kubernetes, config.yaml} on the node
./ca-rotation.sh 1-new-ca                      # step 1: new-ca, new-front-proxy-ca, ca-bundle.crt, front-proxy-ca-bundle.crt
./ca-rotation.sh 2-kcm-bundle                  # steps 2-3: --root-ca-file=ca-bundle.crt
#   kube-root-ca.crt now has 2 certificates
./ca-rotation.sh 4-restart-pods                # step 4 + the docs' annotate loop (coredns, kindnet, kube-proxy)
kubectl -n kube-system exec ds/kube-proxy -- sh -c 'grep -c BEGIN /var/run/secrets/kubernetes.io/serviceaccount/ca.crt'   # 2
./ca-rotation.sh 5-apiserver-bundle            # step 5: --client-ca-file / --requestheader-client-ca-file = bundles
./ca-rotation.sh 7-user-cert                   # step 7: admin cert from the NEW CA + bundle in the lab kubeconfig
#   Username minikube-user   Groups [system:masters system:authenticated]      <- new-CA client cert accepted
./ca-rotation.sh 8-cp-kubeconfigs              # Found #1: controller-manager/scheduler/admin/super-admin .conf trust the bundle
./ca-rotation.sh 9a-kubelet-bundle             # step 9: clientCAFile + kubelet.conf CA = bundle; kubelet restart
./ca-rotation.sh 9b-new-serving-certs          # step 9: apiserver.crt (same SANs), apiserver-kubelet-client.crt, front-proxy-client.crt
#   issuer=CN=new-ca                            <- what the API server presents now
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=1    # works: kubelet trusts the new apiserver-kubelet-client cert
./ca-rotation.sh 10-cluster-info               # step 10: kube-public/cluster-info gets the bundle
./ca-rotation.sh 11-verify                     # step 11: nodes, kube-system Pods, a test Pod, TLS errors
```
Without phase 8 (what happened first in this run):
```
kube-scheduler:          "Failed to watch" … tls: failed to verify certificate: x509: certificate signed by unknown authority
kube-controller-manager: "Failed to watch" … x509: certificate signed by unknown authority
kubectl run ca-check …   → no events at all, Pod never scheduled
```
```bash
./ca-rotation.sh 12-drop-old-ca                # step 12: ca.crt/ca.key := new CA, re-issue control-plane kubeconfigs (incl. admin, Found #2),
                                               # flags back to ca.crt, kubelet clientCAFile = new, kubelet TLS-bootstraps a new client cert
#   kube-root-ca.crt: subject=CN=new-ca
kubectl get csr        # csr-…   kube-apiserver-client-kubelet   system:bootstrap:4q55gr   Approved,Issued   <- kubelet's new cert, new CA
curl -sk --cert ~/.minikube/profiles/ca-lab/client.crt --key ~/.minikube/profiles/ca-lab/client.key https://$(minikube -p ca-lab ip):8443/api -o /dev/null -w '%{http_code}'
#   401                                                                   <- minikube's original (old-CA) client cert is now rejected
kubectl -n kube-system logs kube-apiserver-ca-lab --since=30s | grep -c x509     # 0   (errors only during the switch-over)
```
Step 4 again at the end needs a **new** annotation value (Found #3), e.g.
`kubectl -n kube-system rollout restart deploy/coredns ds/kube-proxy ds/kindnet`.

## Cleanup
```bash
unset KUBECONFIG
./cleanup.sh            # = ./ca-rotation.sh delete: deletes ca-lab, work/, the lab kubeconfig, starts the default minikube
```
