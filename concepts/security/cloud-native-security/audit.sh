#!/usr/bin/env bash
# A read-only "where does my cluster stand?" check, one section per lifecycle phase of the page.
# It only reads: API server flags, kubelet config, workloads. Nothing is changed.
set -uo pipefail
APISERVER=$(kubectl get pod -n kube-system -l component=kube-apiserver -o json | jq -r '.items[0].spec.containers[0].command[]')
flag(){ echo "$APISERVER" | grep -E -- "^--$1=" | head -1 | cut -d= -f2-; }
h(){ printf '\n== %s\n' "$1"; }

h "DISTRIBUTE - what images run? (tags can move; digests can't)"
kubectl get pods -A -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.image}{"\n"}{end}{end}' | sort -u |
  awk '{ if ($0 ~ /@sha256:/) d++; else if ($0 ~ /:latest$/ || $0 !~ /:[^\/]+$/) l++; else t++ } END {printf "pinned by digest: %d   by tag: %d   latest/untagged: %d\n", d, t, l}'

h "DEPLOY - admission control"
echo "enable-admission-plugins: $(flag enable-admission-plugins)"
echo "namespaces with Pod Security Admission labels:"; kubectl get ns -L pod-security.kubernetes.io/enforce --no-headers | awk '$4!="" {print "  "$1" enforce="$4}'
[ -z "$(kubectl get ns -l pod-security.kubernetes.io/enforce -o name)" ] && echo "  (none)"

h "RUNTIME: ACCESS - API server"
echo "authorization-mode: $(flag authorization-mode)"
echo "anonymous-auth:     $(flag anonymous-auth || true) (unset = true)"
SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
echo "unauthenticated GET /api/v1/namespaces -> $(curl -sk -o /dev/null -w '%{http_code}' $SERVER/api/v1/namespaces)  (403 = anonymous allowed in, but not authorized)"
echo "unauthenticated GET /version         -> $(curl -sk -o /dev/null -w '%{http_code}' $SERVER/version)"
echo "plain HTTP to the API port           -> $(curl -s -o /dev/null -w '%{http_code}' --max-time 3 ${SERVER/https/http}/version) (400 = TLS required)"
echo "tls-min-version: $(flag tls-min-version || true) (unset = TLS 1.2)"
echo "audit logging: $( [ -n "$(flag audit-log-path)" ] && echo on || echo OFF )"

h "RUNTIME: ACCESS - kubelet"
kubectl get --raw /api/v1/nodes/minikube/proxy/configz | jq -r '.kubeletconfig | "anonymous auth: \(.authentication.anonymous.enabled)   authz mode: \(.authorization.mode)   readOnlyPort: \(.readOnlyPort // 0)"'

h "RUNTIME: COMPUTE - how do workloads run?"
kubectl get pods -A -o json | jq -r '
  [.items[] | {ns: .metadata.namespace, name: .metadata.name, spec: .spec}] as $p |
  "pods: \($p|length)",
  "privileged containers: \([$p[] | select(any(.spec.containers[]; .securityContext.privileged == true))] | length)",
  "hostNetwork pods: \([$p[] | select(.spec.hostNetwork == true)] | length)",
  "pods without runAsNonRoot: \([$p[] | select((.spec.securityContext.runAsNonRoot // false) == false and all(.spec.containers[]; (.securityContext.runAsNonRoot // false) == false))] | length)",
  "containers without limits: \([$p[] | .spec.containers[] | select(.resources.limits == null)] | length)",
  "runtimeClassName in use: \([$p[] | .spec.runtimeClassName // empty] | unique)"'

h "RUNTIME: STORAGE - Secrets at rest"
echo "encryption-provider-config: $(flag encryption-provider-config || true)"
[ -z "$(flag encryption-provider-config)" ] && echo "  -> NOT set: Secrets are stored in etcd as plaintext (see ../../configuration/secret Lab 9)"

h "NETWORKING"
echo "NetworkPolicies defined: $(kubectl get networkpolicy -A --no-headers 2>/dev/null | wc -l)"
echo "CNI pods: $(kubectl get pods -n kube-system -o name | grep -E 'kindnet|calico|cilium|flannel|weave' | tr '\n' ' ')"
