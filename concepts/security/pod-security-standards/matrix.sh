#!/usr/bin/env bash
# For each control in the Pod Security Standards, build a Pod that violates ONLY that control
# (starting from a fully Restricted-compliant Pod) and dry-run it against the three namespaces.
set -uo pipefail
BASE='{"apiVersion":"v1","kind":"Pod","metadata":{"name":"t"},"spec":{
  "securityContext":{"runAsNonRoot":true,"runAsUser":1000,"seccompProfile":{"type":"RuntimeDefault"}},
  "containers":[{"name":"c","image":"busybox:1.36","securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}}]}}'
declare -a CASES=(
 "compliant (restricted)|."
 "hostNetwork|.spec.hostNetwork=true"
 "hostPID|.spec.hostPID=true"
 "hostIPC|.spec.hostIPC=true"
 "privileged|.spec.containers[0].securityContext.privileged=true|del(.spec.containers[0].securityContext.allowPrivilegeEscalation)"
 "capabilities.add NET_ADMIN|.spec.containers[0].securityContext.capabilities.add=[\"NET_ADMIN\"]"
 "capabilities.add CHOWN (baseline list)|.spec.containers[0].securityContext.capabilities.add=[\"CHOWN\"]"
 "capabilities.add NET_BIND_SERVICE|.spec.containers[0].securityContext.capabilities.add=[\"NET_BIND_SERVICE\"]"
 "hostPath volume|.spec.volumes=[{\"name\":\"h\",\"hostPath\":{\"path\":\"/etc\"}}]"
 "hostPort|.spec.containers[0].ports=[{\"containerPort\":80,\"hostPort\":8080}]"
 "appArmor Unconfined|.spec.containers[0].securityContext.appArmorProfile={\"type\":\"Unconfined\"}"
 "seLinux custom type|.spec.securityContext.seLinuxOptions={\"type\":\"spc_t\"}"
 "procMount Unmasked (+hostUsers:false)|.spec.containers[0].securityContext.procMount=\"Unmasked\"|.spec.hostUsers=false"
 "seccomp Unconfined|.spec.securityContext.seccompProfile={\"type\":\"Unconfined\"}"
 "unsafe sysctl|.spec.securityContext.sysctls=[{\"name\":\"kernel.msgmax\",\"value\":\"65536\"}]"
 "safe sysctl|.spec.securityContext.sysctls=[{\"name\":\"net.ipv4.ip_unprivileged_port_start\",\"value\":\"0\"}]"
 "emptyDir/configMap volumes|.spec.volumes=[{\"name\":\"e\",\"emptyDir\":{}}]"
 "nfs volume (non-core type)|.spec.volumes=[{\"name\":\"n\",\"nfs\":{\"server\":\"x\",\"path\":\"/\"}}]"
 "no allowPrivilegeEscalation:false|del(.spec.containers[0].securityContext.allowPrivilegeEscalation)"
 "no runAsNonRoot|del(.spec.securityContext.runAsNonRoot)"
 "runAsUser 0|.spec.containers[0].securityContext.runAsUser=0"
 "no seccompProfile|del(.spec.securityContext.seccompProfile)"
 "capabilities not dropping ALL|del(.spec.containers[0].securityContext.capabilities)"
 "no runAsNonRoot + hostUsers:false|del(.spec.securityContext.runAsNonRoot)|del(.spec.securityContext.runAsUser)|.spec.hostUsers=false"
 "plain pod, no securityContext|.spec={\"containers\":[{\"name\":\"c\",\"image\":\"busybox:1.36\"}]}"
)
printf '%-42s %-11s %-11s %-11s\n' CONTROL privileged baseline restricted
# DENIED = rejected by Pod Security Admission; INVALID = rejected by ordinary API validation
for c in "${CASES[@]}"; do
  name=${c%%|*}; expr=${c#*|}
  pod=$(echo "$BASE" | jq -c "$expr")
  row=$(printf '%-42s' "$name")
  for ns in pss-privileged pss-baseline pss-restricted; do
    out=$(echo "$pod" | kubectl apply -n $ns --dry-run=server -f - 2>&1)
    if [ $? -eq 0 ]; then r=allowed; elif echo "$out" | grep -q 'violates PodSecurity'; then r=DENIED; else r=INVALID; fi
    row="$row $(printf '%-11s' $r)"
  done
  echo "$row"
done
