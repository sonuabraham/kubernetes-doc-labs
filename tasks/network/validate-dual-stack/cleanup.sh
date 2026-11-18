#!/usr/bin/env bash
# Everything ran on the throwaway profile ds-lab: delete it and start the default minikube again.
"$(dirname "$0")"/ds-lab.sh delete
