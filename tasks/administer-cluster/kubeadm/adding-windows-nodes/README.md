# Adding Windows worker nodes – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/adding-windows-nodes/

> ⚠️ This lab needs a Windows Server 2022+ machine, and minikube can't run one. The Windows-only steps (the two PowerShell scripts) are **read and explained** here. The parts that don't depend on the OS are **run for real** against the `kubeadm-lab` cluster ([../start-kubeadm-lab.sh](../start-kubeadm-lab.sh)), from this Linux host acting as the "new machine":
> - [discover.py](discover.py) replays the **discovery** step of `kubeadm join`: the token's JWS signature and the CA hash.
> - [tls-bootstrap.sh](tls-bootstrap.sh) replays the kubelet's **TLS bootstrap + Node registration** for a node labelled like Windows Server 2022.
>
> This shows what `kubeadm join` does on every OS. It also shows the mixed-cluster networking gotcha the page warns about.

## Key ideas (read first)

| Step on the Windows machine | What it does |
|---|---|
| `Install-Containerd.ps1 -ContainerDVersion 1.7.22` | Enables the **Containers** feature (and Hyper-V unless `-skipHypervisorSupportCheck`). Downloads containerd (no `v` prefix in the version) and crictl. Puts CNI paths into `config.toml` (`-CNIBinPath c:/opt/cni/bin`, `-CNIConfigPath c:/etc/cni/net.d`). Registers containerd as a service. **May reboot.** |
| `PrepareNode.ps1 -KubernetesVersion v1.37.x` | Downloads `kubelet.exe` + `kubeadm.exe` into `C:\k` and puts it on PATH. Writes a start script that reads `/var/lib/kubelet/kubeadm-flags.env`. Registers the kubelet as an **nssm** service (depends on containerd). Opens TCP 10250. Prints the kube-proxy/CNI DaemonSet commands to run **from the control plane** afterwards. |
| `kubeadm join ...` | The same command as on Linux (token + CA hash). See [../adding-linux-nodes](../adding-linux-nodes/). |
| **Networking** | Linux CNI and kube-proxy DaemonSets must **not** land on Windows nodes. Windows gets its own **HostProcess** DaemonSets (sig-windows-tools flannel/calico `kube-proxy.yml`, or Calico for Windows). Only a few CNIs support Windows. |
| **kubectl** | Optional on the node. See [../../../tools/install-kubectl-windows](../../../tools/install-kubectl-windows/). |

What `kubeadm join` does, step by step (Lab 2 and Lab 3 replay it):
```
 new node                                   API server (control-plane.minikube.internal:8443)
 ────────                                   ──────────
 1. GET kube-public/cluster-info  (anonymous, TLS NOT verified yet) ──►  kubeconfig + jws-kubeconfig-<token-id>
 2. check JWS = HMAC-SHA256(token-secret, kubeconfig)   → this server knows our token
 3. check sha256(CA public key) == --discovery-token-ca-cert-hash → this is the CA we were told to trust
 4. as system:bootstrap:<id>: create CSR CN=system:node:<name> ──►  csrapprover auto-approves, CA signs
 5. as system:node:<name>: create Node, post status/heartbeats  ──►  NodeRestriction: only its own Node
```

---

## Step 0
```bash
cd tasks/administer-cluster/kubeadm
./start-kubeadm-lab.sh v1.37.0             # if needed (the adding-linux-nodes lab also left a Linux worker there)
cd adding-windows-nodes
IP=$(minikube ip -p kubeadm-lab)
```

## Lab 1 – Read the two PowerShell scripts
```bash
mkdir -p dl && cd dl        # dl/ is gitignored
curl -LO https://raw.githubusercontent.com/kubernetes-sigs/sig-windows-tools/master/hostprocess/Install-Containerd.ps1
curl -LO https://raw.githubusercontent.com/kubernetes-sigs/sig-windows-tools/master/hostprocess/PrepareNode.ps1
sed -n 1,40p Install-Containerd.ps1
#   - Verifies that Windows Features requried for running containers are enabled (and enables them if they are not)
#   - Downloads ContainerD binaries ... - Downloads Windows SND CNI plugins. - Registers ContainerD as a windows service.
#   [string] $ContainerDVersion = "1.7.1",  [switch] $skipHypervisorSupportCheck,
#   [string] $CNIBinPath = "c:/opt/cni/bin", [string] $CNIConfigPath = "c:/etc/cni/net.d"
grep -nE "Install-WindowsFeature|DISM|releases/download|--register-service" Install-Containerd.ps1
grep -nE "dl.k8s.io|kubeadm-flags.env|nssm install|DependOnService|NetFirewallRule|kube-proxy.yml" PrepareNode.ps1
#   DownloadFile ... https://dl.k8s.io/$KubernetesVersion/bin/windows/amd64/kubelet.exe   (and kubeadm.exe)
#   $FileContent = Get-Content -Path "/var/lib/kubelet/kubeadm-flags.env"      <- same flags file as on Linux
#   nssm install kubelet ...   nssm set kubelet DependOnService containerd
#   New-NetFirewallRule -Name kubelet ... -LocalPort 10250
#   curl.exe -LO $repoUrl/hostprocess/flannel/kube-proxy/kube-proxy.yml      <- Windows kube-proxy, applied from the control plane
cd ..
```

## Lab 2 – Discovery: token signature and CA pinning
```bash
TOKEN=$(../node.sh '$KUBEADM token create --ttl 1h --description "windows join demo"' | tr -d '\r'); echo $TOKEN
HASH=$(../node.sh 'openssl x509 -pubkey -in $PKI/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed "s/^.* //"' | tr -d '\r')
./discover.py $IP:8443 $TOKEN $HASH
#   [discovery] cluster-info keys: ['jws-kubeconfig-2ta1up', 'jws-kubeconfig-72sluu', 'jws-kubeconfig-yaxurm', 'kubeconfig']
#   [discovery] JWS for token yaxurm verified (header {"alg":"HS256","kid":"yaxurm"})
#   [discovery] CA public key sha256:574c0c77dff2210cc772b25e920088be69c505ad5f912eb7204a46f3c723f7e2
#   [discovery] cluster CA trusted -> .../adding-windows-nodes/ca.crt
```
There is one `jws-kubeconfig-<id>` per valid token. The bootstrap signer controller adds and removes them. Now break each check:
```bash
./discover.py $IP:8443 ${TOKEN%.*}.0000000000000000 $HASH            # JWS signature mismatch: wrong token secret
./discover.py $IP:8443 $TOKEN sha256:$(printf 0%.0s {1..64})         # CA hash does NOT match ...: refusing to trust this server
./discover.py $IP:8443 abcdef.0123456789abcdef $HASH                 # no signature for token id 'abcdef' (unknown or expired token)
```

## Lab 3 – TLS bootstrap and Node registration (as a "Windows" node)
```bash
./tls-bootstrap.sh $IP:8443 $TOKEN win-node
#   == who am I with the bootstrap token?
#   Username    system:bootstrap:yaxurm
#   Groups      [system:bootstrappers system:bootstrappers:kubeadm:default-node-token system:authenticated]
#   certificatesigningrequest.certificates.k8s.io/node-csr-win-node-... created
#   == issued:   subject=O=system:nodes, CN=system:node:win-node   issuer=CN=minikubeCA   notAfter=<+1 year>
#   == who am I with the node cert?
#   Username    system:node:win-node      Groups  [system:nodes system:authenticated]
#   node/win-node created
kubectl --context kubeadm-lab get nodes -L kubernetes.io/os,node.kubernetes.io/windows-build
#   kubeadm-lab       Ready     control-plane   v1.37.0   linux
#   kubeadm-lab-m03   Ready     <none>          v1.37.0   linux
#   win-node          Unknown   <none>                    windows   10.0.20348      <- no kubelet posts status
kubectl --context kubeadm-lab get csr | grep win-node
#   node-csr-win-node-...   kubernetes.io/kube-apiserver-client-kubelet   system:bootstrap:yaxurm   Approved,Issued   <- auto-approved
```
NodeRestriction limits a node's credentials to its own Node object:
```bash
kubectl --kubeconfig=/dev/null --server https://$IP:8443 --certificate-authority ca.crt \
  --client-certificate win-node.crt --client-key win-node.key label node kubeadm-lab-m03 hacked=yes
#   Forbidden: node 'win-node' cannot read 'kubeadm-lab-m03', only its own Node object
```

## Lab 4 – Why mixed clusters need Windows-aware networking
```bash
kubectl --context kubeadm-lab get ds -n kube-system \
  -o custom-columns='NAME:.metadata.name,NODESELECTOR:.spec.template.spec.nodeSelector,TOLERATE:.spec.template.spec.tolerations[*].operator,DESIRED:.status.desiredNumberScheduled'
#   NAME         NODESELECTOR                  TOLERATE   DESIRED
#   kindnet      <none>                        Exists     3        <- minikube's CNI targets the Windows node too!
#   kube-proxy   map[kubernetes.io/os:linux]   Exists     2        <- kubeadm's kube-proxy is Linux-only by design
kubectl --context kubeadm-lab -n kube-system get po -l app=kindnet -o wide
#   kindnet-2gkbx   Pending   <none>     (FailedScheduling: our fake node reports no capacity. A real Windows
#                                         kubelet would get this Linux image and fail to run it.)
```
Pin Linux-only DaemonSets to Linux nodes. Windows nodes then get their own HostProcess kube-proxy/CNI DaemonSets (`kube-proxy.yml` from sig-windows-tools, Calico for Windows):
```bash
kubectl --context kubeadm-lab -n kube-system patch ds kindnet -p '{"spec":{"template":{"spec":{"nodeSelector":{"kubernetes.io/os":"linux"}}}}}'
kubectl --context kubeadm-lab -n kube-system get ds kindnet -o jsonpath='{.status.desiredNumberScheduled}{"\n"}'     # 2
```

---

## Useful commands
```powershell
# on the Windows node (PowerShell, as Administrator)
.\Install-Containerd.ps1 -ContainerDVersion 1.7.22 [-skipHypervisorSupportCheck]
.\PrepareNode.ps1 -KubernetesVersion v1.37.0
kubeadm join control-plane:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>
Get-Service containerd, kubelet ; Get-Content C:\var\log\kubelet\kubelet.err.log -Tail 50
```
```bash
kubectl get nodes -L kubernetes.io/os,node.kubernetes.io/windows-build
kubectl get ds -A -o custom-columns=NAME:.metadata.name,SEL:.spec.template.spec.nodeSelector
```

## Cleanup
```bash
./cleanup.sh $TOKEN     # deletes win-node, its CSR, the token, and the local key/cert/ca files
```
