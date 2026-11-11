#!/usr/bin/env bash
# Prints a connectivity matrix: which client pod can reach which service.
# Usage: ./test.sh            (in-cluster tests)
#        ./test.sh external   (also test egress to 1.1.1.1 / 1.0.0.1)

check() {   # check <ns> <pod> <url>
  if kubectl exec -n "$1" "$2" -- curl -s -o /dev/null -m 3 "$3" 2>/dev/null; then
    printf "  %-20s -> %-32s \e[32mALLOWED\e[0m\n" "$1/$2" "$3"
  else
    printf "  %-20s -> %-32s \e[31mBLOCKED\e[0m\n" "$1/$2" "$3"
  fi
}

echo "== Connectivity matrix =="
check np-demo frontend http://backend.np-demo
check np-demo frontend http://db.np-demo
check np-demo backend  http://db.np-demo
check np-demo backend  http://frontend.np-demo
check np-demo db       http://backend.np-demo
check other   outsider http://frontend.np-demo
check other   outsider http://backend.np-demo
check other   outsider http://db.np-demo

if [[ "$1" == "external" ]]; then
  echo "== External egress (frontend) =="
  check np-demo frontend https://1.1.1.1
  check np-demo frontend https://1.0.0.1
fi
