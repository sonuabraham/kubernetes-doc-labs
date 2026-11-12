#!/usr/bin/env bash
# runs against the wl-lab profile (kubectl config use-context wl-lab)
"$(dirname "$0")"/../delete-ns.sh gang-sched
