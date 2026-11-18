#!/usr/bin/env bash
# Everything is on the throwaway profile ca-lab: delete it (plus work/ and the lab kubeconfig) and start the default minikube.
"$(dirname "$0")"/ca-rotation.sh delete
