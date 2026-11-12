#!/usr/bin/env bash
# Wraps each docs excerpt (0N-<name>-excerpt.yaml, verbatim "spec:" fragments) into a runnable Pod named <name>
# and prints the resulting manifests (apply them with:  ./make-pods.sh | kubectl apply -n rm-demo -f -)
cd "$(dirname "$0")"
for f in 0*-excerpt.yaml; do
  n=$(echo "$f" | sed 's/^0[0-9]-//; s/-excerpt.yaml$//')
  echo "---"; printf 'apiVersion: v1\nkind: Pod\nmetadata:\n  name: %s\n' "$n"; cat "$f"
done
