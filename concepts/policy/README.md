# Policies – Hands-on Labs

Based on: https://kubernetes.io/docs/concepts/policy/

| Policy | Scope | Lab |
|---|---|---|
| **LimitRange** | per object (Container/Pod/PVC): defaults, min/max, ratios | [limit-range](limit-range/) |
| **ResourceQuota** | per namespace total: compute, storage, object counts, scopes | [resource-quotas](resource-quotas/) |
| **PID limits** | per Pod and per node (kubelet config) | [pid-limiting](pid-limiting/) |
| Node resource managers | moved to the Resource Management section | [../resource-management/resource-managers](../resource-management/resource-managers/) |

Related: Pod Security Admission (`../security/pod-security-admission`) and ValidatingAdmissionPolicy (`../security/pod-security-policy`) are the policy mechanisms for *what* Pods may do. These pages cover *how much* they may use.
