#!/usr/bin/env bash
# ./security-audit.sh [context]   READ-ONLY tour of the "Securing a Cluster" page against a minikube cluster:
# every check only reads configuration or makes an unauthenticated request; nothing is changed.
C=${1:-minikube}; K="kubectl --context $C"
IP=$(minikube ip -p "$C" 2>/dev/null)
node(){ minikube ssh -p "$C" -- "sudo bash -c '$1'" 2>/dev/null; }
APISRV=$(node 'cat /etc/kubernetes/manifests/kube-apiserver.yaml')
flag(){ local v; v=$(echo "$APISRV" | grep -oE -- "--$1=[^ ]*" | head -1); [ -n "$v" ] && echo "$v"; }
h(){ printf '\n== %s\n' "$1"; }

h "TLS for all API traffic"
printf '  plain http to :8443 -> %s\n' "$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 http://$IP:8443/version)"
printf '  https without trusting the CA -> %s\n' "$(curl -s -o /dev/null -w '%{http_code} (exit %{exitcode})' --max-time 3 https://$IP:8443/version)"
echo "  $(flag tls-cert-file)  $(flag client-ca-file)"

h "API authentication"
echo "  anonymous-auth flag: $(flag anonymous-auth || echo '(not set -> anonymous requests ENABLED)')"
printf '  anonymous GET /version   -> %s\n' "$(curl -sk -o /dev/null -w '%{http_code}' https://$IP:8443/version)"
printf '  anonymous GET /api/v1/namespaces -> %s\n' "$(curl -sk https://$IP:8443/api/v1/namespaces | python3 -c 'import json,sys;print(json.load(sys.stdin)["message"])')"

h "API authorization"
echo "  $(flag authorization-mode)"
printf '  anonymous GET /api/v1/secrets -> %s\n' "$(curl -sk -o /dev/null -w '%{http_code}' https://$IP:8443/api/v1/secrets)"
printf '  can kube-system:default SA do everything? %s\n' "$($K auth can-i '*' '*' --as=system:serviceaccount:kube-system:default 2>&1)"
printf '  can default SA list secrets?       %s\n' "$($K auth can-i list secrets -A --as=system:serviceaccount:default:default 2>&1)"
printf '  subjects bound to cluster-admin: %s\n' "$($K get clusterrolebindings -o jsonpath='{range .items[?(@.roleRef.name=="cluster-admin")]}{.metadata.name}{"["}{range .subjects[*]}{.kind}{":"}{.namespace}{"/"}{.name}{" "}{end}{"] "}{end}')"

h "Kubelet access"
node 'grep -A3 -E "^authentication:|^authorization:" /var/lib/kubelet/config.yaml; grep -E "^readOnlyPort" /var/lib/kubelet/config.yaml || echo "readOnlyPort: (unset -> 0, disabled)"' | sed 's/^/  /'
printf '  anonymous GET https://%s:10250/pods -> %s\n' "$IP" "$(curl -sk -o /dev/null -w '%{http_code}' --max-time 3 https://$IP:10250/pods)"
printf '  read-only port http://%s:10255/pods -> %s\n' "$IP" "$(curl -s -o /dev/null -w '%{http_code} (exit %{exitcode})' --max-time 3 http://$IP:10255/pods)"

h "Limiting resource usage (quotas / limit ranges per namespace)"
for ns in $($K get ns -o jsonpath='{.items[*].metadata.name}'); do
  printf '  %-28s quotas=%s limitranges=%s\n' "$ns" "$($K get resourcequota -n $ns --no-headers 2>/dev/null | wc -l)" "$($K get limitrange -n $ns --no-headers 2>/dev/null | wc -l)"
done

h "Container privileges (Pod Security Admission labels, seccomp default)"
$K get ns -L pod-security.kubernetes.io/enforce,pod-security.kubernetes.io/warn --no-headers | awk '{printf "  %-28s enforce=%s warn=%s\n",$1,($4==""?"-":$4),($5==""?"-":$5)}'
printf '  privileged containers running: %s\n' "$($K get po -A -o jsonpath='{range .items[*]}{range .spec.containers[?(@.securityContext.privileged==true)]}{.name}{" "}{end}{end}')"
echo "  kubelet seccompDefault: $(node 'grep -E "^seccompDefault" /var/lib/kubelet/config.yaml' || echo '(unset -> false: containers run Unconfined unless they ask)')"

h "Unwanted kernel modules (dccp, sctp)"
node 'for m in dccp sctp; do printf "  %-5s loaded=%s  blocked=%s\n" $m "$(lsmod | grep -qw $m && echo yes || echo no)" "$(grep -rqs "blacklist $m" /etc/modprobe.d && echo yes || echo no)"; done'

h "Network access"
printf '  NetworkPolicies: %s in %s namespaces\n' "$($K get netpol -A --no-headers 2>/dev/null | wc -l)" "$($K get netpol -A --no-headers 2>/dev/null | awk '{print $1}' | sort -u | wc -l)"

h "etcd access"
echo "  $(node 'grep -oE -- "--(listen-client-urls|client-cert-auth)=[^ ]*" /etc/kubernetes/manifests/etcd.yaml' | tr '\n' ' ')"
printf '  https://%s:2379/version without client cert -> %s\n' "$IP" "$(curl -sk -o /dev/null -w '%{http_code} (exit %{exitcode})' --max-time 3 https://$IP:2379/version)"

h "Audit logging"
echo "  $(flag audit-policy-file || echo 'audit-policy-file: (not set -> NO audit log)')  $(flag audit-log-path)"

h "Alpha/beta features"
echo "  apiserver: $(flag feature-gates || echo 'no --feature-gates')  $(flag runtime-config || echo 'no --runtime-config')"

h "Secrets encrypted at rest"
echo "  $(flag encryption-provider-config || echo 'encryption-provider-config: (not set -> Secrets stored in PLAINTEXT in etcd)')"

h "Credential lifetimes"
node 'for c in apiserver.crt apiserver-kubelet-client.crt; do printf "  %-30s %s\n" $c "$(openssl x509 -noout -enddate -in /var/lib/minikube/certs/$c)"; done'
printf '  legacy SA token Secrets: %s\n' "$($K get secrets -A --field-selector type=kubernetes.io/service-account-token --no-headers 2>/dev/null | wc -l)"
