# Kubernetes Concepts – Hands-on Labs

Mirrors https://kubernetes.io/docs/concepts/. Each folder is one docs page and contains:
`README.md` (key ideas table, demo app, numbered labs with expected output), numbered YAML files, and helper scripts (`cleanup.sh`, test scripts).
All labs target **minikube** (`minikube start`) unless the README says otherwise. Pages that need special hardware or OS (Windows nodes, GPUs, cloud LBs) simulate as much as possible and say clearly what can't run locally.

Status: ✅ lab written · ⬜ not yet

## ✅ [Overview](overview/) — `overview/`
- ✅ [Kubernetes Components](overview/components/)
- ✅ [Objects In Kubernetes](overview/working-with-objects/) — `overview/working-with-objects/`
  - ✅ [Object Management](overview/working-with-objects/object-management/)
  - ✅ [Object Names and IDs](overview/working-with-objects/names/)
  - ✅ [Labels and Selectors](overview/working-with-objects/labels/)
  - ✅ [Namespaces](overview/working-with-objects/namespaces/)
  - ✅ [Annotations](overview/working-with-objects/annotations/)
  - ✅ [Field Selectors](overview/working-with-objects/field-selectors/)
  - ✅ [Finalizers](overview/working-with-objects/finalizers/)
  - ✅ [Owners and Dependents](overview/working-with-objects/owners-dependents/)
  - ✅ [Recommended Labels](overview/working-with-objects/common-labels/)
  - ✅ [Storage Versions](overview/working-with-objects/storage-version/)
- ✅ [The Kubernetes API](overview/kubernetes-api/)
- ✅ [The kubectl command-line tool](overview/kubectl/)

## ✅ [Cluster Architecture](architecture/) — `architecture/` (2-node profile `arch-lab`)
- ✅ [Nodes](architecture/nodes/)
- ✅ [Control Plane ↔ Node Communication](architecture/control-plane-node-communication/)
- ✅ [Controllers](architecture/controller/)
- ✅ [Leases](architecture/leases/)
- ✅ [Cloud Controller Manager](architecture/cloud-controller/)
- ✅ [About cgroup v2](architecture/cgroups/)
- ✅ [Self-Healing](architecture/self-healing/)
- ✅ [Garbage Collection](architecture/garbage-collection/)
- ✅ [Mixed Version Proxy](architecture/mixed-version-proxy/)

## ✅ [Containers](containers/) — `containers/`
- ✅ [Images](containers/images/)
- ✅ [Container Environment](containers/container-environment/)
- ✅ [Runtime Class](containers/runtime-class/)
- ✅ [Container Lifecycle Hooks](containers/container-lifecycle-hooks/)
- ✅ [Container Runtime Interface (CRI)](containers/cri/)

## ✅ [Workloads](workloads/) — `workloads/`
- Pods — `workloads/pods/`
  - ✅ [Pods](workloads/pods/)
  - ✅ [Pod Lifecycle](workloads/pods/pod-lifecycle/)
  - ✅ [Pod Conditions](workloads/pods/pod-condition/)
  - ✅ [Init Containers](workloads/pods/init-containers/)
  - ✅ [Sidecar Containers](workloads/pods/sidecar-containers/)
  - ✅ [Ephemeral Containers](workloads/pods/ephemeral-containers/)
  - ✅ [Liveness, Readiness and Startup Probes](workloads/pods/probes/)
  - ✅ [Disruptions](workloads/pods/disruptions/)
  - ✅ [Pod Hostname](workloads/pods/pod-hostname/)
  - ✅ [Pod QoS Classes](workloads/pods/pod-qos/)
  - ✅ [Scheduling Group](workloads/pods/scheduling-group/)
  - ✅ [Static Pods](workloads/pods/static-pods/)
  - ✅ [User Namespaces](workloads/pods/user-namespaces/)
  - ✅ [Downward API](workloads/pods/downward-api/)
  - ✅ [Advanced Pod Configuration](workloads/pods/advanced-pod-config/)
- ✅ [Workload Management](workloads/controllers/) — `workloads/controllers/`
  - ✅ [Deployments](workloads/controllers/deployment/)
  - ✅ [ReplicaSet](workloads/controllers/replicaset/)
  - ✅ [StatefulSets](workloads/controllers/statefulset/)
  - ✅ [DaemonSet](workloads/controllers/daemonset/)
  - ✅ [Jobs](workloads/controllers/job/)
  - ✅ [TTL for Finished Jobs](workloads/controllers/ttlafterfinished/)
  - ✅ [CronJob](workloads/controllers/cron-jobs/)
  - ✅ [ReplicationController](workloads/controllers/replicationcontroller/)
- ✅ [Managing Workloads](workloads/management/)
- ✅ [Autoscaling Workloads](workloads/autoscaling/)
  - ✅ [Horizontal Pod Autoscaling](workloads/autoscaling/horizontal-pod-autoscale/)
  - ✅ [Vertical Pod Autoscaling](workloads/autoscaling/vertical-pod-autoscale/)
- ✅ [Workload API](workloads/workload-api/)
  - ✅ [Pod Group Disruption and Priority](workloads/workload-api/disruption-and-priority/)
  - ✅ [PodGroup Scheduling Policies](workloads/workload-api/policies/)
  - ✅ [Topology-Aware Workload Scheduling](workloads/workload-api/topology-aware-scheduling/)
  - ✅ [workloadbuilder Library](workloads/workload-api/workloadbuilder/)
- ✅ [PodGroup API](workloads/podgroup-api/) · ✅ [Lifecycle](workloads/podgroup-api/lifecycle/)
- ✅ [CompositePodGroup API](workloads/compositepodgroup-api/) · ✅ [Lifecycle](workloads/compositepodgroup-api/lifecycle/)

## ✅ [Services, Load Balancing, and Networking](services-networking/) — `services-networking/`
- ✅ [Service](services-networking/service/)
- ✅ [Ingress](services-networking/ingress/)
- ✅ [Ingress Controllers](services-networking/ingress-controllers/)
- ✅ [Gateway API](services-networking/gateway-api/)
- ✅ [EndpointSlices](services-networking/endpoint-slices/)
- ✅ [Network Policies](services-networking/network-policies/)
- ✅ [DNS for Services and Pods](services-networking/dns-pod-service/)
- ✅ [IPv4/IPv6 dual-stack](services-networking/dual-stack/)
- ✅ [Topology Aware Routing](services-networking/topology-aware-routing/)
- ✅ [Networking on Windows](services-networking/windows-networking/)
- ✅ [Service ClusterIP allocation](services-networking/cluster-ip-allocation/)
- ✅ [Service Internal Traffic Policy](services-networking/service-traffic-policy/)

## Storage — `storage/`
- ✅ [Volumes](storage/volumes/) · ⬜ [Persistent Volumes](storage/persistent-volumes/) · ⬜ [Projected Volumes](storage/projected-volumes/) · ⬜ [Ephemeral Volumes](storage/ephemeral-volumes/)
- ⬜ [Storage Classes](storage/storage-classes/) · ⬜ [Volume Attributes Classes](storage/volume-attributes-classes/) · ⬜ [Dynamic Provisioning](storage/dynamic-provisioning/)
- ⬜ [Volume Snapshots](storage/volume-snapshots/) · ⬜ [Volume Snapshot Classes](storage/volume-snapshot-classes/) · ⬜ [CSI Volume Cloning](storage/volume-pvc-datasource/)
- ⬜ [Volume Populators and Data Sources](storage/volume-populators-and-data-sources/) · ⬜ [Storage Capacity](storage/storage-capacity/) · ⬜ [Node-specific Volume Limits](storage/storage-limits/)
- ⬜ [Local ephemeral storage](storage/ephemeral-storage/) · ⬜ [Volume Health Monitoring](storage/volume-health-monitoring/) · ⬜ [Windows Storage](storage/windows-storage/)

## Configuration — `configuration/`
- ⬜ [ConfigMaps](configuration/configmap/) · ⬜ [Secrets](configuration/secret/) · ⬜ [Resource Management for Pods](configuration/manage-resources-containers/)
- ⬜ [kubeconfig Files](configuration/organize-cluster-access-kubeconfig/) · ⬜ [Windows Resource Management](configuration/windows-resource-management/)

## Security — `security/`
- ⬜ [Cloud Native Security](security/cloud-native-security/) · ⬜ [Pod Security Standards](security/pod-security-standards/) · ⬜ [Pod Security Admission](security/pod-security-admission/)
- ⬜ [Service Accounts](security/service-accounts/) · ⬜ [Pod Security Policies](security/pod-security-policy/) · ⬜ [Linux Nodes](security/linux-security/) · ⬜ [Windows Nodes](security/windows-security/)
- ⬜ [Controlling Access to the API](security/controlling-access/) · ⬜ [RBAC Good Practices](security/rbac-good-practices/) · ⬜ [Secrets Good Practices](security/secrets-good-practices/)
- ⬜ [Multi-tenancy](security/multi-tenancy/) · ⬜ [Hardening: Authentication](security/hardening-guide/authentication-mechanisms/) · ⬜ [Hardening: DRA](security/hardening-guide/dynamic-resource-allocation/) · ⬜ [Hardening: Scheduler](security/hardening-guide/scheduler/)
- ⬜ [API Server Bypass Risks](security/api-server-bypass-risks/) · ⬜ [Linux Kernel Security Constraints](security/linux-kernel-security-constraints/) · ⬜ [Security Checklist](security/security-checklist/) · ⬜ [Application Security Checklist](security/application-security-checklist/)

## Policies — `policy/`
- ⬜ [Limit Ranges](policy/limit-range/) · ⬜ [Resource Quotas](policy/resource-quotas/) · ⬜ [PID Limiting](policy/pid-limiting/) · ⬜ [Node Resource Managers](policy/node-resource-managers/)

## Scheduling, Preemption and Eviction — `scheduling-eviction/`
- ⬜ [kube-scheduler](scheduling-eviction/kube-scheduler/) · ⬜ [Multiple Schedulers](scheduling-eviction/running-multiple-schedulers/) · ⬜ [Assigning Pods to Nodes](scheduling-eviction/assign-pod-node/)
- ⬜ [Pod Overhead](scheduling-eviction/pod-overhead/) · ⬜ [Scheduling Readiness](scheduling-eviction/pod-scheduling-readiness/) · ⬜ [Topology Spread](scheduling-eviction/topology-spread-constraints/)
- ⬜ [Taints and Tolerations](scheduling-eviction/taint-and-toleration/) · ⬜ [Scheduling Framework](scheduling-eviction/scheduling-framework/) · ⬜ [Gang Scheduling](scheduling-eviction/gang-scheduling/)
- ⬜ [Scheduler Perf Tuning](scheduling-eviction/scheduler-perf-tuning/) · ⬜ [PodGroup Scheduling](scheduling-eviction/podgroup-scheduling/) · ⬜ [Bin Packing](scheduling-eviction/resource-bin-packing/)
- ⬜ [Workload-Aware Preemption](scheduling-eviction/workload-aware-preemption/) · ⬜ [Topology-Aware Scheduling](scheduling-eviction/topology-aware-scheduling/) · ⬜ [Priority and Preemption](scheduling-eviction/pod-priority-preemption/)
- ⬜ [Node-pressure Eviction](scheduling-eviction/node-pressure-eviction/) · ⬜ [API-initiated Eviction](scheduling-eviction/api-eviction/) · ⬜ [Node Declared Features](scheduling-eviction/node-declared-features/)

## Resource Management — `resource-management/`
- ⬜ [Resource managers](resource-management/resource-managers/) · ⬜ [Pod-level resource managers](resource-management/pod-level-resource-managers/)
- ⬜ [Dynamic Resource Allocation](resource-management/dynamic-resource-allocation/): ⬜ [API Objects](resource-management/dynamic-resource-allocation/dra-api/) · ⬜ [How DRA Works](resource-management/dynamic-resource-allocation/how-dra-works/) · ⬜ [Observability](resource-management/dynamic-resource-allocation/dra-observability/) · ⬜ [Features](resource-management/dynamic-resource-allocation/dra-features/) · ⬜ [Device Taints](resource-management/dynamic-resource-allocation/device-taints/)

## Cluster Administration — `cluster-administration/`
- ⬜ [Node Shutdowns](cluster-administration/node-shutdown/) · ⬜ [Swap](cluster-administration/swap-memory-management/) · ⬜ [Node Autoscaling](cluster-administration/node-autoscaling/) · ⬜ [Certificates](cluster-administration/certificates/)
- ⬜ [Cluster Networking](cluster-administration/networking/) · ⬜ [Observability](cluster-administration/observability/) · ⬜ [Admission Webhook Good Practices](cluster-administration/admission-webhooks-good-practices/) · ⬜ [DRA for Admins](cluster-administration/dra/)
- ⬜ [Logging Architecture](cluster-administration/logging/) · ⬜ [Compatibility Version](cluster-administration/compatibility-version/) · ⬜ [System Metrics](cluster-administration/system-metrics/) · ⬜ [kube-state-metrics](cluster-administration/kube-state-metrics/)
- ⬜ [System Logs](cluster-administration/system-logs/) · ⬜ [System Traces](cluster-administration/system-traces/) · ⬜ [Proxies](cluster-administration/proxies/) · ⬜ [API Priority and Fairness](cluster-administration/flow-control/)
- ⬜ [Installing Addons](cluster-administration/addons/) · ⬜ [Coordinated Leader Election](cluster-administration/coordinated-leader-election/)

## Windows in Kubernetes — `windows/`
- ⬜ [Windows containers](windows/intro/) · ⬜ [User Guide](windows/user-guide/)

## Extending Kubernetes — `extend-kubernetes/`
- ⬜ [Network Plugins](extend-kubernetes/compute-storage-net/network-plugins/) · ⬜ [Device Plugins](extend-kubernetes/compute-storage-net/device-plugins/)
- ⬜ [Custom Resources](extend-kubernetes/api-extension/custom-resources/) · ⬜ [API Aggregation Layer](extend-kubernetes/api-extension/apiserver-aggregation/)
- ⬜ [Operator pattern](extend-kubernetes/operator/)
