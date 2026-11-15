#!/usr/bin/env bash
# NOT from the docs: variations of hostprocess-pod.yaml sent to the API server as a server-side dry run
# (nothing is created). Shows which HostProcess rules the API server enforces on its own.
cd "$(dirname "$0")"
BASE=$(kubectl create --dry-run=client -o json -f hostprocess-pod.yaml)
t(){ printf '%-28s ' "$1"; jq -c "$2" <<<"$BASE" | kubectl apply --dry-run=server -f - 2>&1 \
     | sed 's/^The Pod "hostprocess-demo" is invalid: //' | tr '\n' ' ' | cut -c1-330; echo; }
t "docs spec"                 '.'
t "no hostNetwork"            'del(.spec.hostNetwork)'
t "runAsNonRoot: true"        '.spec.securityContext.runAsNonRoot=true'
t "2nd ctr hostProcess:false" '.spec.containers += [{"name":"plain","image":"x","securityContext":{"windowsOptions":{"hostProcess":false}}}]'
t "2nd ctr, nothing set"      '.spec.containers += [{"name":"plain","image":"x"}]'
t "container-level only"      'del(.spec.securityContext.windowsOptions.hostProcess) | .spec.containers[0].securityContext={"windowsOptions":{"hostProcess":true}}'
t "ctr-level + plain 2nd ctr"   'del(.spec.securityContext.windowsOptions.hostProcess) | .spec.containers[0].securityContext={"windowsOptions":{"hostProcess":true}} | .spec.containers += [{"name":"plain","image":"x"}]'
t "spec.os: linux"            '.spec.os={"name":"linux"}'
t "spec.os: windows"          '.spec.os={"name":"windows"}'
t "local usergroup"           '.spec.securityContext.windowsOptions.runAsUserName="hpc-localgroup"'
