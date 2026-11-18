# Kubernetes Default ServiceCIDR Reconfiguration – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/network/reconfigure-default-service-ip-ranges/

> The page explains the categories and lists 7 "illustrative reconfiguration steps" without commands. This lab **does** them: it replaces the
> default range `10.96.0.0/28` with the non-overlapping `10.100.0.0/24` on the throwaway profile `svc-lab`
> ([../extend-service-ip-ranges/svc-lab.sh](../extend-service-ip-ranges/svc-lab.sh)). [reconfigure.sh](reconfigure.sh) (not from the docs) has one phase per step.
>
> **Found (needed, but not among the page's steps):**
> 1. **The API server certificate must get the new `kubernetes.default` IP.** After step 7 every in-cluster client that connects by IP
>    (client-go uses `KUBERNETES_SERVICE_HOST`) fails: CoreDNS logged `tls: failed to verify certificate: x509: certificate is valid for 10.96.0.1 …`, and curl
>    `SSL: no alternative certificate subject name matches target ipv4 address '10.100.0.1'`. Phase `8-apiserver-cert` re-issues it with kubeadm.
> 2. **The DNS Service has a fixed IP baked into every kubelet** (`clusterDNS: 10.96.0.10`). Recreating kube-dns in the new range also means changing the
>    kubelet config (+ restart), and Pods created earlier keep the old nameserver until they are recreated (they failed lookups in this run).
> 3. After the old `kubernetes` ServiceCIDR disappears, kube-apiserver **recreates** a `kubernetes` ServiceCIDR from its new flag on its own
>    (`"Creating default ServiceCIDR" CIDRs=["10.100.0.0/24"]`, ~20 s later). The temporary `migration` object can be deleted afterwards.

## Key ideas (read first)

| Step | What happens |
|---|---|
| 3 new ServiceCIDR | a temporary target range (`migration`, 10.100.0.0/24) |
| 4 delete the default one | stays `Terminating` while IPs are in it; **no new allocations** from it |
| 5 recreate Services | new ClusterIPs from the new range (clients must re-resolve; DNS needs extra care, Found #2) |
| 6 restart kube-apiserver | `--service-cluster-ip-range` = new range (kube-controller-manager too) |
| 7 delete `kubernetes.default` | apiserver recreates it as the first IP of the new range (10.100.0.1) |

---

## Lab
```bash
cd tasks/network/reconfigure-default-service-ip-ranges
../extend-service-ip-ranges/svc-lab.sh start            # step 1: kube-apiserver with 10.96.0.0/28
./reconfigure.sh 2-services                              # step 2: web (10.96.0.8) next to kubernetes (10.96.0.1) and kube-dns (10.96.0.10)
./reconfigure.sh 3-new-cidr                              # step 3: ServiceCIDR migration 10.100.0.0/24
./reconfigure.sh 4-delete-default                        # step 4: 2026-11-18T12:08:23Z Terminating
kubectl create service clusterip probe --tcp 80 -o jsonpath='{.spec.clusterIP}'      # 10.100.0.186   <- already from the new range
./reconfigure.sh 5-recreate                              # step 5: web → 10.100.0.106; kube-dns → 10.100.0.10 + kubelet clusterDNS (Found #2)
kubectl run dnstest --image=busybox:1.36 --restart=Never --command -- sh -c 'grep nameserver /etc/resolv.conf; wget -qO- -T 3 http://web'
#   nameserver 10.100.0.10   …   <title>Welcome to nginx!</title>        <- new Pod
kubectl exec deploy/web -- sh -c 'grep nameserver /etc/resolv.conf; getent hosts web.default.svc.cluster.local || echo "lookup failed"'
#   nameserver 10.96.0.10   lookup failed                               <- Pod from before step 5
./reconfigure.sh 6-apiserver                             # step 6: --service-cluster-ip-range=10.100.0.0/24 (apiserver + controller-manager)
./reconfigure.sh 7-kubernetes-svc                        # step 7: kubernetes   ClusterIP   10.100.0.1
kubectl get servicecidr
#   kubernetes   10.100.0.0/24   2s        <- recreated by the apiserver (Found #3)
#   migration    10.100.0.0/24
kubectl run apitest --image=curlimages/curl:8.11.1 --restart=Never --command -- sh -c \
  'S=/var/run/secrets/kubernetes.io/serviceaccount; curl -s -o /dev/null -w "%{errormsg}\n" --cacert $S/ca.crt https://$KUBERNETES_SERVICE_HOST/version'
#   SSL: no alternative certificate subject name matches target ipv4 address '10.100.0.1'      (Found #1)
kubectl -n kube-system rollout restart deploy/coredns   # new CoreDNS: … x509: certificate is valid for … 10.96.0.1 …
./reconfigure.sh 8-apiserver-cert                        # kubeadm init phase certs apiserver with serviceSubnet 10.100.0.0/24
#   … IP Address:10.100.0.1, IP Address:192.168.202.2, IP Address:127.0.0.1
#   (apitest again)  https://10.100.0.1: 200    https://kubernetes.default.svc: 200
./reconfigure.sh check
#   kubernetes   ClusterIP   10.100.0.1     /   web   10.100.0.106   /   kube-dns   10.100.0.10
#   IPAddress objects only in 10.100.0.0/24
```
Not shown (single node, single stack): other CNIs / service meshes that store the Service range, and dual-stack conversions.

## Cleanup
```bash
./cleanup.sh          # deletes svc-lab, starts the default minikube
```
