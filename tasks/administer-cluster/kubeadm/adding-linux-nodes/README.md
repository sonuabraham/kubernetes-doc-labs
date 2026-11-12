# Adding Linux worker nodes – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/adding-linux-nodes/

> Runs on the throwaway profile **`kubeadm-lab`** ([../start-kubeadm-lab.sh](../start-kubeadm-lab.sh)). `minikube node add` creates a second machine (a kic container with containerd, kubeadm and kubelet) and joins it **for** you. This lab undoes that join with `kubeadm reset` and repeats it **by hand** with the docs' commands. [../node.sh](../node.sh) runs commands as root on a node (`N=kubeadm-lab-m02` picks the worker).
>
> **Host limit:** each kic node needs inotify instances, and this host has `fs.inotify.max_user_instances=128`. With the default `minikube` cluster running as well, the worker died with *"Failed to allocate manager object: Too many open files"*. Stop the other clusters first (`minikube stop`), or raise the limit: `sudo sysctl fs.inotify.max_user_instances=512`.
>
> **minikube differences:**
> 1. The CA is in `/var/lib/minikube/certs/ca.crt`, not `/etc/kubernetes/pki/ca.crt`.
> 2. The kubelet binary is not on `$PATH`.
> 3. A container can't read the host's kernel config, so preflight `SystemVerification` must be ignored. minikube itself ignores all preflight errors.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **`kubeadm join`** | `kubeadm join <cp-host>:<port> --token <token> --discovery-token-ca-cert-hash sha256:<hash>`, run as root on the new machine. The machine needs a container runtime, the kubelet and kubeadm installed first. |
| **Bootstrap token** | `abcdef.0123456789abcdef`, a Secret `bootstrap-token-<id>` in kube-system. The token authenticates the kubelet as `system:bootstrap:<id>` so it can file its first CSR. The CSR is auto-approved, and the kubelet then uses its own `system:node:<name>` cert. Default TTL is **24h**. |
| **CA cert hash** | SHA-256 of the cluster CA's public key (DER SubjectPublicKeyInfo). The joining node uses it to trust the API server it discovers. Without it, a fake API server could hand the node a bogus CA. |
| **`kubeadm token list / create`** | Run on a control-plane node. `create --print-join-command` prints a complete join line. |
| **IPv6** | Put the address in brackets: `[2001:db8::101]:2073`. |
| **CoreDNS** | Nodes usually join one after another, so CoreDNS ends up on the first control-plane node. Run `rollout restart` after joining to spread it out. |

---

## Step 0 – a cluster plus a second machine
```bash
cd tasks/administer-cluster/kubeadm
./start-kubeadm-lab.sh v1.37.0            # if kubeadm-lab doesn't exist yet
minikube stop                             # free inotify instances (see heads-up); restart it when done
minikube node add -p kubeadm-lab          # 2nd kic container, auto-joined by minikube
kubectl --context kubeadm-lab get nodes
#   kubeadm-lab       Ready    control-plane   ...
#   kubeadm-lab-m02   Ready    <none>          ...      (the name may be -m03 if an earlier add failed)
cd adding-linux-nodes
W=$(kubectl --context kubeadm-lab get nodes -o name | grep -- -m0 | cut -d/ -f2); echo $W
```
Turn it back into a machine that is "not joined":
```bash
N=$W ../node.sh '$KUBEADM reset -f >/dev/null 2>&1; systemctl is-active kubelet'      # inactive
kubectl --context kubeadm-lab delete node $W
../node.sh '$KUBEADM token list'
#   TOKEN                     TTL         EXPIRES                USAGES                   ... EXTRA GROUPS
#   72sluu.nqtibyq36a8zwnfg   23h         2026-11-13T13:14:28Z   authentication,signing   ... system:bootstrappers:kubeadm:default-node-token   <- from init
#   x10m7c.6tuf2yyfg8aybbgv   <forever>   <never>                authentication,signing   ...    <- minikube's "node add" token (--ttl 0)!
```

## Lab 1 – Token and CA hash (on the control plane)
```bash
../node.sh '$KUBEADM token create'
#   job6k4.87ql2zfqn36wjsaq
../node.sh 'cat $PKI/ca.crt | openssl x509 -pubkey | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed "s/^.* //"'
#   574c0c77dff2210cc772b25e920088be69c505ad5f912eb7204a46f3c723f7e2
../node.sh '$KUBEADM token create --print-join-command'
#   kubeadm join control-plane.minikube.internal:8443 --token 2ta1up.77oymot8iagoridh --discovery-token-ca-cert-hash sha256:574c0c77...   <- same hash
```
Copy your own token and hash into the variables below:
```bash
TOKEN=job6k4.87ql2zfqn36wjsaq
HASH=574c0c77dff2210cc772b25e920088be69c505ad5f912eb7204a46f3c723f7e2
```

## Lab 2 – `kubeadm join` (on the worker)
`control-plane.minikube.internal` is in the worker's `/etc/hosts` (→ 192.168.175.2). Port 8443 is minikube's API port.
```bash
N=$W ../node.sh "kubeadm join control-plane.minikube.internal:8443 --token $TOKEN --discovery-token-ca-cert-hash sha256:$HASH"
#   bash: kubeadm: command not found     (or, with $KUBEADM:)
#   [ERROR KubeletVersion]: couldn't get kubelet version: cannot execute 'kubelet --version': executable file not found in $PATH
N=$W ../node.sh "export PATH=\$(dirname \$KUBEADM):\$PATH
  kubeadm join control-plane.minikube.internal:8443 --token $TOKEN --discovery-token-ca-cert-hash sha256:$HASH"
#   [ERROR SystemVerification]: failed to parse kernel config: unable to load kernel module: "configs" ...
N=$W ../node.sh "export PATH=\$(dirname \$KUBEADM):\$PATH
  kubeadm join control-plane.minikube.internal:8443 --token $TOKEN --discovery-token-ca-cert-hash sha256:$HASH --ignore-preflight-errors=SystemVerification"
#   [preflight] Running pre-flight checks
#   	[WARNING SystemVerification]: failed to parse kernel config ...
#   [preflight] Reading configuration from the "kubeadm-config" ConfigMap in namespace "kube-system"...
#   [kubelet-start] Writing kubelet configuration to file "/var/lib/kubelet/config.yaml"      <- from the kubelet-config ConfigMap
#   [kubelet-start] Writing kubelet environment file with flags to file "/var/lib/kubelet/kubeadm-flags.env"
#   [kubelet-start] Starting the kubelet
#   [kubelet-start] Waiting for the kubelet to perform the TLS Bootstrap
#   This node has joined the cluster:
#   * Certificate signing request was sent to apiserver and a response was received.
#   * The Kubelet was informed of the new secure connection details.
#   Run 'kubectl get nodes' on the control-plane to see this node join the cluster.
kubectl --context kubeadm-lab get nodes
#   kubeadm-lab       Ready    control-plane   10m   v1.37.0
#   kubeadm-lab-m03   Ready    <none>          6s    v1.37.0
kubectl --context kubeadm-lab get csr
#   csr-28g55   kubernetes.io/kube-apiserver-client-kubelet   system:bootstrap:x10m7c   Approved,Issued   <- minikube's auto join
#   csr-qt7z7   kubernetes.io/kube-apiserver-client-kubelet   system:bootstrap:job6k4   Approved,Issued   <- ours: the token id is the user
```
Delete tokens you no longer need. A joined node doesn't use the token again:
```bash
../node.sh "\$KUBEADM token delete $TOKEN"          # also delete minikube's forever token: \$KUBEADM token delete x10m7c
```

## Lab 3 – Rebalance CoreDNS and run something on the worker
```bash
K="kubectl --context kubeadm-lab"
$K -n kube-system get po -o wide --field-selector spec.nodeName=$W     # kindnet-* and kube-proxy-* (DaemonSets) arrived
$K -n kube-system scale deploy coredns --replicas=2                   # minikube runs a single replica
$K -n kube-system rollout restart deployment coredns && $K -n kube-system rollout status deployment coredns
$K -n kube-system get po -l k8s-app=kube-dns -o wide
#   coredns-b5dd768f4-bjq7t   Running   kubeadm-lab-m03
#   coredns-b5dd768f4-f44zm   Running   kubeadm-lab           <- spread (kubeadm's CoreDNS has pod anti-affinity)
$K create ns join-demo && $K -n join-demo create deploy web --image=nginx --replicas=2 && $K -n join-demo rollout status deploy web
$K -n join-demo get po -o wide
#   web-...-9wzjx   Running   10.244.2.4   kubeadm-lab-m03     <- Pod CIDR from the new node's podCIDR
#   web-...-k6f6k   Running   10.244.0.8   kubeadm-lab
```

---

## Useful commands
```bash
kubeadm token list | create [--ttl 2h] [--print-join-command] | delete <id>
openssl x509 -pubkey -in ca.crt | openssl rsa -pubin -outform der | openssl dgst -sha256 -hex
kubeadm join <host>:<port> --token ... --discovery-token-ca-cert-hash sha256:...
kubeadm reset -f                        # undo a join on the node, then: kubectl delete node <name>
```

## Cleanup
```bash
kubectl --context kubeadm-lab delete ns join-demo
kubectl --context kubeadm-lab -n kube-system scale deploy coredns --replicas=1
# keep the worker for the "Upgrading Linux nodes" lab, or remove it:
#   kubectl --context kubeadm-lab drain $W --ignore-daemonsets --force && minikube node delete $W -p kubeadm-lab
minikube start                          # bring the default cluster back
```
