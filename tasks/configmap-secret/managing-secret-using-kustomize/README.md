# Managing Secrets using Kustomize – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/configmap-secret/managing-secret-using-kustomize/

> Runs on the default **minikube** cluster in namespace `secret-kust`. The page's three tabs are three directories, each with the
> docs' `kustomization.yaml` **verbatim**: [literals/](literals/), [files/](files/), [env/](env/). [env/.env.secret](env/.env.secret) is not from
> the docs (the page only names it).
> General Kustomize behaviour: [manage-kubernetes-objects/kustomization](../../manage-kubernetes-objects/kustomization/).
>
> **Found:** the docs' cleanup `kubectl delete secret db-user-pass` fails (`NotFound`). The generated Secret is called `db-user-pass-<hash>`.
> Use `kubectl delete -k <dir>`.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **secretGenerator** | Builds a Secret from `literals`, `files` (key = file name, or `key=file`) or `envs` (`.env` lines). No base64 by hand. |
| **Hash suffix** | The name gets a content hash (`database-creds-bkbd782d2c`). New content means a new Secret, and workloads in the same kustomization are updated to reference it, which triggers a rollout. |
| **Old versions stay** | `kubectl apply -k` doesn't delete the previous Secret. Prune them, or delete them yourself. |

---

## Step 0
```bash
cd tasks/configmap-secret/managing-secret-using-kustomize
kubectl create namespace secret-kust
```

## Lab 1 – The three ways to create it (docs tabs)
```bash
for d in literals files env; do kubectl apply -k $d -n secret-kust; kubectl get -k $d -n secret-kust -o jsonpath='{.data}'; echo; done
```
| Dir | Created | `.data` |
|---|---|---|
| literals | `secret/database-creds-bkbd782d2c` | `{"password":"MWYyZDFlMmU2N2Rm","username":"YWRtaW4="}` |
| files | `secret/database-creds-gd995d5t92` | `{"password.txt":"MWYyZDFlMmU2N2Rm","username.txt":"YWRtaW4="}`: keys are the **file names** |
| env | `secret/db-user-pass-bkbd782d2c` | `{"password":"MWYyZDFlMmU2N2Rm","username":"YWRtaW4="}` |
```bash
kubectl get -k literals -n secret-kust -o jsonpath='{.data.password}' | base64 --decode      # 1f2d1e2e67df
```
`literals` and `env` produce identical data, so they get the same hash `bkbd782d2c`: the hash doesn't depend on the name.

## Lab 2 – Edit (docs)
```bash
sed -i 's/password=1f2d1e2e67df/password=n3wpass/' literals/kustomization.yaml
kubectl apply -k literals -n secret-kust        # secret/database-creds-8k2t5kg262 created   <- a NEW object
kubectl get secrets -n secret-kust -o name | grep database-creds
#   database-creds-8k2t5kg262  database-creds-bkbd782d2c  database-creds-gd995d5t92        <- old ones still there
sed -i 's/password=n3wpass/password=1f2d1e2e67df/' literals/kustomization.yaml
```

## Lab 3 – Clean up (docs, and what works)
```bash
kubectl delete secret db-user-pass -n secret-kust
#   Error from server (NotFound): secrets "db-user-pass" not found
kubectl delete -k env -n secret-kust            # secret "db-user-pass-bkbd782d2c" deleted
./cleanup.sh                                    # the namespace, with all leftover versions
```
