# Change the default StorageClass – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/administer-cluster/change-default-storage-class/

> Runs on the default **minikube** cluster. Its default class is `standard` (`k8s.io/minikube-hostpath`). [01-gold-storageclass.yaml](01-gold-storageclass.yaml) adds `gold`, the docs' second class name, on the same provisioner. The docs' `kubectl patch` commands are used **verbatim**. Extra files test the page's notes:
> - [02-claim-no-class.yaml](02-claim-no-class.yaml): a PVC with no `storageClassName`.
> - [03-static-pv-and-claim.yaml](03-static-pv-and-claim.yaml): `volumeName` with a mismatched class.
>
> [cleanup.sh](cleanup.sh) restores `standard` as the default.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **The default** | A StorageClass annotated `storageclass.kubernetes.io/is-default-class: "true"`. Any other value, or no annotation, means not default. |
| **Who uses it** | The `DefaultStorageClass` admission plugin fills `storageClassName` for PVCs that omit it, **at creation time**. Changing the default later doesn't move existing PVCs. |
| **Several defaults** | Allowed. New PVCs get the **most recently created** default, and `kubectl get sc` marks only that one `(default)`. |
| **No default** | A class-less PVC stays Pending with no class. Since 1.28 it's **retroactively** assigned when a default appears. |
| **Static PV + volumeName** | The PVC still gets the default class. If that differs from the PV's class, binding fails with `VolumeMismatch`. |
| **Addon managers** | Some installers re-create or re-mark their default class. minikube applies its `default-storageclass` addon at start; use `minikube addons disable default-storageclass`. |

---

## Step 0
```bash
cd tasks/administer-cluster/change-default-storage-class
kubectl create ns sc-demo
kubectl apply -f 01-gold-storageclass.yaml
claim(){ sed "s/NAME/$1/" 02-claim-no-class.yaml | kubectl apply -f -; }
scs(){ kubectl get pvc -n sc-demo -o custom-columns=PVC:.metadata.name,CLASS:.spec.storageClassName,STATUS:.status.phase; }
```

## Lab 1 – The docs' switch: standard → gold
```bash
kubectl get storageclass
#   NAME                 PROVISIONER                RECLAIMPOLICY   VOLUMEBINDINGMODE
#   csi-hostpath-sc      hostpath.csi.k8s.io        Delete          Immediate
#   gold                 k8s.io/minikube-hostpath   Delete          Immediate
#   standard (default)   k8s.io/minikube-hostpath   Delete          Immediate
kubectl patch storageclass standard -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
kubectl patch storageclass gold -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
kubectl get storageclass
#   gold (default)    k8s.io/minikube-hostpath ...
#   standard          k8s.io/minikube-hostpath ...
claim c1-gold-default; scs
#   c1-gold-default   gold    Bound
```

## Lab 2 – Two defaults
```bash
kubectl patch storageclass standard -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
kubectl get sc -o custom-columns=NAME:.metadata.name,DEFAULT:'.metadata.annotations.storageclass\.kubernetes\.io/is-default-class'
#   gold true     standard true          <- both annotated...
kubectl get sc
#   gold (default)  ...  standard  ...     <- ...but only the effective one (newest: gold) is marked
claim c2-two-defaults; scs
#   c2-two-defaults   gold    Bound        <- "most recently created default StorageClass"
```

## Lab 3 – No default, then retroactive assignment
```bash
for s in standard gold; do kubectl patch storageclass $s -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'; done
claim c3-no-default; scs
#   c3-no-default     <none>   Pending
kubectl patch storageclass gold -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
sleep 8; scs
#   c3-no-default     gold     Bound       <- class filled in after the fact (GA 1.28)
```

## Lab 4 – A static PV, volumeName, and the wrong default
```bash
kubectl apply -f 03-static-pv-and-claim.yaml          # PV class "standard"; PVC names the PV but no class
kubectl get pvc c4-volumename -n sc-demo -o custom-columns=PVC:.metadata.name,CLASS:.spec.storageClassName,STATUS:.status.phase
#   c4-volumename   gold    Pending
kubectl describe pvc c4-volumename -n sc-demo | tail -1
#   Warning  VolumeMismatch  persistentvolume-controller  Cannot bind to requested volume "static-pv": storageClassName does not match
```
Fix it by setting `storageClassName: standard` (or `""` for a class-less PV) on the claim explicitly.

---

## Useful commands
```bash
kubectl get sc
kubectl get sc -o custom-columns=NAME:.metadata.name,DEFAULT:'.metadata.annotations.storageclass\.kubernetes\.io/is-default-class'
kubectl patch storageclass <sc> -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

## Cleanup
```bash
./cleanup.sh      # sc-demo, static-pv, gold; standard default again
```
