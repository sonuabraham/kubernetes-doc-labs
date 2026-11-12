#!/usr/bin/env bash
# Automates the checkable items of the Kubernetes security checklist (read-only). PASS / FAIL / INFO / MANUAL.
set -uo pipefail
API=$(kubectl get pod -n kube-system -l component=kube-apiserver -o json | jq -r '.items[0].spec.containers[0].command[]')
KCM=$(kubectl get pod -n kube-system -l component=kube-controller-manager -o json | jq -r '.items[0].spec.containers[0].command[]')
NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
KUBELET=$(kubectl get --raw /api/v1/nodes/$NODE/proxy/configz | jq '.kubeletconfig')
PODS=$(kubectl get pods -A -o json)
r(){ printf '%-7s %s\n' "$1" "$2"; }
yes(){ [ "$1" = true ] && echo PASS || echo FAIL; }
h(){ printf '\n## %s\n' "$1"; }

h "Authentication & Authorization"
n=$(kubectl get clusterrolebindings -o json | jq '[.items[] | select(any(.subjects[]?; .kind=="Group" and .name=="system:masters"))] | length')
me=$(kubectl auth whoami -o json | jq -r '.status.userInfo.groups | index("system:masters") != null')
r $( [ "$me" = false ] && echo PASS || echo FAIL ) "system:masters not used for users (your kubeconfig is in system:masters: $me)"
r $(yes $(echo "$KCM" | grep -q -- '--use-service-account-credentials=true' && echo true || echo false)) "kube-controller-manager --use-service-account-credentials"
r MANUAL "root CA protected (offline/managed); leaf certs <= 3y; periodic access reviews"

h "Network security"
np=$(kubectl get networkpolicy -A --no-headers 2>/dev/null | wc -l); nsn=$(kubectl get ns --no-headers | wc -l)
r INFO "NetworkPolicies: $np across $nsn namespaces (CNI must enforce them - kindnet does)"
r $( [ $(kubectl get svc -A -o json | jq '[.items[] | select(.spec.type=="LoadBalancer" or (.spec.externalIPs // [] | length > 0))] | length') -eq 0 ] && echo PASS || echo FAIL ) "no LoadBalancer/externalIPs Services (restricted use)"
r MANUAL "API/kubelet/etcd not exposed to the Internet; cloud metadata API filtered; service mesh mTLS"

h "Pod security"
lab=$(kubectl get ns -o json | jq '[.items[] | select(.metadata.labels["pod-security.kubernetes.io/enforce"] // "" | . != "" and . != "privileged")] | length')
r $( [ "$lab" -eq "$nsn" ] && echo PASS || echo FAIL ) "PSS enforced on all namespaces ($lab/$nsn have baseline/restricted)"
nomem=$(echo "$PODS" | jq '[.items[].spec.containers[] | select(.resources.limits.memory == null)] | length')
r $( [ $nomem -eq 0 ] && echo PASS || echo FAIL ) "memory limits set ($nomem containers without)"
r $(yes $(echo "$KUBELET" | jq '.seccompDefault == true')) "seccomp RuntimeDefault by default (kubelet seccompDefault)"
r INFO "AppArmor/SELinux: see ../linux-kernel-security-constraints (not usable on minikube docker driver)"

h "Logs and auditing"
r $(yes $(echo "$API" | grep -q -- '--audit-log-path' && echo true || echo false)) "audit logging enabled"

h "Secrets"
r $(yes $(echo "$API" | grep -q -- '--encryption-provider-config' && echo true || echo false)) "encryption at rest for Secrets"
mnt=$(echo "$PODS" | jq '[.items[] | select(.spec.automountServiceAccountToken != false)] | length'); tot=$(echo "$PODS" | jq '.items|length')
r INFO "$mnt/$tot Pods mount a ServiceAccount token (opt out where not needed)"
lt=$(kubectl get secrets -A --field-selector type=kubernetes.io/service-account-token --no-headers 2>/dev/null | wc -l)
r $( [ $lt -eq 0 ] && echo PASS || echo FAIL ) "no long-lived ServiceAccount token Secrets ($lt found)"

h "Images"
imgs=$(echo "$PODS" | jq -r '.items[].spec.containers[].image' | sort -u); dig=$(echo "$imgs" | grep -c '@sha256:'); all=$(echo "$imgs" | wc -l)
r $( [ $dig -eq $all ] && echo PASS || echo FAIL ) "images referenced by digest ($dig/$all)"
root=$(echo "$PODS" | jq '[.items[] | select((.spec.securityContext.runAsNonRoot // false) == false)] | length')
r INFO "$root/$tot Pods not declaring runAsNonRoot"

h "Admission controllers"
r INFO "enabled: $(echo "$API" | grep -- '--enable-admission-plugins' | cut -d= -f2)"
r INFO "webhooks: $(kubectl get validatingwebhookconfigurations,mutatingwebhookconfigurations --no-headers 2>/dev/null | wc -l)  ValidatingAdmissionPolicies: $(kubectl get validatingadmissionpolicies --no-headers 2>/dev/null | wc -l)"
