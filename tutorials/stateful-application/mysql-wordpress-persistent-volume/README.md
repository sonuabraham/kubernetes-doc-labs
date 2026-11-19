# Example: Deploying WordPress and MySQL with Persistent Volumes – Hands-on Lab

Based on: https://kubernetes.io/docs/tutorials/stateful-application/mysql-wordpress-persistent-volume/

> Runs on the default **minikube**, namespace `default` (default StorageClass `standard`, `k8s.io/minikube-hostpath`).
> [mysql-deployment.yaml](mysql-deployment.yaml) and [wordpress-deployment.yaml](wordpress-deployment.yaml) are the docs examples **verbatim**.
> [kustomization.yaml](kustomization.yaml) is exactly what the page's two heredocs produce, with `YOUR_PASSWORD` replaced by the lab password
> `lab-Passw0rd`. Change it if you like; this cluster is local only.
>
> **Notes:**
> - PVCs bound **immediately** (`standard` is `Immediate`), not "after a few minutes". Both Pods were `Running` after ~90 s (image pulls).
> - `kubectl get pods` shows **two** Pods (`wordpress-…` and `wordpress-mysql-…`); the page's sample lists only the MySQL one.
> - The Secret gets a content-hash suffix (`mysql-pass-f754tbdc64`), and kustomize rewrites both Deployments' `secretKeyRef.name` to it.
>   That's why the YAML can say just `mysql-pass`.
> - The second heredoc **appends** (`>>`). Run it twice and `kustomization.yaml` has two `resources:` keys. Check the file before `apply -k`.
> - The page warns not to leave WordPress on the setup page. This lab completes the installation with `curl` (NOT from the docs), which
>   also proves that WordPress reached MySQL through the headless `wordpress-mysql` Service.

## Key ideas (read first)

| Piece | Meaning |
|---|---|
| `secretGenerator` | kustomize creates `mysql-pass-<hash>` from literals; a changed password → new name → Deployments roll |
| `kubectl apply -k ./` / `delete -k ./` | build the kustomization and apply/delete everything in it |
| PVC without `storageClassName` | default StorageClass → PV provisioned dynamically (hostPath on minikube: dev/test only) |
| `strategy: Recreate` | old Pod stops before the new one starts. Needed for RWO volumes and a single MySQL |
| `wordpress-mysql` Service `clusterIP: None` | headless; WordPress uses the DNS name `wordpress-mysql` |
| `type: LoadBalancer` on minikube | `EXTERNAL-IP` stays `<pending>`; use the NodePort, `minikube service wordpress --url` |

## Lab
```bash
cat <<EOF >./kustomization.yaml
secretGenerator:
- name: mysql-pass
  literals:
  - password=lab-Passw0rd
EOF
cat <<EOF >>./kustomization.yaml
resources:
  - mysql-deployment.yaml
  - wordpress-deployment.yaml
EOF
kubectl apply -k ./
#   secret/mysql-pass-f754tbdc64 created, service/wordpress, service/wordpress-mysql, 2 PVCs, 2 Deployments created
kubectl get secrets                          # mysql-pass-f754tbdc64   Opaque   1
kubectl get pvc
#   mysql-pv-claim   Bound   pvc-7ebdb219-…   20Gi   RWO   standard
#   wp-pv-claim      Bound   pvc-43ef6d6e-…   20Gi   RWO   standard
kubectl get pods
#   wordpress-5bf87f5c4c-rzzg7        1/1   Running   0   89s
#   wordpress-mysql-995dbc867-kfdcx   1/1   Running   0   89s
kubectl get services wordpress               # wordpress   LoadBalancer   10.109.88.130   <pending>   80:32403/TCP
minikube service wordpress --url             # http://192.168.58.2:32403
# browser → "WordPress › Installation" (language selection)
curl -s -o /dev/null -w '%{http_code} -> %{redirect_url}\n' http://192.168.58.2:32403/    # 302 -> …/wp-admin/install.php
```
NOT from the docs – install WordPress without a browser, then check persistence:
```bash
U=$(minikube service wordpress --url)
curl -s "$U/wp-admin/install.php?step=2" --data-urlencode 'weblog_title=k8s lab' --data-urlencode 'user_name=labadmin' \
  --data-urlencode 'admin_password=Lab-WP-pass-2026!' --data-urlencode 'admin_password2=Lab-WP-pass-2026!' --data-urlencode 'pw_weak=1' \
  --data-urlencode 'admin_email=admin@example.com' --data-urlencode 'blog_public=0' | grep -o '<h1>[^<]*</h1>'     # <h1>Success!</h1>
curl -s $U/ | grep -o '<title>[^<]*</title>'                     # <title>k8s lab</title>
kubectl exec deploy/wordpress-mysql -- sh -c 'mysql -uwordpress -p"$MYSQL_PASSWORD" wordpress -N -e "select option_value from wp_options where option_name=\"blogname\""'
#   k8s lab
kubectl delete pod -l app=wordpress                              # both Pods replaced
curl -s $U/ | grep -o '<title>[^<]*</title>'                     # <title>k8s lab</title>   <- DB and files on the PVs survived
kubectl get deploy wordpress -o jsonpath='{.spec.template.spec.containers[0].env[1].valueFrom.secretKeyRef.name}'   # mysql-pass-f754tbdc64
```

## Cleanup
```bash
kubectl delete -k ./        # Secret, 2 Services, 2 PVCs, 2 Deployments; the PVs go too (reclaim policy Delete)
```
or `./cleanup.sh`.
