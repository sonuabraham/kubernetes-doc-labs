# Logging in Kubernetes – Section Page

Based on: https://kubernetes.io/docs/tasks/debug/logging/

> This docs page is only a list of links. The hands-on work is in the concept labs it points to:

| Docs link | Lab in this repo |
|---|---|
| Logging Architecture | [concepts/cluster-administration/logging](../../../concepts/cluster-administration/logging/): basic `kubectl logs`, where logs live on the node, streaming sidecars, the fluentd agent sidecar |
| System Logs | [concepts/cluster-administration/system-logs](../../../concepts/cluster-administration/system-logs/): structured/contextual logs, JSON format and verbosity, node log query |
| A Practical Guide to Kubernetes Logging (CNCF blog) | external reading |

Quick reminders:
```bash
kubectl logs <pod> [-c <container>] [--previous] [--since=10m] [-f]
kubectl logs -l app=<label> --all-containers --prefix
minikube ssh -- sudo journalctl -u kubelet --since -10min
```
