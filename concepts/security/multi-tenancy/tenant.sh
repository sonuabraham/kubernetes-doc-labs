#!/usr/bin/env bash
# tenant.sh <name>  - "namespace per tenant" kit from the page: namespace + PSA, tenant admin SA with RBAC,
# ResourceQuota (incl. object counts), LimitRange defaults, NetworkPolicies (default deny + same-namespace + DNS).
set -euo pipefail
T=$1
kubectl apply -f - <<Y
apiVersion: v1
kind: Namespace
metadata:
  name: tenant-$T
  labels: {tenant: $T, pod-security.kubernetes.io/enforce: baseline, pod-security.kubernetes.io/warn: restricted}
---
apiVersion: v1
kind: ServiceAccount
metadata: {name: $T-admin, namespace: tenant-$T}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: {name: $T-admin, namespace: tenant-$T}
roleRef: {apiGroup: rbac.authorization.k8s.io, kind: ClusterRole, name: admin}
subjects: [{kind: ServiceAccount, name: $T-admin, namespace: tenant-$T}]
---
apiVersion: v1
kind: ResourceQuota
metadata: {name: tenant-quota, namespace: tenant-$T}
spec:
  hard: {requests.cpu: "1", requests.memory: 1Gi, limits.cpu: "2", limits.memory: 2Gi, pods: "10", count/configmaps: "20", count/secrets: "20", persistentvolumeclaims: "5"}
---
apiVersion: v1
kind: LimitRange
metadata: {name: tenant-defaults, namespace: tenant-$T}
spec:
  limits:
  - type: Container
    default: {cpu: 200m, memory: 128Mi}
    defaultRequest: {cpu: 50m, memory: 32Mi}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: default-deny, namespace: tenant-$T}
spec: {podSelector: {}, policyTypes: [Ingress, Egress]}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: allow-same-tenant, namespace: tenant-$T}
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
  ingress: [{from: [{podSelector: {}}]}]
  egress:
  - to: [{podSelector: {}}]
  - to: [{namespaceSelector: {matchLabels: {kubernetes.io/metadata.name: kube-system}}, podSelector: {matchLabels: {k8s-app: kube-dns}}}]
    ports: [{port: 53, protocol: UDP}, {port: 53, protocol: TCP}]
Y
