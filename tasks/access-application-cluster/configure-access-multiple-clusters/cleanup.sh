#!/usr/bin/env bash
# Remove the working copies (your ~/.kube/config is never modified by this lab when you follow the README).
rm -rf "$(dirname "$0")/config-exercise"
echo 'Also run in your shell:  export KUBECONFIG="$KUBECONFIG_SAVED"'
