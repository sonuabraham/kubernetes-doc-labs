# Install and Set Up kubectl on Linux – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/

> Everything is downloaded into this folder's `bin/` (gitignored), **not** `/usr/local/bin`, so the lab changes nothing on the machine. `export PATH=$PWD/bin:$PATH` makes it take effect in one shell only.
>
> Added for the lab: [old-ingress.yaml](old-ingress.yaml), an `extensions/v1beta1` Ingress for `kubectl convert`, and [kuberc.yaml](kuberc.yaml), kubectl preferences used through `KUBERC=`.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **Version skew** | kubectl must be within **±1 minor** of the API server: a v1.37 client works with v1.36, v1.37 and v1.38 control planes. |
| **Install methods** | Binary via curl (+ sha256 check). Native packages from **pkgs.k8s.io** (apt/dnf/zypper; one repo **per minor version**, so upgrading means editing the repo line). Snap or Homebrew. |
| **Verify** | `kubectl version`, `kubectl cluster-info` (needs `~/.kube/config`; minikube writes it). |
| **Completion** | `kubectl completion bash|zsh|fish|powershell` generates a script. Bash also needs `bash-completion`. `alias k=kubectl` + `complete -o default -F __start_kubectl k`. |
| **kuberc** | `~/.kube/kuberc` (or `$KUBERC`): user **preferences** kept separate from cluster credentials, with command **aliases** and option **defaults**. `KUBERC=off` disables it. |
| **kubectl convert** | A plugin (separate binary `kubectl-convert`) that rewrites manifests from old API versions to new ones. |
| **Plugins** | Any executable named `kubectl-<name>` on `PATH`. |

---

## Lab 1 – The problem on this machine
```bash
cd tasks/tools/install-kubectl-linux
command -v kubectl ; kubectl version
#   /snap/bin/kubectl
#   Client Version: v1.35.10
#   Server Version: v1.37.0
#   Warning: version difference between client (1.35) and server (1.37) exceeds the supported minor version skew of +/-1
snap list kubectl ; snap info kubectl | grep -E "^\s+(latest|1\.3[5-8])/stable"
#   kubectl  1.35.10  3869  latest/stable  canonical**  classic
#     latest/stable:  1.35.10
#     1.36/stable:    1.36.6           <- no 1.37 channel yet: snap can't currently fix the skew
```

## Lab 2 – Install the binary with curl (the docs' steps)
```bash
mkdir -p bin && cd bin
curl -L -s https://dl.k8s.io/release/stable.txt          # v1.37.2   (latest patch; the cluster runs v1.37.0)
curl -LO https://dl.k8s.io/release/v1.37.0/bin/linux/amd64/kubectl
curl -LO https://dl.k8s.io/release/v1.37.0/bin/linux/amd64/kubectl.sha256
echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
#   kubectl: OK
cp kubectl kubectl.bad && printf x >> kubectl.bad && echo "$(cat kubectl.sha256)  kubectl.bad" | sha256sum --check
#   kubectl.bad: FAILED
#   sha256sum: WARNING: 1 computed checksum did NOT match         (exit 1)
rm kubectl.bad kubectl.sha256 ; chmod +x kubectl ; cd ..
export PATH=$PWD/bin:$PATH
kubectl version
#   Client Version: v1.37.0   Kustomize Version: v5.8.1   Server Version: v1.37.0     <- no skew warning
kubectl version --client --output=yaml | grep -E "gitVersion|goVersion|platform"
#   gitVersion: v1.37.0   goVersion: go1.26.6   platform: linux/amd64
```
To install it for real, use `sudo install -o root -g root -m 0755 bin/kubectl /usr/local/bin/kubectl`, or `~/.local/bin` without root. Then remove the snap (`sudo snap remove kubectl`) or make sure the new one comes **first** on `PATH`.

## Lab 3 – Verify the configuration
```bash
kubectl cluster-info
#   Kubernetes control plane is running at https://192.168.58.2:8443
#   CoreDNS is running at https://192.168.58.2:8443/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
```
Without a kubeconfig it would try `localhost:8080` and fail ("The connection to the server localhost:8080 was refused").

## Lab 4 – Shell autocompletion (bash)
```bash
bash -c 'source <(kubectl completion bash); alias k=kubectl; complete -o default -F __start_kubectl k; complete -p kubectl k'
#   complete -o default -F __start_kubectl kubectl
#   complete -o default -F __start_kubectl k
kubectl __complete get po                       # what TAB calls under the hood
#   pods  podtemplates  podcertificaterequests.certificates.k8s.io
kubectl __complete get deploy -n kube-system "" # live names from the cluster
#   coredns  metrics-server  snapshot-controller
```
Permanent setup (docs): `echo 'source <(kubectl completion bash)' >>~/.bashrc`, plus the alias lines, then `source ~/.bashrc`.

## Lab 5 – kuberc: aliases and defaults
```bash
export KUBERC=$PWD/kuberc.yaml
kubectl getsys pods | head -2            # alias = get -n kube-system -o wide
kubectl create cm kuberc-test --from-literal=a=b --dry-run=client -o yaml | kubectl apply -f -
#   configmap/kuberc-test serverside-applied          <- default: apply --server-side
echo n | kubectl delete cm kuberc-test
#   You are about to delete the following 1 resource(s): configmap/kuberc-test
#   Do you want to continue? (y/N): deletion is cancelled          <- default: delete --interactive
echo y | kubectl delete cm kuberc-test
KUBERC=off kubectl getsys pods           # error: unknown command "getsys" for "kubectl"
```

## Lab 6 – The kubectl convert plugin
```bash
cd bin
curl -LO https://dl.k8s.io/release/v1.37.0/bin/linux/amd64/kubectl-convert
curl -LO https://dl.k8s.io/release/v1.37.0/bin/linux/amd64/kubectl-convert.sha256
echo "$(cat kubectl-convert.sha256) kubectl-convert" | sha256sum --check      # kubectl-convert: OK
chmod +x kubectl-convert ; cd ..
kubectl plugin list
#   .../bin/kubectl-convert
#   .../bin/kubectl-convert.sha256
#     - warning: ...kubectl-convert.sha256 identified as a kubectl plugin, but it is not executable
rm bin/kubectl-convert.sha256          # that's why the docs delete the downloaded checksum files
kubectl apply --dry-run=server -f old-ingress.yaml
#   no matches for kind "Ingress" in version "extensions/v1beta1"          (removed in v1.22)
kubectl convert -f old-ingress.yaml --output-version networking.k8s.io/v1
#   apiVersion: networking.k8s.io/v1 ... backend: {service: {name: web, port: {number: 80}}}
#   pathType: ImplementationSpecific                                         <- filled in by the conversion
kubectl convert -f old-ingress.yaml --output-version networking.k8s.io/v1 | kubectl apply --dry-run=server -f -
#   ingress.networking.k8s.io/legacy created (server dry run)
```

## Not run here
The **apt/dnf/zypper** steps (pkgs.k8s.io repos) need root and change system package sources. The repo URL has the **minor version** in it (`.../core:/stable:/v1.37/deb/`). See `../../administer-cluster/kubeadm/change-package-repository`.

---

## Useful commands
```bash
kubectl version ; kubectl version --client --output=yaml
kubectl cluster-info ; kubectl plugin list
kubectl completion bash > /etc/bash_completion.d/kubectl
```

## Cleanup
```bash
./cleanup.sh        # removes bin/ and the test ConfigMap (nothing outside this folder was changed)
```
