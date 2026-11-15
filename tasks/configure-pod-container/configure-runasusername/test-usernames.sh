#!/usr/bin/env bash
# NOT from the docs: send Pods with various runAsUserName values to the API server (server-side dry run,
# nothing is created) and print whether validation accepts them. Validation is done by kube-apiserver,
# so this works on a cluster with no Windows nodes.
try(){
  out=$(kubectl run rau-test --image=busybox --dry-run=server -o name \
    --overrides="$(jq -nc --arg u "$1" '{spec:{securityContext:{windowsOptions:{runAsUserName:$u}}}}')" 2>&1)
  if [[ $out == pod/* ]]; then printf '%-30s OK\n' "$(printf '%q' "$1")"
  else printf '%-30s REJECTED  %s\n' "$(printf '%q' "$1")" "$(sed 's/.*runAsUserName: //' <<<"$out" | cut -c1-110)"; fi
}
for u in "ContainerUser" "ContainerAdministrator" 'NT AUTHORITY\NETWORK SERVICE' 'NT AUTHORITY\LOCAL SERVICE' \
         'CONTOSO\WebApp1' 'contoso.com\WebApp1' \
         "" $'bad\x01name' 'DOMAIN\' 'A-NETBIOS-NAME-16\u' '.dom\u' 'my-dom-\u' 'a\b\c' \
         'abcdefghijklmnopqrstu' "$(printf 'u%.0s' {1..104})" "$(printf 'u%.0s' {1..105})" '...' '   ' 'user@corp' 'us:er' 'us[er]'; do
  try "$u"
done
