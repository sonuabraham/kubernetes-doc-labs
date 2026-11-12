# Good Practices for DRA (Cluster Administrators) – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/cluster-administration/dra/

> No YAML on the page. The lab checks the two measurable parts, **permissions** and **metrics**, using the fake DRA driver from `../../resource-management/dynamic-resource-allocation` (`fake-dra.sh`). [00-personas.yaml](00-personas.yaml) binds an "operator" ServiceAccount to the built-in `edit` role and creates a metrics reader.

## Key ideas (read first)

| Topic | Good practice |
|---|---|
| **Permissions by persona** | DeviceClasses and ResourceSlices: admins and drivers only. ResourceClaims and ResourceClaimTemplates (namespaced): workload operators. Status writes: scheduler/drivers (granular, see `../../security/hardening-guide/dynamic-resource-allocation`). |
| **Driver lifecycle** | Prefer drivers with seamless upgrades. Use their liveness probe. When draining, drain the **driver last** so it can unprepare devices. |
| **Scale** | DRA scheduling means more API calls, CPU and memory in the scheduler and the ResourceClaim controller. Tune client QPS/burst (scale tests: controller-manager QPS 75 / burst 150 at 100 nodes). |
| **Metrics to watch** | controller-manager: `workqueue_adds_total / depth / work_duration_seconds{name="resource_claim"}`. Scheduler: `scheduler_plugin_execution_duration_seconds{plugin="DynamicResources"}`, pending Pods, bind latency. kubelet: `dra_operations_duration_seconds`, gRPC call metrics. |

---

## Lab 1 – What the built-in roles allow
```bash
cd concepts/cluster-administration/dra
kubectl apply -f 00-personas.yaml
A="--as=system:serviceaccount:dra-admin-lab:operator"
for c in "create resourceclaims -n dra-admin-lab" "create resourceclaimtemplates -n dra-admin-lab" "create deviceclasses" "create resourceslices" "create devicetaintrules"; do
  echo "$c: $(kubectl auth can-i $c $A)"; done
#   create resourceclaims: yes   create resourceclaimtemplates: yes      <- edit (via aggregation) covers the operator persona
#   create deviceclasses: no     create resourceslices: no    create devicetaintrules: no
kubectl auth can-i update resourceclaims --subresource=status -n dra-admin-lab $A        # no
kubectl auth can-i patch resourceclaims --subresource=binding -n dra-admin-lab $A        # no
```
The defaults already match the page's split. Careful with `kubectl auth can-i update resourceclaims/status`: that checks a claim **named** "status" and says *yes*. Use `--subresource=status`.

## Lab 2 – The metrics to watch
```bash
../../resource-management/dynamic-resource-allocation/fake-dra.sh up
# 3 Pods with a ResourceClaimTemplate (gpu.example.com) in dra-admin-lab, then:
T=$(kubectl create token metrics -n dra-admin-lab)
minikube ssh -- "curl -sk -H 'Authorization: Bearer $T' https://127.0.0.1:10257/metrics | grep -a 'name=\"resource_claim\"'"
#   workqueue_adds_total{name="resource_claim"} 153        workqueue_depth{name="resource_claim"} 0
minikube ssh -- "curl -sk -H 'Authorization: Bearer $T' https://127.0.0.1:10259/metrics | grep 'plugin=\"DynamicResources\"' | grep _count"
#   ...{extension_point="Filter",plugin="DynamicResources",status="Success"} 4
#   ...{extension_point="Filter",plugin="DynamicResources",status="UnschedulableAndUnresolvable"} 5
#   ...{extension_point="PostFilter",plugin="DynamicResources",status="Unschedulable"} 353
kubectl get pod -n kube-system -l component=kube-controller-manager -o json | jq -r '.items[0].spec.containers[0].command[]' | grep -E 'api-qps|api-burst'
#   (none) → client defaults 20 QPS / 30 burst
```
The counters are cumulative since the components started and include all the DRA labs in this repo, which is a reminder that dashboards should use `rate()`.

---

## Useful commands
```bash
kubectl auth can-i --list --as=<user> | grep resource.k8s.io
kubectl get clusterrole edit -o json | jq '.rules[] | select(.apiGroups|index("resource.k8s.io"))'
```

## Cleanup
```bash
./cleanup.sh
```
