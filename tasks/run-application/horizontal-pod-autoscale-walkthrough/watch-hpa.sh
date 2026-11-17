#!/usr/bin/env bash
# NOT from the docs: print the HPA and Deployment every 15 s for N seconds (default 240), with elapsed time.
#   ./watch-hpa.sh [seconds]
DUR=${1:-240}; start=$(date +%s)
while :; do
  el=$(( $(date +%s) - start )); [ $el -gt $DUR ] && break
  printf '%4ss  %s | deploy %s\n' $el "$(kubectl get hpa php-apache --no-headers | tr -s ' ' | cut -d' ' -f3-7)" \
    "$(kubectl get deploy php-apache --no-headers | tr -s ' ' | cut -d' ' -f2)"
  timeout 15 tail -f /dev/null
done
