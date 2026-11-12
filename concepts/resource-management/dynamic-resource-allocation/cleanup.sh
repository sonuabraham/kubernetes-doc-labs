#!/usr/bin/env bash
# this lab's namespace; the shared fake driver stays for the sub-labs:  ./fake-dra.sh down  when done with DRA
"$(dirname "$0")"/../../scheduling-eviction/delete-ns.sh dra-demo
