# Kubernetes API Server Bypass Risks – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/security/api-server-bypass-risks/

> Authentication, RBAC, admission (Pod Security!) and auditing all live in the **API server**. This lab uses the four side doors from the page on the minikube node, showing in each case what the API server never sees. [01-static-privileged.yaml](01-static-privileged.yaml) is the only manifest.

## Key ideas (read first)

| Side door | What it allows | Mitigations (from the page) |
|---|---|---|
| **Static Pods** | Anyone who can write the kubelet's manifest directory (or URL) runs Pods **without admission**. Mirror Pods may be rejected, but the containers still run. | Restrict file access to the dir, `staticPodPath` only where needed, don't use static Pods for user workloads, admission rules for mirror Pods… |
| **kubelet API** (`:10250`) | Pods, logs, exec, configz — authorized by the kubelet via the API server's SubjectAccessReview (Webhook mode), but **not admitted** | `authentication.anonymous.enabled: false`, `authorization.mode: Webhook`, restrict `nodes/proxy` RBAC, firewall the port |
| **etcd API** | Full read/write of every object, bypassing **everything** | mTLS with a dedicated CA, firewall etcd to the API servers, encryption at rest, protect backups |
| **Container runtime socket** | Run containers the cluster doesn't know about, inspect or alter any container | Restrict socket access (root only), no `hostPath` mounts of it, PSS Baseline+, separate runtime namespaces |

---

## Lab 1 – Static Pod vs Pod Security
```bash
cd concepts/security/api-server-bypass-risks
kubectl create ns bypass-demo ; kubectl label ns bypass-demo pod-security.kubernetes.io/enforce=restricted
kubectl apply -f 01-static-privileged.yaml
#   Forbidden: violates PodSecurity "restricted:latest" ...         <- the front door is closed
minikube cp 01-static-privileged.yaml /etc/kubernetes/manifests/sneaky-static.yaml     # the side door
minikube ssh -- "sudo crictl pods --name sneaky-static"
#   18c37854e3545  Ready  sneaky-static-minikube  bypass-demo       <- RUNNING: privileged + hostPID
kubectl get pods -n bypass-demo                                      # No resources found
minikube ssh -- "sudo journalctl -u kubelet --since '-1 min' | grep -i 'mirror pod'"
#   "Failed creating a mirror pod" err="pods \"sneaky-static-minikube\" is forbidden: violates PodSecurity \"restricted:latest\": host namespaces (hostPID=true), privileged ..."
minikube ssh -- "sudo rm /etc/kubernetes/manifests/sneaky-static.yaml"
```
Admission rejected only the **mirror** (the API object). The containers kept running, invisible to `kubectl get pods`.

## Lab 2 – The kubelet API
```bash
minikube ssh -- "curl -sk -o /dev/null -w '%{http_code}\n' https://127.0.0.1:10250/pods"        # 401: anonymous disabled - good
minikube ssh -- "sudo curl -sk --cert /var/lib/minikube/certs/apiserver-kubelet-client.crt --key /var/lib/minikube/certs/apiserver-kubelet-client.key https://127.0.0.1:10250/pods | head -c 60"
#   {"kind":"PodList","apiVersion":"v1",...                          <- with the API server's own kubelet client cert: everything
```
Through the API server the same access is `nodes/proxy` (see [../rbac-good-practices](../rbac-good-practices/) row 4). Whoever holds a kubelet client credential talks to every kubelet directly.

## Lab 3 – etcd: below admission, validation and audit
```bash
E="etcdctl --cacert /var/lib/minikube/certs/etcd/ca.crt --cert /var/lib/minikube/certs/etcd/server.crt --key /var/lib/minikube/certs/etcd/server.key"
kubectl create cm via-api -n bypass-demo --from-literal=owner=api
kubectl exec -n kube-system etcd-minikube -- $E put /registry/configmaps/bypass-demo/via-api 'not-a-valid-object'
kubectl get cm via-api -n bypass-demo
#   Error from server (InternalError): ... StorageError: corrupt object ...      <- no validation at all
kubectl exec -n kube-system etcd-minikube -- $E del /registry/configmaps/bypass-demo/via-api
kubectl get cm -n bypass-demo                       # gone - no finalizers, no admission, no audit event
```
Reading Secrets from etcd: `../../configuration/secret`, Lab 9, and `../secrets-good-practices`.

## Lab 4 – The container runtime socket
```bash
minikube ssh -- "sudo ctr -n bypass image pull docker.io/library/busybox:1.36; sudo ctr -n bypass run -d --privileged docker.io/library/busybox:1.36 hidden sleep 600; sudo ctr -n bypass task ls"
#   hidden    170828    RUNNING          <- a privileged container ...
kubectl get pods -A | grep -c hidden                # 0                 ... Kubernetes has no idea
minikube ssh -- "sudo crictl ps | grep -c hidden"   # 0  (crictl only shows the k8s.io namespace)
```
Anything with the containerd socket (a Pod with `hostPath: /run/containerd/containerd.sock`, a compromised node agent) owns the node. That's why PSS Baseline forbids `hostPath`.

---

## Useful commands
```bash
minikube ssh -- "ls -la /etc/kubernetes/manifests; sudo grep -i staticPodPath /var/lib/kubelet/config.yaml"
kubectl get --raw /api/v1/nodes/minikube/proxy/configz | jq '.kubeletconfig.authentication.anonymous, .kubeletconfig.authorization'
minikube ssh -- "sudo ctr namespaces ls"      # every containerd namespace, not just k8s.io
```

## Cleanup
```bash
./cleanup.sh       # removes the static manifest, kills the ctr container + its namespace, deletes bypass-demo
```
