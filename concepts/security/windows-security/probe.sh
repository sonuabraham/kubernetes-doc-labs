#!/usr/bin/env bash
# Dry-runs Windows Pods (spec.os.name: windows) with one security setting each and prints what the API says.
B='{"apiVersion":"v1","kind":"Pod","metadata":{"name":"w"},"spec":{"os":{"name":"windows"},"containers":[{"name":"c","image":"mcr.microsoft.com/windows/nanoserver:ltsc2022"}]}}'
probe(){ printf '%-44s ' "$1"; echo "$B" | jq -c "$2" | kubectl apply -n winsec-demo --dry-run=server -f - 2>&1 | sed 's/.*is invalid: //' | cut -c1-150; }
kubectl create ns winsec-demo --dry-run=client -o yaml | kubectl apply -f - >/dev/null
probe "runAsUserName ContainerUser"            '.spec.securityContext.windowsOptions.runAsUserName="ContainerUser"'
probe "runAsUserName ContainerAdministrator"   '.spec.containers[0].securityContext.windowsOptions.runAsUserName="ContainerAdministrator"'
probe "runAsUserName DOMAIN\\user"             '.spec.securityContext.windowsOptions.runAsUserName="CONTOSO\\appuser"'
probe "runAsUserName with bad chars"           '.spec.securityContext.windowsOptions.runAsUserName="bad\"user"'
probe "runAsUserName too long (>256)"          ".spec.securityContext.windowsOptions.runAsUserName=\"$(head -c 300 /dev/zero | tr '\0' a)\""
probe "gmsaCredentialSpecName"                 '.spec.securityContext.windowsOptions.gmsaCredentialSpecName="webapp-gmsa"'
probe "runAsUser (Linux)"                      '.spec.securityContext.runAsUser=1000'
probe "seLinuxOptions (Linux)"                 '.spec.securityContext.seLinuxOptions={"type":"container_t"}'
probe "seccompProfile (Linux)"                 '.spec.securityContext.seccompProfile={"type":"RuntimeDefault"}'
probe "capabilities (Linux)"                   '.spec.containers[0].securityContext.capabilities={"drop":["ALL"]}'
probe "appArmorProfile (Linux)"                '.spec.containers[0].securityContext.appArmorProfile={"type":"RuntimeDefault"}'
probe "privileged"                             '.spec.containers[0].securityContext.privileged=true'
probe "hostProcess + hostNetwork"              '.spec.hostNetwork=true | .spec.securityContext.windowsOptions={"hostProcess":true,"runAsUserName":"NT AUTHORITY\\SYSTEM"}'
