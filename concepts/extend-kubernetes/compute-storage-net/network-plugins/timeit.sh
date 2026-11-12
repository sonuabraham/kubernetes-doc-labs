#!/usr/bin/env bash
# ./timeit.sh [MB=2|24] [context] - downloads MB megabytes from each server Pod via the client Pod and prints the time taken.
MB=${1:-2}; C="--context ${2:-$(kubectl config current-context)}"; NS=cni-demo
for s in server-free server-limited; do
  ip=$(kubectl $C get pod $s -n $NS -o jsonpath='{.status.podIP}')
  t0=$(date +%s.%N)
  kubectl $C exec client -n $NS -- wget -q -O /dev/null http://$ip:8080/${MB}mb
  t1=$(date +%s.%N)
  awk -v m=$MB -v s=$s -v a=$t0 -v b=$t1 'BEGIN{d=b-a; printf "%-15s %s MB in %6.2fs  = %7.2f Mbit/s\n", s, m, d, m*8/d}'
done
