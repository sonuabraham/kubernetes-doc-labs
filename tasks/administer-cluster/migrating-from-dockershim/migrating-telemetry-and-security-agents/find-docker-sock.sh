#!/usr/bin/env bash
# The docs' script, verbatim: namespace and name of every Pod with a hostPath volume of /var/run/docker.sock.
# Remove the last grep to review all hostPath mounts.   (pass --context X through: ./find-docker-sock.sh --context rt-lab)
kubectl "$@" get pods --all-namespaces \
-o=jsonpath='{range .items[*]}{"\n"}{.metadata.namespace}{":\t"}{.metadata.name}{":\t"}{range .spec.volumes[*]}{.hostPath.path}{", "}{end}{end}' \
| sort \
| grep '/var/run/docker.sock'
