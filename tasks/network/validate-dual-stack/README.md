# Validate IPv4/IPv6 dual-stack – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/network/validate-dual-stack/

> Needs a dual-stack cluster. **minikube v1.39 can't create one here.** Its certificate code rejects a dual `--service-cluster-ip-range`
> (`GUEST_CERT: … parsing default service cidr: invalid CIDR address: 10.96.0.0/12,fd00:10:96::/112`), and with Docker 29 a custom IPv6-enabled
> `--network` fails (`map has no entry for key "Gateway"`). So the lab uses a **throwaway profile `ds-lab`** ([ds-lab.sh](ds-lab.sh)): a normal
> IPv4 cluster whose kube-apiserver / kube-controller-manager then get a second, IPv6 Service range. That makes the **Service** half of the
> page fully testable. Node/Pod addressing stays IPv4-only and shows what is missing.
> Files (docs, **verbatim**): [dual-stack-default-svc.yaml](dual-stack-default-svc.yaml), [dual-stack-ipfamilies-ipv6.yaml](dual-stack-ipfamilies-ipv6.yaml),
> [dual-stack-preferred-svc.yaml](dual-stack-preferred-svc.yaml), [dual-stack-prefer-ipv6-lb-svc.yaml](dual-stack-prefer-ipv6-lb-svc.yaml).
> [pod01.yaml](pod01.yaml) = the page's `pod01` + its `MY_POD_IPS` env snippet (not a docs file).
> Concept background: [concepts/services-networking/dual-stack](../../../concepts/services-networking/dual-stack/).

## Key ideas (read first)

| What | Dual-stack needs |
|---|---|
| Services | two `--service-cluster-ip-range` entries (apiserver + controller-manager) → the default ServiceCIDR has both |
| Pods | two `--cluster-cidr` entries, nodes with **two podCIDRs**, a dual-stack CNI, IPv6 on the node network |
| Service traffic | kube-proxy in dual-stack mode (iptables **and** ip6tables rules) |
| `ipFamilyPolicy` | `SingleStack` (default) / `PreferDualStack` / `RequireDualStack`; `ipFamilies` order = primary family |

---

## Lab 1 – Service side (docs, all as documented)
```bash
cd tasks/network/validate-dual-stack
./ds-lab.sh start
#   --service-cluster-ip-range=10.96.0.0/12,fd00:10:96::/112
#   kubernetes   10.96.0.0/12,fd00:10:96::/112          <- default ServiceCIDR updated in place
for f in dual-stack-default-svc dual-stack-ipfamilies-ipv6 dual-stack-preferred-svc dual-stack-prefer-ipv6-lb-svc; do
  kubectl apply -f $f.yaml
  kubectl get svc my-service -o jsonpath='{.spec.ipFamilyPolicy} {.spec.ipFamilies} {.spec.clusterIPs} {.spec.type}{"\n"}'
  kubectl delete svc my-service; done
#   SingleStack     ["IPv4"]         ["10.100.240.7"]
#   SingleStack     ["IPv6"]         ["fd00:10:96::d131"]
#   PreferDualStack ["IPv4","IPv6"]  ["10.105.59.109","fd00:10:96::fdf"]
#   PreferDualStack ["IPv6","IPv4"]  ["fd00:10:96::1e78","10.102.6.204"]   LoadBalancer  EXTERNAL-IP <pending> (no cloud LB)
kubectl apply -f dual-stack-preferred-svc.yaml && kubectl describe svc -l app.kubernetes.io/name=MyApp | grep -E 'IP Family|^IPs?:'
#   IP Family Policy:  PreferDualStack
#   IP Families:       IPv4,IPv6
#   IP:                10.107.142.89
#   IPs:               10.107.142.89,fd00:10:96::5c41
#   (kubectl get svc shows only the primary IP, as the docs note)
kubectl delete svc my-service
# RequireDualStack (not from the docs): ["10.96.29.189","fd00:10:96::417"]
kubectl get svc kubernetes -o jsonpath='{.spec.ipFamilyPolicy} {.spec.clusterIPs}'     # SingleStack ["10.96.0.1"]   <- unchanged
```

## Lab 2 – Node and Pod side (docs commands; IPv4-only here)
```bash
kubectl get nodes ds-lab -o go-template --template='{{range .spec.podCIDRs}}{{printf "%s\n" .}}{{end}}'      # 10.244.0.0/24      (docs: + an IPv6 block)
kubectl get nodes ds-lab -o go-template --template='{{range .status.addresses}}{{printf "%s: %s\n" .type .address}}{{end}}'
#   InternalIP: 192.168.202.2   Hostname: ds-lab                                                             (docs: + an IPv6 InternalIP)
kubectl apply -f pod01.yaml
kubectl get pods pod01 -o go-template --template='{{range .status.podIPs}}{{printf "%s\n" .ip}}{{end}}'      # 10.244.0.2
kubectl exec pod01 -- sh -c 'set | grep MY_POD_IPS; tail -1 /etc/hosts'
#   MY_POD_IPS='10.244.0.2'      10.244.0.2  pod01       (on a dual-stack cluster: two IPs, comma separated / two hosts lines)
```
What a half-converted cluster looks like (not from the docs):
```bash
kubectl apply -f dual-stack-ipfamilies-ipv6.yaml
kubectl get endpointslices -l kubernetes.io/service-name=my-service -o custom-columns=FAMILY:.addressType,ENDPOINTS:.endpoints[*].addresses
#   IPv6   <none>                          <- pod01 matches the selector but has no IPv6 address
kubectl exec pod01 -- curl -s -m 3 -g "http://[$(kubectl get svc my-service -o jsonpath='{.spec.clusterIP}')]/"
#   Failed to connect to fd00:10:96::7a78 port 80 … Couldn't connect to server
minikube -p ds-lab ssh -- "sudo ip6tables-save | grep -c KUBE-SVC; sudo iptables-save | grep -c KUBE-SVC"     # 0 / 16
```
An IPv6 ClusterIP is only an allocation until the CNI, the nodes and kube-proxy are dual-stack too, which is the point the
[ServiceCIDR reconfiguration](../reconfigure-default-service-ip-ranges/) page makes about "single-to-dual-stack conversion".

## Cleanup
```bash
./cleanup.sh          # deletes ds-lab, starts the default minikube
```
