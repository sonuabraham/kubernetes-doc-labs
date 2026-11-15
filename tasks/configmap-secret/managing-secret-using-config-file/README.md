# Managing Secrets using Configuration File – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/configmap-secret/managing-secret-using-config-file/

> Runs on the default **minikube** cluster in namespace `secret-file` (the docs use `default`, so add `-n secret-file` or switch context).
> Files (docs, **verbatim**): [secret.yaml](secret.yaml), [secret-stringdata.yaml](secret-stringdata.yaml),
> [secret-data-and-stringdata.yaml](secret-data-and-stringdata.yaml), [secret-edited.yaml](secret-edited.yaml).
>
> **Found:** the page says `stringData` "does not work well with server-side apply". Measured: removing a key from `stringData` never removes it from
> the Secret, with server-side **and** client-side apply. (Also, the docs' `kubectl get secret mysecret -o yaml` sample decodes to
> `{{username}}`/`{{password}}`, not the `<user>`/`<password>` they apply. Here it decodes to exactly what was applied.)

## Key ideas (read first)

| Field | Meaning |
|---|---|
| `data` | base64 values. One line each: GNU `base64` wraps at 76 characters, so use `base64 -w 0` for long values. |
| `stringData` | plain values, **write-only**: converted into `data` on write, never stored or returned. Wins over `data` for the same key. |
| keys | `[-._a-zA-Z0-9]+` |
| editing | change the file and `kubectl apply` again (unless the Secret is `immutable`) |

---

## Step 0
```bash
cd tasks/configmap-secret/managing-secret-using-config-file
kubectl create namespace secret-file
echo -n 'admin' | base64           # YWRtaW4=
echo -n '1f2d1e2e67df' | base64    # MWYyZDFlMmU2N2Rm
```

## Lab 1 – `data` (docs)
```bash
kubectl apply -n secret-file -f secret.yaml                    # secret/mysecret created
kubectl get secret mysecret -n secret-file -o jsonpath='{.data}'      # {"password":"MWYyZDFlMmU2N2Rm","username":"YWRtaW4="}
kubectl delete secret mysecret -n secret-file
```

## Lab 2 – `stringData` (docs)
```bash
kubectl apply -n secret-file -f secret-stringdata.yaml
kubectl get secret mysecret -n secret-file -o json | jq -c '{data:(.data|keys), stringData}'
#   {"data":["config.yaml"],"stringData":null}             <- stored only as data
kubectl get secret mysecret -n secret-file -o jsonpath='{.data.config\.yaml}' | base64 -d
#   apiUrl: "https://my.api.com/api/v1"
#   username: <user>
#   password: <password>
kubectl delete secret mysecret -n secret-file
```

## Lab 3 – Both fields for the same key (docs)
```bash
kubectl apply -n secret-file -f secret-data-and-stringdata.yaml
kubectl get secret mysecret -n secret-file -o jsonpath='{.data.username}'       # YWRtaW5pc3RyYXRvcg==  -> administrator
kubectl delete secret mysecret -n secret-file
```

## Lab 4 – Edit by re-applying (docs)
```bash
kubectl apply -n secret-file -f secret.yaml
echo -n 'birdsarentreal' | base64                     # YmlyZHNhcmVudHJlYWw=
kubectl apply -n secret-file -f secret-edited.yaml    # secret/mysecret configured
kubectl get secret mysecret -n secret-file -o jsonpath='{.data.password}' | base64 -d     # birdsarentreal
```

## Lab 5 – The two notes, tested (not from the docs)
Wrapped base64 (the page's note about newlines):
```bash
LONG=$(head -c 120 /dev/zero | tr '\0' x)
echo -n "$LONG" | base64 | wc -l                       # 3   <- wrapped
printf 'apiVersion: v1\nkind: Secret\nmetadata: {name: wrapped}\ndata:\n  long: %s\n' "$(echo -n "$LONG" | base64)" | kubectl apply -n secret-file -f -
#   error: error parsing STDIN: error converting YAML to JSON: yaml: line 7: could not find expected ':'
printf '…same…' "$(echo -n "$LONG" | base64 -w 0)" | kubectl apply -n secret-file -f -       # secret/wrapped created
```
`stringData` and apply:
```bash
printf 'apiVersion: v1\nkind: Secret\nmetadata: {name: ssa}\nstringData:\n  a: one\n  b: two\n' | kubectl apply --server-side -n secret-file -f -
printf 'apiVersion: v1\nkind: Secret\nmetadata: {name: ssa}\nstringData:\n  a: ONE\n'         | kubectl apply --server-side -n secret-file -f -
kubectl get secret ssa -n secret-file -o json | jq -c '{data:(.data|map_values(@base64d))}'
#   {"data":{"a":"ONE","b":"two"}}          <- "b" was removed from the file but is still in the Secret
```
The same two steps with plain `kubectl apply` (client-side) give the same `{"a":"ONE","b":"two"}`. The live object never has a
`stringData` field, so neither apply mode can tell that `data.b` came from it. Use `data` for anything you'll remove later.

## Clean up (docs)
```bash
kubectl delete secret mysecret -n secret-file
./cleanup.sh          # deletes namespace secret-file
```
