#!/usr/bin/env bash
# The docs' three-member example cluster, for real: containers member1..member3 at http://10.0.0.1..3 on a Docker
# network 10.0.0.0/24 (gateway moved to .254 so 10.0.0.1 is free), same etcd image as the Kubernetes cluster.
#   ./etcd-docker-cluster.sh up            start member1-3 (static bootstrap, --initial-cluster-state=new)
#   ./etcd-docker-cluster.sh fail member1  "the node dies": stop the container
#   ./etcd-docker-cluster.sh member4       start member4 at 10.0.0.4 with the docs' ETCD_* env vars (state existing)
#   ./etcd-docker-cluster.sh down          remove containers and network
#   etcdctl in the cluster:  docker exec member2 etcdctl ...
IMG=${IMG:-registry.k8s.io/etcd:3.7.0-0}; NET=etcd-lab-net
run(){ # name ip [extra docker args...]
  local n=$1 ip=$2; shift 2
  docker run -d --name "$n" --network $NET --ip "$ip" "$@" "$IMG" etcd --name "$n" \
    --data-dir /var/lib/etcd \
    --listen-client-urls "http://$ip:2379,http://127.0.0.1:2379" --advertise-client-urls "http://$ip:2379" \
    --listen-peer-urls "http://$ip:2380" --initial-advertise-peer-urls "http://$ip:2380" >/dev/null && echo "started $n ($ip)"
}
case $1 in
up)
  docker network create --subnet 10.0.0.0/24 --gateway 10.0.0.254 $NET >/dev/null
  CL="member1=http://10.0.0.1:2380,member2=http://10.0.0.2:2380,member3=http://10.0.0.3:2380"
  for i in 1 2 3; do
    run member$i 10.0.0.$i -e ETCD_INITIAL_CLUSTER="$CL" -e ETCD_INITIAL_CLUSTER_STATE=new -e ETCD_INITIAL_CLUSTER_TOKEN=docs-lab
  done ;;
fail) docker stop "${2:-member1}" >/dev/null && echo "stopped ${2:-member1}" ;;
member4)
  # the docs' step: export ETCD_NAME / ETCD_INITIAL_CLUSTER / ETCD_INITIAL_CLUSTER_STATE=existing, then "etcd [flags]"
  run member4 10.0.0.4 -e ETCD_INITIAL_CLUSTER="member2=http://10.0.0.2:2380,member3=http://10.0.0.3:2380,member4=http://10.0.0.4:2380" \
      -e ETCD_INITIAL_CLUSTER_STATE=existing ;;
down)
  docker rm -f member1 member2 member3 member4 >/dev/null 2>&1
  docker network rm $NET >/dev/null 2>&1; echo "removed" ;;
*) echo "usage: $0 up|fail <member>|member4|down"; exit 1 ;;
esac
