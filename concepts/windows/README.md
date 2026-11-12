# Windows in Kubernetes – Hands-on Labs

Based on: https://kubernetes.io/docs/concepts/windows/

minikube can't run Windows nodes. [fake-windows-nodes.sh](fake-windows-nodes.sh) (`up` / `down`) registers two **API-only** Windows nodes on the current cluster, kept Ready by a heartbeat loop:

| Node | `kubernetes.io/os` | `node.kubernetes.io/windows-build` |
|---|---|---|
| `win-2022` | windows | `10.0.20348` (Windows Server 2022) |
| `win-2025` | windows | `10.0.26100` (Windows Server 2025) |

Validation, scheduling, taints and RuntimeClass admission all run for real. Pods bound to the fake nodes stay `Pending` forever, and deleting them needs `--force` (see `../scheduling-eviction/delete-ns.sh`).

| Page | Lab shows |
|---|---|
| [intro](intro/) | the 20 fields `spec.os.name: windows` forbids (and the ones it doesn't check); the kubelet's `PodOSNotSupported`; the failed-Pod storm when Windows Pods have no nodeSelector; image vs. host build matching |
| [user-guide](user-guide/) | the docs' web server, why Windows nodes get an `os=windows:NoSchedule` taint, version pinning with `windows-build`, RuntimeClass `scheduling` merged in by admission |

Related Windows pages in other sections: `../storage/windows-storage`, `../configuration/windows-resource-management`, `../security/windows-security`.
