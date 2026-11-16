#!/usr/bin/env bash
# Delete the throwaway profile and bring the default cluster back.
minikube delete -p force-lab
minikube start
