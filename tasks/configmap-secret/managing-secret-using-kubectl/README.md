# Managing Secrets using kubectl – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/configmap-secret/managing-secret-using-kubectl/

> Runs on the default **minikube** cluster in namespace `secret-kubectl` (the docs use `default`). All commands are the docs' own,
> plus a few comparisons (double quotes, a missing `-n`, editing an immutable Secret).

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **`--from-literal`** | Quote with **single quotes**. In double quotes the shell expands `$…` and `\`. |
| **`--from-file`** | The key is the file name unless you write `key=path`. The content goes in byte for byte, so write files with `echo -n` (no trailing newline). |
| **base64 ≠ encryption** | `get`/`describe` hide values, but `-o jsonpath='{.data}'` plus `base64 -d` shows them to anyone allowed to read the Secret. See [encrypt-data](../../administer-cluster/encrypt-data/) for encryption at rest. |
| **`kubectl edit`** | Edits the **base64** values in `data`. Not possible on an `immutable` Secret. |

---

## Step 0
```bash
cd tasks/configmap-secret/managing-secret-using-kubectl
kubectl create namespace secret-kubectl; kubectl config set-context --current --namespace=secret-kubectl
```

## Lab 1 – Raw data (docs)
```bash
kubectl create secret generic db-user-pass --from-literal=username=admin --from-literal=password='S!B\*d$zDsb='
kubectl get secret db-user-pass -o jsonpath='{.data}'                      # {"password":"UyFCXCpkJHpEc2I9","username":"YWRtaW4="}
kubectl get secret db-user-pass -o jsonpath='{.data.password}' | base64 --decode     # S!B\*d$zDsb=
kubectl delete secret db-user-pass
kubectl create secret generic dq --from-literal=password="S!B\*d$zDsb="     # NOT from the docs: double quotes
kubectl get secret dq -o jsonpath='{.data.password}' | base64 -d           # S!B\*d=        <- $zDsb expanded to "" by the shell
```

## Lab 2 – Source files (docs)
```bash
echo -n 'admin' > ./username.txt
echo -n 'S!B\*d$zDsb=' > ./password.txt
kubectl create secret generic db-user-pass --from-file=./username.txt --from-file=./password.txt
kubectl get secret db-user-pass -o jsonpath='{.data}'
#   {"password.txt":"UyFCXCpkJHpEc2I9","username.txt":"YWRtaW4="}       <- keys = file names
kubectl delete secret db-user-pass
kubectl create secret generic db-user-pass --from-file=username=./username.txt --from-file=password=./password.txt
kubectl get secrets                                       # db-user-pass   Opaque   2
kubectl describe secret db-user-pass | sed -n '/^Data/,$p'
#   password:  12 bytes                                     <- S ! B \ * d $ z D s b = : the backslash is part of the password
#   username:  5 bytes
echo 'admin' > nl.txt                                      # NOT from the docs: without -n
kubectl create secret generic with-newline --from-file=username=nl.txt
kubectl get secret with-newline -o jsonpath='{.data.username}' | base64 -d | od -c | head -1
#   0000000   a   d   m   i   n  \n                       <- 6 bytes: a login with this username would fail
rm username.txt password.txt nl.txt
```

## Lab 3 – Edit (docs)
```bash
kubectl edit secrets db-user-pass             # opens $EDITOR on the base64 values. Scripted:
NEW=$(echo -n 'n3w-p@ss' | base64)
EDITOR="sed -i s/UyFCXCpkJHpEc2I9/$NEW/" kubectl edit secrets db-user-pass
kubectl get secret db-user-pass -o jsonpath='{.data.password}' | base64 --decode     # n3w-p@ss
kubectl create secret generic frozen --from-literal=k=v --dry-run=client -o json | jq '.immutable=true' | kubectl apply -f -
kubectl patch secret frozen -p '{"data":{"k":"eA=="}}'
#   The Secret "frozen" is invalid: data: Forbidden: field is immutable when `immutable` is set     (kubectl edit fails the same way)
```

## Useful commands
```bash
kubectl get secret <s> -o go-template='{{range $k,$v := .data}}{{$k}}={{$v|base64decode}}{{"\n"}}{{end}}'
kubectl create secret generic <s> --from-env-file=.env
```

## Cleanup (docs)
```bash
kubectl delete secret db-user-pass
kubectl config set-context --current --namespace=default
./cleanup.sh
```
