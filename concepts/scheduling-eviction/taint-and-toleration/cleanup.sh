#!/usr/bin/env bash
"$(dirname "$0")"/../delete-ns.sh taint-demo
for n in fake-1 fake-2 fake-3; do for k in example-key key1 key2 other; do kubectl taint nodes $n $k- >/dev/null 2>&1; done; done
true
