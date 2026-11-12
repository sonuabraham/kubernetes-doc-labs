# Install and Set Up kubectl on macOS – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/tools/install-kubectl-macos/

> ⚠️ This machine is Linux. [fetch-and-verify.sh](fetch-and-verify.sh) runs the page's **download and checksum** steps for **both** Mac architectures (Intel `amd64` and Apple Silicon `arm64`) and identifies the binaries (they're in `dl/`, gitignored). Everything that's the same on every OS (version, `cluster-info`, completion, kuberc, `kubectl convert`) was run in `../install-kubectl-linux`.

## Key ideas (read first)

| Topic | macOS specifics |
|---|---|
| **Architecture** | Pick `darwin/amd64` (Intel) or `darwin/arm64` (Apple Silicon). The wrong one fails with "bad CPU type in executable" (amd64 can run on arm64 through Rosetta). |
| **Checksum** | `echo "$(cat kubectl.sha256)  kubectl" \| shasum -a 256 --check` (macOS has `shasum`, not `sha256sum`). |
| **Install** | `chmod +x ./kubectl; sudo mv ./kubectl /usr/local/bin/kubectl; sudo chown root: /usr/local/bin/kubectl`. Make sure `/usr/local/bin` is on `PATH`. |
| **Homebrew / MacPorts** | `brew install kubectl` (alias of `kubernetes-cli`). `sudo port install kubectl`. To uninstall a brew install: `brew remove kubectl`. |
| **Completion** | **Bash on macOS is 3.2**: needs bash-completion **v2** + Bash 4.1+ (`brew install bash bash-completion@2`). **Zsh** (the default shell) works directly: `source <(kubectl completion zsh)`. |

---

## Lab 1 – Download and verify both architectures
```bash
cd tasks/tools/install-kubectl-macos
./fetch-and-verify.sh
#   kubectl: OK
#   kubectl: Mach-O 64-bit x86_64 executable, flags:<|DYLDLINK|PIE>          <- dl/amd64 (Intel)
#   kubectl-convert: OK
#   kubectl-convert: Mach-O 64-bit x86_64 executable, flags:<|DYLDLINK|PIE>
#   kubectl: OK
#   kubectl: Mach-O 64-bit arm64 executable, flags:<|DYLDLINK|PIE>           <- dl/arm64 (Apple Silicon)
#   kubectl-convert: OK
#   kubectl-convert: Mach-O 64-bit arm64 executable, flags:<|DYLDLINK|PIE>
```

## Lab 2 – The zsh completion script
```bash
../install-kubectl-linux/bin/kubectl completion zsh | head -1       # #compdef kubectl   (228 lines)
```
On a Mac: `echo 'source <(kubectl completion zsh)' >> ~/.zshrc`. If you see `complete:13: command not found: compdef`, add `autoload -Uz compinit; compinit` at the top of `~/.zshrc`.

## On a real Mac
```bash
curl -LO "https://dl.k8s.io/release/v1.37.0/bin/darwin/arm64/kubectl"
curl -LO "https://dl.k8s.io/release/v1.37.0/bin/darwin/arm64/kubectl.sha256"
echo "$(cat kubectl.sha256)  kubectl" | shasum -a 256 --check        # kubectl: OK
chmod +x ./kubectl && sudo mv ./kubectl /usr/local/bin/kubectl && sudo chown root: /usr/local/bin/kubectl
kubectl version --client
```

---

## Cleanup
```bash
rm -rf dl
```
