# Compatibility Version for Kubernetes Control Plane Components – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/cluster-administration/compatibility-version/

> No YAML on the page. A profile **`compat-lab`** ([start-compat-lab.sh](start-compat-lab.sh)) runs the **v1.37 binaries** with `--emulated-version=1.36` on the API server, controller-manager and scheduler. The main `minikube` cluster is the plain v1.37 reference. [diff-gates.sh](diff-gates.sh) compares feature gates between the two.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **`--emulated-version`** | A newer binary behaves like an older minor: features and APIs added after it are **unavailable**, things removed since are **available**. Must be ≤ the binary version (supported range in `--help`). |
| **Why** | Safer upgrades: roll out the new binaries first while still behaving like the old version, then raise the emulated version as a separate, reversible step. |
| **minCompatibilityVersion** | The oldest version the component stays compatible with (here 1.35). |
| **Feature gates** | Their stage and default follow the **emulated** version. |

---

## Lab 1 – Same binary, different version
```bash
cd concepts/cluster-administration/compatibility-version
./start-compat-lab.sh                 # --emulated-version=1.36
kubectl --context compat-lab version -o json | jq -c '.serverVersion | {gitVersion, emulationMajor, emulationMinor, minCompatibilityMajor, minCompatibilityMinor}'
#   {"gitVersion":"v1.37.0","emulationMajor":"1","emulationMinor":"36","minCompatibilityMajor":"1","minCompatibilityMinor":"35"}
kubectl --context minikube version -o json | jq -c '.serverVersion | {gitVersion, emulationMinor}'
#   {"gitVersion":"v1.37.0","emulationMinor":"37"}
```

## Lab 2 – Feature gates follow the emulated version
```bash
./diff-gates.sh minikube compat-lab
```
Measured (abridged, 34 gates differ):
```
GATE                                   minikube (1.37)   compat-lab (emulating 1.36)
ClusterTrustBundle                     GA     on         BETA   off
PodCertificateRequest                  GA     on         BETA   off
DRADeviceTaintRules                    GA     on         BETA   off
SELinuxMount                           GA     on         BETA   off
StorageVersionMigrator                 GA     on         BETA   off
DRADeviceTaints / DRAExtendedResource  GA     on         BETA   on
GenericWorkload                        BETA   off        ALPHA  off
MemoryQoS / HPAScaleToZero / PodsAPI   BETA   on         ALPHA  off
KubeProxyIPVS                          DEPRECATED on     GA     on
```

## Lab 3 – APIs follow it too
```bash
# api-resources served by 1.37 but not by the 1.36 emulation:
#   clustertrustbundles.certificates.k8s.io      podcertificaterequests.certificates.k8s.io
#   devicetaintrules.resource.k8s.io             storageversionmigrations.storagemigration.k8s.io
```
So the projected-volume `clusterTrustBundle`/`podCertificate` labs (`../../storage/projected-volumes`) wouldn't work on this cluster, although it runs exactly the same binaries.

```bash
./cleanup.sh       # stops compat-lab
```

---

## Useful commands
```bash
kubectl version -o json | jq .serverVersion
kubectl get --raw /metrics | grep kubernetes_feature_enabled
```
