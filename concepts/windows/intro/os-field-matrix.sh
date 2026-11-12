#!/usr/bin/env bash
# Server-side dry-runs a Pod with spec.os.name=windows plus ONE field each, and prints the API's verdict.
# Part 1: the 20 fields the page says must NOT be set. Part 2: fields the page calls unsupported on Windows
# but that the API does not police. Part 3: the reverse - Windows-only fields on a linux Pod.
NS=${NS:-win-intro}
base(){ echo "{\"apiVersion\":\"v1\",\"kind\":\"Pod\",\"metadata\":{\"name\":\"w\"},\"spec\":{\"os\":{\"name\":\"$1\"},\"containers\":[{\"name\":\"c\",\"image\":\"mcr.microsoft.com/windows/nanoserver:ltsc2022\"}]}}"; }
probe(){ local os=$1 label=$2 expr=$3
  out=$(base "$os" | jq -c "$expr" | kubectl apply -n "$NS" --dry-run=server -f - 2>&1)
  if echo "$out" | grep -q "created (server dry run)"; then v="ACCEPTED"; else v="REJECTED  $(echo "$out" | sed 's/.*is invalid: //; s/: Forbidden.*//' | cut -c1-90)"; fi
  printf '  %-62s %s\n' "$label" "$v"; }
kubectl create ns "$NS" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
C='.spec.containers[0].securityContext'
echo "== 1. Fields the page forbids with os.name=windows"
probe windows spec.hostPID                                   '.spec.hostPID=true'
probe windows spec.hostIPC                                   '.spec.hostIPC=true'
probe windows spec.securityContext.seLinuxOptions            '.spec.securityContext.seLinuxOptions={"type":"container_t"}'
probe windows spec.securityContext.seccompProfile            '.spec.securityContext.seccompProfile={"type":"RuntimeDefault"}'
probe windows spec.securityContext.fsGroup                   '.spec.securityContext.fsGroup=2000'
probe windows spec.securityContext.fsGroupChangePolicy       '.spec.securityContext.fsGroupChangePolicy="OnRootMismatch"'
probe windows spec.securityContext.sysctls                   '.spec.securityContext.sysctls=[{"name":"net.ipv4.ip_unprivileged_port_start","value":"0"}]'
probe windows spec.shareProcessNamespace                     '.spec.shareProcessNamespace=true'
probe windows spec.securityContext.runAsUser                 '.spec.securityContext.runAsUser=1000'
probe windows spec.securityContext.runAsGroup                '.spec.securityContext.runAsGroup=1000'
probe windows spec.securityContext.supplementalGroups        '.spec.securityContext.supplementalGroups=[3000]'
probe windows "containers[*].securityContext.seLinuxOptions"           "$C.seLinuxOptions={\"type\":\"container_t\"}"
probe windows "containers[*].securityContext.seccompProfile"           "$C.seccompProfile={\"type\":\"RuntimeDefault\"}"
probe windows "containers[*].securityContext.capabilities"             "$C.capabilities={\"drop\":[\"ALL\"]}"
probe windows "containers[*].securityContext.readOnlyRootFilesystem"   "$C.readOnlyRootFilesystem=true"
probe windows "containers[*].securityContext.privileged"               "$C.privileged=true"
probe windows "containers[*].securityContext.allowPrivilegeEscalation" "$C.allowPrivilegeEscalation=false"
probe windows "containers[*].securityContext.procMount"                "$C.procMount=\"Default\""
probe windows "containers[*].securityContext.runAsUser"                "$C.runAsUser=1000"
probe windows "containers[*].securityContext.runAsGroup"               "$C.runAsGroup=1000"
echo "== 2. Unsupported on Windows per the page, but not policed by the API"
probe windows "spec.hostNetwork"                              '.spec.hostNetwork=true'
probe windows "dnsPolicy: ClusterFirstWithHostNet"            '.spec.dnsPolicy="ClusterFirstWithHostNet"'
probe windows "emptyDir medium: Memory"                       '.spec.volumes=[{"name":"m","emptyDir":{"medium":"Memory"}}] | .spec.containers[0].volumeMounts=[{"name":"m","mountPath":"C:\\data"}]'
probe windows "volumeMounts mountPropagation"                 '.spec.volumes=[{"name":"m","emptyDir":{}}] | .spec.containers[0].volumeMounts=[{"name":"m","mountPath":"C:\\data","mountPropagation":"HostToContainer"}]'
probe windows "volumeDevices (raw block)"                     '.spec.volumes=[{"name":"b","persistentVolumeClaim":{"claimName":"x"}}] | .spec.containers[0].volumeDevices=[{"name":"b","devicePath":"/dev/xvda"}]'
probe windows "hugepages-2Mi limit"                           '.spec.containers[0].resources={"limits":{"hugepages-2Mi":"4Mi","memory":"100Mi"}}'
probe windows "terminationGracePeriodSeconds: 120"            '.spec.terminationGracePeriodSeconds=120'
echo "== 3. Allowed on Windows (the only Pod securityContext fields that work there)"
probe windows "securityContext.runAsNonRoot"                  '.spec.securityContext.runAsNonRoot=true'
probe windows "windowsOptions.runAsUserName"                  '.spec.securityContext.windowsOptions.runAsUserName="ContainerUser"'
probe windows "windowsOptions.hostProcess (needs hostNetwork)" '.spec.hostNetwork=true | .spec.securityContext.windowsOptions={"hostProcess":true,"runAsUserName":"NT AUTHORITY\\SYSTEM"}'
echo "== 4. The reverse: Windows-only fields on os.name=linux"
probe linux   "windowsOptions.runAsUserName"                  '.spec.securityContext.windowsOptions.runAsUserName="ContainerUser"'
probe linux   "no os field at all + windowsOptions"           'del(.spec.os) | .spec.securityContext.windowsOptions.runAsUserName="ContainerUser"'
