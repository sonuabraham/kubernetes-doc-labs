#!/usr/bin/env bash
# NOT from the docs – run/stop the HAProxy load balancer container "k8s-api-lb" on the lab network (name = LOAD_BALANCER_DNS).
#   ./lb.sh up | down | log
cd "$(dirname "$0")"
case ${1:?up|down|log} in
  up)   docker run -d --name k8s-api-lb --network kubeadm-lab-net --label kubeadm-lab=1 \
          -v "$PWD/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro" haproxy:3.2-alpine >/dev/null
        docker inspect -f 'k8s-api-lb: {{(index .NetworkSettings.Networks "kubeadm-lab-net").IPAddress}}' k8s-api-lb ;;
  down) docker rm -f k8s-api-lb ;;
  log)  docker logs k8s-api-lb 2>&1 | tail -20 ;;
esac
