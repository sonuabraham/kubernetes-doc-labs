#!/usr/bin/env bash
# cosign without installing it: Sigstore's official image, current directory mounted as the working dir.
# Usage: source ./cosign.sh   (defines a "cosign" shell function so the docs' commands run unchanged)
cosign(){ docker run --rm -v "$PWD":/w -w /w gcr.io/projectsigstore/cosign:v2.4.1 "$@"; }
