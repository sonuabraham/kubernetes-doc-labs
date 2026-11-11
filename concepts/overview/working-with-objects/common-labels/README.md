# Recommended Labels – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/overview/working-with-objects/common-labels/

> These labels are **recommended, not required**. No core component depends on them. They exist so that tools (Helm, dashboards, kubectl, GitOps tools) and people can describe and query **applications** the same way.

## Key ideas (read first)

| Label | Meaning | Example |
|---|---|---|
| `app.kubernetes.io/name` | Name of the application | `mysql` |
| `app.kubernetes.io/instance` | Unique name of **this installation** of the application | `mysql-abcxyz` |
| `app.kubernetes.io/version` | Current version (SemVer, revision hash…) | `5.7.21` |
| `app.kubernetes.io/component` | Component within the architecture | `database` |
| `app.kubernetes.io/part-of` | The higher-level application this belongs to | `wordpress` |
| `app.kubernetes.io/managed-by` | Tool that manages it | `Helm` |

| Concept | Meaning |
|---|---|
| **Application** | Kubernetes isn't a PaaS. It has **no formal "application" object**. An application is defined only by this metadata. |
| **Shared prefix** | `app.kubernetes.io/` keeps shared labels apart from your own unprefixed labels such as `app` or `tier`. |
| **Apply everywhere** | Put them on **every** object of the app (Deployments, StatefulSets, Services, ConfigMaps…) to get the full benefit. |
| **name vs instance** | One application can be installed several times, even in one namespace. `name` stays `wordpress`, while `instance` (`wordpress-abcxyz`) tells the installations apart. |
| **Selectors** | Use the stable labels (`name` + `instance`) in selectors. Keep `version` out: a selector can't change, but the version does. |

## The demo app
The docs examples are **excerpts** that end in `...`. Each file keeps the docs' `metadata.labels` block **verbatim** and fills in the minimum (name, namespace, spec) needed to apply it. Containers run the tiny `pause` image, since only labels matter here.

| File | Docs section |
|---|---|
| [01-mysql-statefulset-excerpt.yaml](01-mysql-statefulset-excerpt.yaml) | The first StatefulSet example (`mysql-abcxyz`) |
| [02-simple-stateless-service.yaml](02-simple-stateless-service.yaml) | A Simple Stateless Service (`myservice-abcxyz`) |
| [03-wordpress-with-database.yaml](03-wordpress-with-database.yaml) | Web Application With A Database (WordPress + MySQL) |
| [04-wordpress-second-instance.yaml](04-wordpress-second-instance.yaml) | Extra: a **second** WordPress install (`wordpress-blog2`, `mysql-blog2`) |

---

## Step 1
```bash
cd concepts/overview/working-with-objects/common-labels
kubectl apply -f 00-namespace.yaml
kubectl apply -f 01-mysql-statefulset-excerpt.yaml -f 02-simple-stateless-service.yaml
kubectl apply -f 03-wordpress-with-database.yaml           # statefulset.apps/mysql-abcxyz unchanged - same object as file 01
kubectl apply -f 04-wordpress-second-instance.yaml
```

## Lab 1 – See the application structure
```bash
kubectl get deploy,sts,svc -n common-labels-demo \
  -L app.kubernetes.io/name,app.kubernetes.io/instance,app.kubernetes.io/component,app.kubernetes.io/part-of
```
Expected:
```
NAME                               NAME        INSTANCE           COMPONENT   PART-OF
deployment.apps/myservice-abcxyz   myservice   myservice-abcxyz
deployment.apps/wordpress-abcxyz   wordpress   wordpress-abcxyz   server      wordpress
deployment.apps/wordpress-blog2    wordpress   wordpress-blog2    server      wordpress
statefulset.apps/mysql-abcxyz      mysql       mysql-abcxyz       database    wordpress
statefulset.apps/mysql-blog2       mysql       mysql-blog2        database    wordpress
service/...                        (the same columns for every Service)
```
MySQL carries information about **itself** (`name: mysql`) **and** the larger application (`part-of: wordpress`).

## Lab 2 – Query the application
```bash
kubectl get all -n common-labels-demo -l app.kubernetes.io/part-of=wordpress -o name          # both WordPress sites + their DBs
kubectl get all -n common-labels-demo -l app.kubernetes.io/instance=wordpress-abcxyz -o name  # ONE installation's web tier
kubectl get sts,svc -n common-labels-demo -l app.kubernetes.io/component=database -o name     # every database
kubectl get deploy,sts,svc -n common-labels-demo -l app.kubernetes.io/managed-by=Helm -o name # 8 objects "owned" by Helm
kubectl get deploy,sts,svc -n common-labels-demo -l '!app.kubernetes.io/managed-by' -o name   # myservice - managed by hand
kubectl get all -n common-labels-demo -l 'app.kubernetes.io/name=wordpress,app.kubernetes.io/version!=4.9.4'   # anything to upgrade?
```

## Lab 3 – Two instances of the same application
```bash
kubectl get deploy -n common-labels-demo -l app.kubernetes.io/name=wordpress \
  -o custom-columns=NAME:.metadata.name,INSTANCE:.metadata.labels.app\\.kubernetes\\.io/instance,SELECTOR:.spec.selector.matchLabels
```
Both Deployments have `name=wordpress`. The **instance** label keeps their selectors, and therefore their pods, apart. Try it: create a third Deployment that reuses `instance: wordpress-abcxyz` and watch the two fight over one Service's endpoints. That's why instance names must be unique.

## Lab 4 – Operate on a whole application
```bash
kubectl scale deploy,sts -n common-labels-demo -l app.kubernetes.io/instance=wordpress-blog2 --replicas=0
kubectl get deploy,sts -n common-labels-demo -l app.kubernetes.io/part-of=wordpress
kubectl delete all -n common-labels-demo -l app.kubernetes.io/instance in (wordpress-blog2,mysql-blog2)   # quote the selector!
kubectl delete all -n common-labels-demo -l 'app.kubernetes.io/instance in (wordpress-blog2,mysql-blog2)'
```
The first `delete` fails because the unquoted `(` is a shell error. The quoted one removes the second site and nothing else.

## Lab 5 – Who sets these labels for you?
```bash
kubectl create deployment plain --image=nginx -n common-labels-demo --dry-run=client -o jsonpath='{.metadata.labels}{"\n"}'
#   {"app":"plain"}        <- kubectl create uses a private "app" label, not the recommended ones
```
Helm charts (`managed-by: Helm`), Kustomize `labels:` and most operators add the `app.kubernetes.io/*` set. The guestbook example in [../labels](../labels/) uses both `app` (handy for typing) and `app.kubernetes.io/name` (for tools).

---

## Useful commands
```bash
kubectl get all -l app.kubernetes.io/part-of=<app>
kubectl get all -l app.kubernetes.io/instance=<instance> -L app.kubernetes.io/version
kubectl get deploy -A -L app.kubernetes.io/name,app.kubernetes.io/managed-by
```

## Cleanup
```bash
./cleanup.sh
```
