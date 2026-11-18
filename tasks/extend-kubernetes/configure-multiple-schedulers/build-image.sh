#!/usr/bin/env bash
# NOT from the docs: build the second-scheduler image straight into minikube under the name the docs' Deployment
# uses (gcr.io/my-gcp-project/my-kube-scheduler:1.0), so my-scheduler.yaml works unchanged without pushing anywhere.
cd "$(dirname "$0")/image" && minikube image build -t gcr.io/my-gcp-project/my-kube-scheduler:1.0 .
