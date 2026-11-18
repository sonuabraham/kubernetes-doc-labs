# Extend Service IP Ranges – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/network/extend-service-ip-ranges/

> Needs the docs' tiny Service range `10.96.0.0/28`, so it runs on a **throwaway profile `svc-lab`** ([svc-lab.sh](svc-lab.sh) `start`/`delete`;
> the next lab, [reconfigure-default-service-ip-ranges](../reconfigure-default-service-ip-ranges/), uses the same profile).
> Files (docs, **verbatim**): [vap-servicecidr-default.yaml](vap-servicecidr-default.yaml), [vap-servicecidr-deny.yaml](vap-servicecidr-deny.yaml).
>
> **Differences from the page:** the cluster DNS Service already holds `10.96.0.10`, so only **12** test Services fit (the page counts 13;
> `test-13` is the one that fails). A ServiceCIDR waiting for its IPs shows `reason: Terminating` (page: `OrphanIPAddress`).

## Key ideas (read first)

| Object | Meaning |
|---|---|
| ServiceCIDR `kubernetes` | created by kube-apiserver from `--service-cluster-ip-range`; finalizer `networking.k8s.io/service-cidr-finalizer` |
| Extra ServiceCIDRs | add ranges at runtime, no apiserver restart; may overlap the default one (`10.96.0.0/24` ⊃ `/28`) |
| IPAddress | one object per allocated ClusterIP, `parentRef` = the Service |
| Deleting a ServiceCIDR | stays `Terminating` while IPAddresses inside it exist (and no other CIDR covers them) |
| ValidatingAdmissionPolicy | restrict which ranges may be added, or forbid changes completely |

---

## Lab 1 – The default range (docs)
```bash
cd tasks/network/extend-service-ip-ranges
./svc-lab.sh start                                  # minikube --service-cluster-ip-range=10.96.0.0/28
kubectl get servicecidr                             # kubernetes   10.96.0.0/28
kubectl get service kubernetes                      # ClusterIP 10.96.0.1
kubectl get ipaddress
#   10.96.0.1    services/default/kubernetes
#   10.96.0.10   services/kube-system/kube-dns      <- one IP fewer than the page assumes
kubectl get servicecidr kubernetes -o jsonpath='{.metadata.finalizers}'      # ["networking.k8s.io/service-cidr-finalizer"]
```

## Lab 2 – Full range, extend it, delete the extension (docs)
```bash
for i in $(seq 1 13); do kubectl create service clusterip "test-$i" --tcp 80 -o json | jq -r .spec.clusterIP; done
#   10.96.0.6 … (12 addresses)
#   error: failed to create ClusterIP service: Internal error occurred: failed to allocate a serviceIP for Service "test-13": range is full
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: ServiceCIDR
metadata:
  name: newcidr1
spec:
  cidrs:
  - 10.96.0.0/24
EOF
for i in $(seq 13 16); do kubectl create service clusterip "test-$i" --tcp 80 -o json | jq -r .spec.clusterIP; done
#   10.96.0.250  10.96.0.115  10.96.0.21  10.96.0.37         <- from the new range
kubectl delete servicecidr newcidr1 --wait=false
kubectl get servicecidr newcidr1 -o yaml | sed -n '/finalizers/,$p'
#   finalizers: [networking.k8s.io/service-cidr-finalizer]
#   status.conditions: Ready False  reason: Terminating
#     message: There are still IPAddresses referencing the ServiceCIDR, please remove them or create a new ServiceCIDR
for i in $(seq 13 16); do kubectl delete service "test-$i" ; done
kubectl get servicecidr newcidr1                    # Error from server (NotFound)   <- finalizer released
```

## Lab 3 – Admission policies (docs)
```bash
kubectl apply -f vap-servicecidr-default.yaml       # allowed: 10.96.0.0/16, 2001:db8::/64
# ServiceCIDR ['10.96.1.0/24']                      → created
# ServiceCIDR ['2001:db8:0:0:ffff::/80','10.96.0.0/20'] → created
# ServiceCIDR ['172.20.0.0/16']                     → … denied request: failed expression: object.spec.cidrs.all(newCIDR, …)
kubectl delete servicecidr allowed-1 allowed-2; kubectl delete -f vap-servicecidr-default.yaml
kubectl apply -f vap-servicecidr-deny.yaml
# new ServiceCIDR                                   → … denied request: you can only create or update the default ServiceCIDR
kubectl label servicecidr kubernetes lab=x         # … denied request: you can not create or update ServiceCIDR objects   <- only system:apiserver may
kubectl delete -f vap-servicecidr-deny.yaml
```

## Cleanup
```bash
./cleanup.sh            # Services, ServiceCIDRs, policies on svc-lab
./svc-lab.sh delete     # after the next lab: deletes svc-lab, starts the default minikube
```
