# Migrate Replicated Control Plane To Use Cloud Controller Manager – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/administer-cluster/controller-manager-leader-migration/

> In-tree cloud providers were removed from kube-controller-manager (KCM) years ago. So this lab tests the **Leader Migration mechanism** itself, on a throwaway profile **`lm-lab`** (kubelet `--cloud-provider=external`):
> - KCM plays "version N".
> - The **fakecloud CCM** built in [../developing-cloud-controller-manager](../developing-cloud-controller-manager/) plays "version N+1". Its binary is needed here: build it there first.
>
> The docs' four `LeaderMigrationConfiguration` files are saved **verbatim** ([01-initial-kcm.yaml](01-initial-kcm.yaml), [02-wildcard.yaml](02-wildcard.yaml), [03-n-plus-1-ccm.yaml](03-n-plus-1-ccm.yaml), [04-wildcard-with-nodeipam.yaml](04-wildcard-with-nodeipam.yaml)). **All four are rejected by v1.37 binaries** (Lab 1), so minimally fixed copies are in [fixed/](fixed/). Helpers:
> - [kcm-migration.sh](kcm-migration.sh) turns Leader Migration on or off in the KCM static Pod (flags + `/etc/leadermigration.conf` mount).
> - [run-ccm.sh](run-ccm.sh) runs the CCM with Leader Migration.
>
> ⚠️ **Findings with v1.37:** the docs' configs no longer parse, and **kube-controller-manager crashes whenever it wins the migration Lease** (Lab 3).

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **Why** | During an HA control-plane upgrade, cloud controllers (`route`, `service`, `cloud-node-lifecycle`, optionally `nodeipam`) move from KCM (version N) to the CCM (N+1). Both run at the same time, and a controller must **never run in both**. |
| **Migration Lease** | `kube-system/cloud-provider-extraction-migration`. Whichever manager holds it runs the migrated controllers. Each manager still has its own main Lease for everything else. |
| **Config** | `LeaderMigrationConfiguration` (`controllermanager.config.k8s.io/v1`): `leaderName` plus `controllerLeaders: [{name, component}]`. `component: "*"` makes one file valid on both sides. Without a file, a built-in default applies. |
| **Flags** | `--enable-leader-migration`, `--leader-migration-config=/etc/leadermigration.conf` (mounted at the same path). N+1 KCM runs with `--cloud-provider=external` and **without** migration. |
| **RBAC** | Both managers need access to the migration Lease (patch their `system::leader-locking-*` Roles). |

---

## Step 0
```bash
cd tasks/administer-cluster/controller-manager-leader-migration
ls ../developing-cloud-controller-manager/fakecloud-ccm/bin/fakecloud-ccm      # build it there first
minikube start -p lm-lab --memory 2200 --cpus 2 --kubernetes-version v1.37.0 --extra-config=kubelet.cloud-provider=external
kubectl config use-context minikube; K="kubectl --context lm-lab"
```

## Lab 1 – The docs' configuration files vs v1.37
```bash
B=../developing-cloud-controller-manager/fakecloud-ccm/bin
for f in 0*.yaml; do echo "== $f"; $B/fakecloud-ccm --cloud-provider=fakecloud --enable-leader-migration --leader-migration-config=$f --kubeconfig=/dev/null 2>&1 | grep "command failed"; done
#   == 01-initial-kcm.yaml           err="strict decoding error: unknown field \"resourceLock\""
#   == 02-wildcard.yaml              err="yaml: line 8: did not find expected alphabetic or numeric character"     <- bare `*` = YAML alias
#   == 03-n-plus-1-ccm.yaml          err="strict decoding error: unknown field \"resourceLock\""
#   == 04-wildcard-with-nodeipam.yaml  (same YAML error; it also has a stray "-" before the last "component:")
diff 02-wildcard.yaml fixed/02-wildcard.yaml
#   < resourceLock: leases                    (removed - Leases are the only lock now)
#   <     component: *      >     component: "*"
for f in fixed/0*.yaml; do timeout 4 $B/fakecloud-ccm --cloud-provider=fakecloud --cloud-config=../developing-cloud-controller-manager/cloud-config.json \
  --enable-leader-migration --leader-migration-config=$f --kubeconfig=/dev/null --master=https://127.0.0.1:1 2>&1 | grep -m1 "starting leader migration"; done
#   controllermanager.go:250] starting leader migration        (x4 - all fixed files accepted)
```

## Lab 2 – RBAC for the migration Lease (the docs' commands)
```bash
$K patch -n kube-system role 'system::leader-locking-kube-controller-manager' -p '{"rules": [ {"apiGroups":[ "coordination.k8s.io"], "resources": ["leases"], "resourceNames": ["cloud-provider-extraction-migration"], "verbs": ["create", "list", "get", "update"] } ]}' --type=merge
#   role.rbac.authorization.k8s.io/system::leader-locking-kube-controller-manager patched
$K patch -n kube-system role 'system::leader-locking-cloud-controller-manager' -p '{"rules": [ {"apiGroups":[ "coordination.k8s.io"], "resources": ["leases"], "resourceNames": ["cloud-provider-extraction-migration"], "verbs": ["create", "list", "get", "update"] } ]}' --type=merge
#   Error from server (NotFound): roles.rbac.authorization.k8s.io "system::leader-locking-cloud-controller-manager" not found
```
The CCM Role only exists once a CCM is installed (its manifests create it). Also note that `--type=merge` **replaces** the whole `rules` list of the KCM Role. This lab's CCM runs outside the cluster with an admin kubeconfig, so it doesn't need the Role.

## Lab 3 – Version N: KCM with Leader Migration
```bash
./kcm-migration.sh on fixed/01-initial-kcm.yaml       # leader election on (minikube disables it), migration flags + mount
$K -n kube-system get lease
#   cloud-provider-extraction-migration   lm-lab_94ee9bc3-...      <- KCM holds the migration Lease...
#   kube-controller-manager               lm-lab_94ee9bc3-...      <- ...and its main Lease
minikube ssh -p lm-lab -- 'sudo bash -c "crictl logs \$(crictl ps -a -q --name kube-controller-manager | sed -n 2p) 2>&1 | grep -E \"migration|already registered\""'
#   "Successfully acquired lease" lock="kube-system/cloud-provider-extraction-migration"
#   "leader migration: starting migrated controllers."
#   "Error building controller context" err="failed to create informer name: informer name \"kube-controller-manager\" is already registered"
#   "migration leaderelection lost/stopped"
$K -n kube-system get po -l component=kube-controller-manager      # RESTARTS keeps increasing
```
This is a v1.37 kube-controller-manager bug: building the second (migrated-controllers) context registers an informer name that's already taken, and the process exits. It happens every time KCM wins the Lease, so it reproduces reliably.

## Lab 4 – Version N+1: CCM with Leader Migration
```bash
./run-ccm.sh start fixed/03-n-plus-1-ccm.yaml
$K create deploy web --image=nginx && $K expose deploy web --type=LoadBalancer --port=80
grep -E "leader migration|acquire|Starting \"" ccm.log
#   starting leader migration
#   "Successfully acquired lease" lock="kube-system/cloud-controller-manager"
#   leader migration: starting main controllers.
#   "Attempting to acquire leader lease..." lock="kube-system/cloud-provider-extraction-migration"
#   Starting "service-lb-controller"  "cloud-node-controller"  "cloud-node-lifecycle-controller"   <- once it holds the migration Lease
$K -n kube-system get lease
#   cloud-controller-manager              sonu-thinkPad-...      <- CCM main Lease
#   cloud-provider-extraction-migration   sonu-thinkPad-...      <- the migration Lease moved to the CCM (helped by KCM crashing)
$K get svc web                          # EXTERNAL-IP 203.0.113.200 - served by the CCM's service controller
$K get node lm-lab -o jsonpath='{.spec.providerID}'      # fakecloud://eu-lab-1a/lm-lab
```

## Lab 5 – Finish the upgrade: N+1 KCM without migration
```bash
./kcm-migration.sh off                  # the docs: N+1 KCM "MUST NOT have Leader Migration enabled"
$K -n kube-system get po -l component=kube-controller-manager      # 1/1 Running, 0 restarts - stable again
$K expose deploy web --type=LoadBalancer --port=80 --name=web2; $K get svc web2      # 203.0.113.201
```
**Default configuration**: `--enable-leader-migration` without `--leader-migration-config` (`./run-ccm.sh start` with no file):
```bash
#   starting leader migration ... "Attempting to acquire leader lease..." lock="kube-system/cloud-provider-extraction-migration"
```
**Disable afterwards** (optional): remove both flags and the mount from the CCM, delete `/etc/leadermigration.conf`.

---

## Useful commands
```bash
kubectl -n kube-system get lease
kubectl -n kube-system get lease cloud-provider-extraction-migration -o jsonpath='{.spec.holderIdentity}'
crictl logs <kcm-container> | grep -i migration
```

## Cleanup
```bash
./run-ccm.sh stop
minikube delete -p lm-lab
```
