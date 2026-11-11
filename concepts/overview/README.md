# Overview (What is Kubernetes?) – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/overview/

> Sub-pages: [components](components/), [working-with-objects](working-with-objects/) (and its 10 sub-pages), [kubernetes-api](kubernetes-api/), [kubectl](kubectl/).
> This lab is a quick tour. One small app shows each item in the docs' list "Kubernetes provides you with…", and later sections cover each one in depth.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Kubernetes / K8s** | Greek for helmsman. A portable, extensible platform for containerized workloads, built on declarative configuration and automation. Open-sourced by Google in 2014. |
| **Deployment eras** | Physical servers had no resource boundaries. **VMs** each run a full OS on virtual hardware. **Containers** share the host **kernel**, but each has its own filesystem, CPU and memory share, and process space. They are lighter and portable. |
| **What it gives you** | Service discovery and load balancing, storage orchestration, automated rollouts and rollbacks, automatic bin packing, self-healing, secret and configuration management, batch execution, horizontal scaling, IPv4/IPv6 dual-stack, extensibility. |
| **What it is not** | Not a full PaaS. It doesn't build your code or provide CI/CD, middleware or databases. It doesn't dictate logging, monitoring or a config language. It doesn't manage machines. Those pieces are optional and pluggable. |
| **Not orchestration** | It doesn't run a fixed workflow (A, then B, then C). Independent control loops keep driving **current state → desired state**, and it doesn't matter how you get there. |

## The demo app
[00-shop.yaml](00-shop.yaml) creates namespace `overview-demo` with ConfigMap, Secret, PVC, Deployment `shop` (3× agnhost, which answers `/hostname`) and Service `shop`.
Extra files: [01-storage-pod.yaml](01-storage-pod.yaml), [02-too-big.yaml](02-too-big.yaml), [03-batch-job.yaml](03-batch-job.yaml), [04-crd.yaml](04-crd.yaml).

---

## Step 1
```bash
cd concepts/overview
kubectl apply -f 00-shop.yaml
kubectl wait --for=condition=Available deploy/shop -n overview-demo --timeout=150s
```

## Lab 1 – Service discovery and load balancing
```bash
kubectl run c -n overview-demo --restart=Never --image=busybox:1.36 -- \
  sh -c 'for i in $(seq 12); do wget -qO- http://shop/hostname; echo; done'
kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/c -n overview-demo ; kubectl logs c -n overview-demo | sort | uniq -c
kubectl delete pod c -n overview-demo
```
Expected: the requests to the DNS name `shop` are **spread over the shop pods**. kube-proxy picks a backend at random, so the counts vary. Details in `../services-networking/service`.

## Lab 2 – Storage orchestration
```bash
kubectl get pvc shop-data -n overview-demo        # Bound, STORAGECLASS standard - a volume was provisioned for you
kubectl apply -f 01-storage-pod.yaml ; sleep 5 ; kubectl logs writer -n overview-demo
kubectl delete pod writer -n overview-demo ; kubectl apply -f 01-storage-pod.yaml ; sleep 5 ; kubectl logs writer -n overview-demo   # 2 lines - data outlived the pod
```

## Lab 3 – Automated rollouts and rollbacks
```bash
kubectl set image deploy/shop shop=registry.k8s.io/e2e-test-images/agnhost:does-not-exist -n overview-demo
kubectl annotate deploy/shop -n overview-demo kubernetes.io/change-cause="v2: broken image" --overwrite
kubectl rollout status deploy/shop -n overview-demo --timeout=30s     # times out - new pods never become Ready
kubectl get pods -n overview-demo -l app=shop                         # 3 old pods still serve (ImagePullBackOff on the new one)
kubectl rollout history deploy/shop -n overview-demo
kubectl rollout undo deploy/shop -n overview-demo                     # rollback
kubectl rollout status deploy/shop -n overview-demo
```

## Lab 4 – Automatic bin packing
```bash
kubectl get pod -n overview-demo -l app=shop -o jsonpath='{.items[0].spec.containers[0].resources}{"\n"}'   # requests cpu 50m, memory 32Mi
kubectl describe node minikube | sed -n '/Allocated resources/,/Events/p'
kubectl apply -f 02-too-big.yaml ; sleep 3
kubectl get pod too-big -n overview-demo -o jsonpath='{.status.conditions[0].message}{"\n"}'
#   0/1 nodes are available: 1 Insufficient cpu.        <- the scheduler fits pods by their requests
```

## Lab 5 – Self-healing
```bash
kubectl delete pod -n overview-demo -l app=shop --wait=false ; kubectl get pods -n overview-demo -l app=shop -w   # replaced at once
P=$(kubectl get pod -n overview-demo -l app=shop -o name | head -1)
kubectl exec -n overview-demo $P -- sh -c 'kill 1'                       # crash the container -> "command terminated with exit code 137"
kubectl get $P -n overview-demo                                            # RESTARTS 1 - the kubelet restarted it
```
Readiness keeps traffic away from pods that aren't ready, which is "doesn't advertise them to clients until they are ready to serve". See `../workloads/pods/probes`.

## Lab 6 – Secret and configuration management
```bash
kubectl exec deploy/shop -n overview-demo -- sh -c 'echo "$GREETING / $DB_PASSWORD"'
#   welcome to the shop / not-in-the-image
kubectl create configmap shop-config -n overview-demo --from-literal=GREETING="black friday sale" --dry-run=client -o yaml | kubectl apply -f -
kubectl rollout restart deploy/shop -n overview-demo ; kubectl rollout status deploy/shop -n overview-demo
kubectl exec deploy/shop -n overview-demo -- sh -c 'echo "$GREETING"'     # new config, same image - nothing rebuilt
```

## Lab 7 – Batch execution
```bash
kubectl apply -f 03-batch-job.yaml
kubectl wait --for=condition=Complete job/report -n overview-demo --timeout=150s
kubectl get job report -n overview-demo -o jsonpath='succeeded={.status.succeeded} failed={.status.failed}{"\n"}'
#   succeeded=3 failed=<some>     <- failed containers were replaced until 3 succeeded
```

## Lab 8 – Horizontal scaling
```bash
kubectl scale deploy/shop -n overview-demo --replicas=5 ; kubectl get deploy shop -n overview-demo
kubectl autoscale deploy/shop -n overview-demo --cpu-percent=50 --min=2 --max=6      # automatic, needs metrics-server
kubectl get hpa -n overview-demo
```

## Lab 9 – IPv4/IPv6 dual-stack
```bash
kubectl get pod -n overview-demo -l app=shop -o jsonpath='{.items[0].status.podIPs}{"\n"}'     # [{"ip":"10.244.0.x"}] - IPv4 only on default minikube
kubectl get svc shop -n overview-demo -o jsonpath='{.spec.ipFamilies} {.spec.ipFamilyPolicy}{"\n"}'   # ["IPv4"] SingleStack
```
Dual-stack has to be enabled when the cluster is created. See `../services-networking/dual-stack`.

## Lab 10 – Designed for extensibility
```bash
kubectl apply -f 04-crd.yaml ; kubectl wait --for=condition=Established crd/coupons.shop.example.com
echo '{"apiVersion":"shop.example.com/v1","kind":"Coupon","metadata":{"name":"bf","namespace":"overview-demo"},"spec":{"code":"BLACKFRIDAY","percentOff":95}}' | kubectl apply -f -
#   The Coupon "bf" is invalid: spec.percentOff: Invalid value: 95: ... should be less than or equal to 90
kubectl get coupons -n overview-demo        # a brand-new API type with validation, no Kubernetes code changed
```

## Lab 11 – Containers vs VMs: one shared kernel
```bash
kubectl exec deploy/shop -n overview-demo -- uname -r ; minikube ssh -- uname -r ; uname -r
#   7.0.0-38-generic ×3 - the container, the minikube "node" and your laptop share ONE kernel
kubectl exec deploy/shop -n overview-demo -- sh -c 'cat /proc/1/cmdline | tr "\0" " "; echo'   # but its own process space: PID 1 is "/agnhost netexec ..."
```
A VM would show its **own** kernel version. Containers are lighter because they share the kernel.

---

## Useful commands
```bash
kubectl get all -n overview-demo
kubectl explain deployment.spec.strategy
kubectl rollout history|undo|status deploy/<name>
```

## Cleanup
```bash
./cleanup.sh
```
