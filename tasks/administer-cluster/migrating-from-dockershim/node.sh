#!/usr/bin/env bash
# ./node.sh '<shell command>'  - run as root on a minikube node. P=<profile> (default rt-lab: the Docker Engine
# + cri-dockerd node made by ./start-rt-lab.sh; P=minikube is the containerd node).
minikube ssh -p "${P:-rt-lab}" -- "sudo bash -c '$1'"
