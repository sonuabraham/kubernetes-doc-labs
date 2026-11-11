#!/usr/bin/env bash
# A toy ingress controller, to show what real ones (ingress-nginx, Traefik, …) do:
#  1. list Ingresses whose spec.ingressClassName == "toy" (ignore all others!)
#  2. render one nginx "server" block per host, one "location" per path
#  3. write it to ConfigMap toy-proxy-conf and roll the proxy if it changed
#  4. publish the proxy's address in each Ingress's status.loadBalancer
# Prefix paths only, no TLS, polling every 5s. Ctrl-C to stop.
NS=ingressctl-demo; last=""
while true; do
  conf=$(kubectl get ingress -A -o json | jq -r '
    [.items[] | select(.spec.ingressClassName=="toy") | . as $i | .spec.rules[] |
      "server { listen 80; server_name \(.host);\n" +
      ([.http.paths[] | "  location \(.path) { proxy_pass http://\(.backend.service.name).\($i.metadata.namespace).svc.cluster.local:\(.backend.service.port.number); }\n"] | join("")) +
      "}\n"] | join("")')
  full="server { listen 80 default_server; return 404 \"toy: no route\\n\"; }
$conf"
  if [ "$full" != "$last" ]; then
    kubectl create configmap toy-proxy-conf -n $NS --from-literal=default.conf="$full" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
    kubectl rollout restart deploy/toy-proxy -n $NS >/dev/null
    echo "$(date +%T) config changed -> proxy reloaded:"; echo "$conf" | sed 's/^/    /'
    last="$full"
  fi
  ip=$(kubectl get svc toy-proxy -n $NS -o jsonpath='{.spec.clusterIP}')
  for ing in $(kubectl get ingress -A -o json | jq -r '.items[] | select(.spec.ingressClassName=="toy") | "\(.metadata.namespace)/\(.metadata.name)"'); do
    kubectl patch ingress ${ing#*/} -n ${ing%%/*} --subresource=status --type=merge \
      -p "{\"status\":{\"loadBalancer\":{\"ingress\":[{\"ip\":\"$ip\"}]}}}" >/dev/null
  done
  sleep 5
done
