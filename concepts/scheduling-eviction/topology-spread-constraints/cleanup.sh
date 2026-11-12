#!/usr/bin/env bash
"$(dirname "$0")"/../delete-ns.sh tsc-demo
for i in 1 2 3 4 5; do kubectl label node fake-$i node- zone- >/dev/null 2>&1; done
# this lab added fake-4/fake-5; shrink back with: ../fake-nodes.sh down && ../fake-nodes.sh up 3
true
