# Install and Set Up kubectl on Windows – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/tools/install-kubectl-windows/

> ⚠️ This machine is Linux. [fetch-and-verify.sh](fetch-and-verify.sh) runs the page's **download and checksum** steps for real (binaries in `dl/`, gitignored) and identifies the files. The Windows-only steps (PATH, package managers, PowerShell) are listed with what they do. Everything that is the same on every OS (version check, `cluster-info`, completion, kuberc, `kubectl convert`) was run in `../install-kubectl-linux`.

## Key ideas (read first)

| Topic | Windows specifics |
|---|---|
| **Binary** | `kubectl.exe` from `https://dl.k8s.io/release/<v>/bin/windows/amd64/kubectl.exe`. Put its folder on `PATH`. |
| **Checksum** | `CertUtil -hashfile kubectl.exe SHA256` (compare by eye with `type kubectl.exe.sha256`) or PowerShell `$(Get-FileHash -Algorithm SHA256 .\kubectl.exe).Hash -eq $(Get-Content .\kubectl.exe.sha256)` → `True`. |
| **Docker Desktop** | Adds **its own** kubectl to `PATH`. Put your entry **before** it, or the old one wins (the same trap as the snap in the Linux lab). |
| **Package managers** | `choco install kubernetes-cli`, `scoop install kubectl`, `winget install -e --id Kubernetes.kubectl`. |
| **kubeconfig** | `%USERPROFILE%\.kube\config` (`cd ~; mkdir .kube; New-Item config -type file`). |
| **Completion** | PowerShell: `kubectl completion powershell \| Out-String \| Invoke-Expression`, and add it to `$PROFILE` to keep it. |
| **kubectl convert** | `kubectl-convert.exe` on `PATH`. |

---

## Lab 1 – Download and verify (the page's curl.exe steps, run with curl on Linux)
```bash
cd tasks/tools/install-kubectl-windows
./fetch-and-verify.sh
#   kubectl.exe: OK
#   kubectl.exe: PE32+ executable for MS Windows 6.01 (console), x86-64, 8 sections
#   kubectl-convert.exe: OK
#   kubectl-convert.exe: PE32+ executable for MS Windows 6.01 (console), x86-64, 8 sections
```
The page downloads the **binary** from `dl.k8s.io/release/v…/` but the **checksum** from `dl.k8s.io/v…/` (no `release/`). Both URLs work (HTTP 200, same file):
```bash
curl -sL https://dl.k8s.io/v1.37.0/bin/windows/amd64/kubectl.exe.sha256 ; echo
curl -sL https://dl.k8s.io/release/v1.37.0/bin/windows/amd64/kubectl.exe.sha256 ; echo
```

## Lab 2 – The PowerShell completion script
```bash
../install-kubectl-linux/bin/kubectl completion powershell | head -3     # (after running the Linux lab)
#   # Copyright 2016 The Kubernetes Authors.        284 lines; on Windows: | Out-String | Invoke-Expression
```

## On a real Windows machine
```powershell
curl.exe -LO "https://dl.k8s.io/release/v1.37.0/bin/windows/amd64/kubectl.exe"
curl.exe -LO "https://dl.k8s.io/v1.37.0/bin/windows/amd64/kubectl.exe.sha256"
$(Get-FileHash -Algorithm SHA256 .\kubectl.exe).Hash -eq $(Get-Content .\kubectl.exe.sha256)    # True
# add the folder to PATH (before Docker Desktop's), then:
kubectl version --client
kubectl cluster-info
```

---

## Cleanup
```bash
rm -rf dl
```
