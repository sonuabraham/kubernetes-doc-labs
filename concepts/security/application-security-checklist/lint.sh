#!/usr/bin/env bash
# lint.sh <file>  - grades the first Deployment in a manifest against the application security checklist
set -uo pipefail
D=$(kubectl apply --dry-run=client -f "$1" -o json 2>/dev/null | jq 'if .kind=="List" then .items[] else . end | select(.kind=="Deployment")' | jq -s '.[0]')
s=$(echo "$D" | jq '.spec.template.spec')
chk(){ r=$(echo "$s" | jq -r "$2"); printf '  [%s] %s\n' "$( [ "$r" = true ] && echo x || echo ' ')" "$1"; }
echo "$1: $(echo "$D" | jq -r .metadata.name)"
chk "dedicated ServiceAccount"                 '(.serviceAccountName // "default") != "default"'
chk "automountServiceAccountToken: false"      '.automountServiceAccountToken == false'
chk "runAsNonRoot: true"                       '.securityContext.runAsNonRoot == true'
chk "non-root runAsUser"                       '(.securityContext.runAsUser // 0) > 0'
chk "seccompProfile set"                       '.securityContext.seccompProfile != null'
chk "allowPrivilegeEscalation: false"          'all(.containers[]; .securityContext.allowPrivilegeEscalation == false)'
chk "readOnlyRootFilesystem: true"             'all(.containers[]; .securityContext.readOnlyRootFilesystem == true)'
chk "not privileged"                           'all(.containers[]; (.securityContext.privileged // false) == false)'
chk "capabilities drop ALL"                    'all(.containers[]; (.securityContext.capabilities.drop // []) | index("ALL") != null)'
chk "requests+limits (QoS)"                    'all(.containers[]; .resources.requests != null and .resources.limits.memory != null)'
chk "image pinned (no :latest/untagged)"       'all(.containers[]; .image | test(":latest$") or (test(":[^/]+$")|not) | not)'
