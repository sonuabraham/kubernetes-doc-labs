#!/usr/bin/env bash
# Everything ran on the throwaway profile svc-lab: delete it and start the default minikube again.
"$(dirname "$0")"/../extend-service-ip-ranges/svc-lab.sh delete
