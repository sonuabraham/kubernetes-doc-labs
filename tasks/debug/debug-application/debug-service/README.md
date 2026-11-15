# Debug Services – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/debug/debug-application/debug-service/

> Runs the docs' walk-through on the default **minikube** cluster (`default` namespace, kube-proxy in iptables mode, kindnet).
> The docs' Deployment/Service are created with their `kubectl create/scale/expose` commands. The client is a long-running
> `busybox` Pod used with `kubectl exec`, instead of the docs' interactive `kubectl run -it --rm`.
> Not from the docs: [deny-hostnames.yaml](deny-hostnames.yaml) (the NetworkPolicy step), [hairpin.yaml](hairpin.yaml) (the edge case).

## The checklist (top to bottom)

```
Pods serve on their port?  ─►  Service exists?  ─►  NetworkPolicy?  ─►  DNS name resolves?  ─►  works by ClusterIP?
        ─►  Service spec right (port/targetPort/protocol/selector)?  ─►  EndpointSlices list the Pods?
        ─►  kube-proxy running, right mode, rules present?  ─►  hairpin
```

---

## Step 0 – Setup (docs)
```bash
cd tasks/debug/debug-application/debug-service
kubectl create deployment hostnames --image=registry.k8s.io/serve_hostname
kubectl scale deployment hostnames --replicas=3
kubectl run busybox --image=registry.k8s.io/busybox:1.27.2 --restart=Never -- sleep 3600     # our client
kubectl get pods -l app=hostnames
EPS=$(kubectl get pods -l app=hostnames -o go-template='{{range .items}}{{.status.podIP}}:9376 {{end}}')
kubectl exec busybox -- sh -c "for ep in $EPS; do wget -qO- \$ep; done"
#   hostnames-5fcff9db8f-c5pk4
#   hostnames-5fcff9db8f-gcvdw
#   hostnames-5fcff9db8f-kqvcs        <- the Pods work on their own
```

## Lab 1 – Does the Service exist?
```bash
kubectl exec busybox -- wget -O- hostnames
#   wget: bad address 'hostnames'          <- busybox's wording of "unable to resolve host address"
kubectl get svc hostnames                  # Error from server (NotFound)
kubectl expose deployment hostnames --port=80 --target-port=9376
kubectl get svc hostnames                  # hostnames  ClusterIP  10.102.32.40  <none>  80/TCP
```

## Lab 2 – Network Policy (the docs only mention it)
```bash
IP=$(kubectl get svc hostnames -o jsonpath='{.spec.clusterIP}')
kubectl apply -f deny-hostnames.yaml
kubectl exec busybox -- sh -c "time wget -qO- -T 3 $IP:80"
#   wget: download timed out   real 0m 3.00s     <- a policy DROPS: a timeout, not "connection refused"
kubectl delete -f deny-hostnames.yaml
```

## Lab 3 – DNS
```bash
for n in hostnames hostnames.default hostnames.default.svc.cluster.local kubernetes.default; do kubectl exec busybox -- nslookup $n | tail -2; done
#   Address 1: 10.102.32.40 hostnames.default.svc.cluster.local     (×3)
#   Address 1: 10.96.0.1 kubernetes.default.svc.cluster.local
kubectl exec busybox -- cat /etc/resolv.conf
#   search default.svc.cluster.local svc.cluster.local cluster.local
#   nameserver 10.96.0.10
#   options ndots:5
minikube ssh -- nslookup hostnames.default.svc.cluster.local 10.96.0.10      # from the node: Address: 10.102.32.40
```
On this cluster the DNS Service is `10.96.0.10`, not the docs' `10.0.0.10`. DNS problems in depth: [Debugging DNS Resolution](../../../administer-cluster/dns-debugging-resolution/).

## Lab 4 – By IP, the spec, the EndpointSlices
```bash
kubectl exec busybox -- sh -c "for i in 1 2 3 4 5 6; do wget -qO- $IP:80; done" | sort | uniq -c
#   2 hostnames-…-c5pk4   3 hostnames-…-gcvdw   1 hostnames-…-kqvcs      <- random spread over 3 Pods
kubectl get service hostnames -o json | jq -c '.spec|{ports, selector}'
#   {"ports":[{"port":80,"protocol":"TCP","targetPort":9376}],"selector":{"app":"hostnames"}}
kubectl get endpointslices -l kubernetes.io/service-name=hostnames
#   hostnames-r7z6w   IPv4   9376   10.244.0.24,10.244.0.25,10.244.0.23
```
For the broken versions (empty endpoints, wrong `targetPort`), see Lab 7 of [debug-pods](../debug-pods/).

## Lab 5 – kube-proxy
```bash
minikube ssh -- "ps auxw | grep [k]ube-proxy"
#   /usr/local/bin/kube-proxy --config=/var/lib/kube-proxy/config.conf --hostname-override=minikube
kubectl logs -n kube-system -l k8s-app=kube-proxy | grep Proxier
#   "Using iptables Proxier"
minikube ssh -- "sudo iptables-save | grep hostnames"
```
```
-A KUBE-SERVICES -d 10.102.32.40/32 -p tcp -m comment --comment "default/hostnames cluster IP" -m tcp --dport 80 -j KUBE-SVC-YN5D6RYVEVZOH44Q
-A KUBE-SVC-YN5D6RYVEVZOH44Q ! -s 10.244.0.0/16 -d 10.102.32.40/32 … -j KUBE-MARK-MASQ
-A KUBE-SVC-YN5D6RYVEVZOH44Q … "default/hostnames -> 10.244.0.23:9376" -m statistic --mode random --probability 0.33333333349 -j KUBE-SEP-22QRNCIBB7QROBBH
-A KUBE-SVC-YN5D6RYVEVZOH44Q … "default/hostnames -> 10.244.0.24:9376" -m statistic --mode random --probability 0.50000000000 -j KUBE-SEP-2QEPDCTBKMXTCBWU
-A KUBE-SVC-YN5D6RYVEVZOH44Q … "default/hostnames -> 10.244.0.25:9376" -j KUBE-SEP-GOKA4UC3JRBK7E3J
-A KUBE-SEP-22QRNCIBB7QROBBH -p tcp … -j DNAT --to-destination 10.244.0.23:9376      (+ one per endpoint)
```
One `KUBE-SERVICES` rule per Service port, one `KUBE-SVC-…` chain, and one `KUBE-SEP-…` per endpoint. The probabilities
1/3 → 1/2 → rest give an even spread.
```bash
minikube ssh -- curl -s $IP:80          # hostnames-…-kqvcs   <- the docs' "Is kube-proxy proxying?" from the node
```
The docs' `Setting endpoints for default/hostnames…` log lines don't appear at kube-proxy's default verbosity in 1.37.

## Lab 6 – A Pod reaching itself through its Service (hairpin)
```bash
kubectl apply -f hairpin.yaml               # Pod + Service, both called "selfcall"
SIP=$(kubectl get svc selfcall -o jsonpath='{.spec.clusterIP}')
kubectl exec selfcall -- wget -qO- $SIP                                 # selfcall   <- hairpin works
kubectl exec selfcall -- wget -qO- selfcall.default.svc.cluster.local   # selfcall
kubectl exec selfcall -- wget -qO- selfcall
#   wget: can't connect to remote host (10.244.0.27): Connection refused   <- NOT a hairpin problem:
kubectl exec selfcall -- tail -1 /etc/hosts
#   10.244.0.27  selfcall      <- the Pod's own hostname wins over the Service name; :80 on the Pod has no listener
kubectl get --raw /api/v1/nodes/minikube/proxy/configz | jq -r .kubeletconfig.hairpinMode      # hairpin-veth
```
This one looked exactly like the docs' edge case at first. Check `/etc/hosts` before blaming the network.
Never give a Pod the same name as the Service it calls.

## Useful commands
```bash
kubectl get svc,endpointslices -l app=<app>
kubectl exec <client> -- nslookup <svc>
minikube ssh -- "sudo iptables-save | grep <svc>"
kubectl get --raw /api/v1/nodes/minikube/proxy/configz | jq .kubeletconfig.hairpinMode
```

## Cleanup
```bash
./cleanup.sh
```
