# Example: Deploying PHP Guestbook application with Redis – Hands-on Lab

Based on: https://kubernetes.io/docs/tutorials/stateless-application/guestbook/

> Runs on the default **minikube**, namespace `default`. The six manifests are the docs examples `application/guestbook/…` **verbatim**.
>
> **Found:**
> - **`kubectl logs deployment/redis-follower` shows the *leader's* log.** Both Redis Deployments select only `app: redis`, so for
>   kubectl `deployment/redis-follower` matches 3 Pods (`Found 3 pods, using pod/redis-leader-69555f5f9-dmdlf`). `kubectl exec
>   deploy/redis-follower` lands on the leader too. The controllers are fine, because each ReplicaSet adds `pod-template-hash` to its
>   selector. To see a follower, use its Pod name or `-l role=follower`.
> - Leader and followers run different Redis versions: the leader image (`registry.k8s.io/redis@sha256:cb11…`) is **Redis 2.8.19**, the
>   followers (`gb-redis-follower:v2`) are **Redis 6.2.17**. Replication still works (`master_link_status:up`, both followers
>   `connected_slaves … state=online`).
> - The frontend's JSON API ignores the `key` parameter and always uses the Redis key `guestbook`. Writes go to `redis-leader`, reads to
>   `redis-follower` (see `/var/www/html/guestbook.php` in the frontend Pod). The UI shows the entries as one comma-separated string.
> - `kubectl get pods -l app=guestbook -l tier=frontend`: the second `-l` replaces the first, so only `tier=frontend` filters.
>   (It works because only the frontend has that label.) `-l app=guestbook,tier=frontend` is the AND form.
> - The docs' cleanup output omits the `service "redis-…" deleted` lines; they appear.
>
> **On minikube:** the LoadBalancer variant (the page says uncomment `type: LoadBalancer`) needs a cloud. Here it's done with
> `kubectl patch` plus the fake LB controller from
> [tasks/…/create-external-load-balancer](../../../tasks/access-application-cluster/create-external-load-balancer/) (NOT from the docs).
> Its IP `203.0.113.200` only works inside the node.

## Key ideas (read first)

| Piece | Kind | Notes |
|---|---|---|
| `redis-leader` | Deployment (1) + ClusterIP Service | writes |
| `redis-follower` | Deployment (2) + ClusterIP Service | replicas of the leader (they find it by DNS name `redis-leader`); reads |
| `frontend` | Deployment (3) + Service (ClusterIP, optional LoadBalancer) | PHP + Predis; `GET_HOSTS_FROM=dns` → uses Service names |
| Access | `kubectl port-forward svc/frontend 8080:80`, or an external LB | |
| Scaling | `kubectl scale deployment frontend` | stateless → any number of replicas behind the Service |

## Lab 1 – Redis
```bash
kubectl apply -f redis-leader-deployment.yaml
kubectl get pods                                  # redis-leader-69555f5f9-dmdlf   1/1   Running
kubectl logs -f deployment/redis-leader           # Server started, Redis version 2.8.19 … ready to accept connections on port 6379
kubectl apply -f redis-leader-service.yaml
kubectl get service                               # redis-leader   ClusterIP   10.101.21.246   6379/TCP
kubectl apply -f redis-follower-deployment.yaml
kubectl get pods                                  # + redis-follower-7d98b98f46-754kf / -dqnn7
kubectl apply -f redis-follower-service.yaml
kubectl get service                               # + redis-follower   ClusterIP   10.98.255.130   6379/TCP
```
NOT from the docs – the overlapping selector, and replication:
```bash
kubectl logs deployment/redis-follower | head -1  # Found 3 pods, using pod/redis-leader-69555f5f9-dmdlf    <- leader!
kubectl logs -l role=follower --tail=3            # Connecting to MASTER redis-leader:6379 / MASTER <-> REPLICA sync started …
kubectl exec <follower-pod> -- redis-server --version     # Redis server v=6.2.17
kubectl exec <follower-pod> -- redis-cli info replication # role:slave  master_host:redis-leader  master_link_status:up
```

## Lab 2 – Frontend
```bash
kubectl apply -f frontend-deployment.yaml
kubectl get pods -l app=guestbook -l tier=frontend          # 3 × frontend-5f76567768-…  Running
kubectl apply -f frontend-service.yaml
kubectl get services                                        # frontend   ClusterIP   10.99.118.177   80/TCP
kubectl port-forward svc/frontend 8080:80                   # Forwarding from 127.0.0.1:8080 -> 80 / [::1]:8080 -> 80
# browser: http://localhost:8080 → "Guestbook" page with a Submit button. The UI calls the JSON API:
curl 'localhost:8080/guestbook.php?cmd=set&key=messages&value=,hello%20from%20the%20lab'   # {"message": "Updated"}
curl 'localhost:8080/guestbook.php?cmd=get&key=messages'                                  # {"data": ",hello from the lab"}
kubectl exec <follower-pod> -- redis-cli GET guestbook      # ,hello from the lab   (replicated; key is "guestbook", not "messages")
```
LoadBalancer variant (NOT from the docs as such; the docs edit the YAML):
```bash
../../../tasks/access-application-cluster/create-external-load-balancer/run-fake-lb.sh start
kubectl patch svc frontend -p '{"spec":{"type":"LoadBalancer"}}'
kubectl get service frontend                    # frontend   LoadBalancer   10.99.118.177   203.0.113.200   80:30711/TCP
minikube ssh -- "curl -s 'http://203.0.113.200/guestbook.php?cmd=get'"    # {"data": ",hello from the lab"}
```

## Lab 3 – Scale the frontend
```bash
kubectl scale deployment frontend --replicas=5
kubectl get pods                                  # 5 frontend + 2 follower + 1 leader
kubectl scale deployment frontend --replicas=2
kubectl get pods                                  # 2 frontend + 2 follower + 1 leader
```

## Cleanup
```bash
./cleanup.sh
#   docs: kubectl delete deployment -l app=redis ; kubectl delete service -l app=redis
#         kubectl delete deployment frontend ; kubectl delete service frontend      (+ stops the fake LB)
kubectl get pods                                  # No resources found in default namespace.
```
