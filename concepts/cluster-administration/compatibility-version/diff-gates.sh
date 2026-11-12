#!/usr/bin/env bash
# diff-gates.sh <ctxA> <ctxB> - feature gates whose stage or on/off state differ between two API servers
g(){ kubectl --context $1 get --raw /metrics | grep '^kubernetes_feature_enabled' | sed -E 's/kubernetes_feature_enabled\{name="([^"]*)",stage="([^"]*)"\} (.)/\1 \2 \3/; s/^([^ ]+)  /\1 GA /' | sort -k1,1; }
join <(g $1) <(g $2) | awk -v a=$1 -v b=$2 'BEGIN{printf "%-45s %-14s %s\n","GATE",a,b} $2!=$4 || $3!=$5 {printf "%-45s %-6s %-7s %-6s %s\n",$1,$2,($3?"on":"off"),$4,($5?"on":"off")}'
