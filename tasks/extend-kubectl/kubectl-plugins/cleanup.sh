#!/usr/bin/env bash
# Remove the generated plugin directories (nothing was installed system-wide).
cd "$(dirname "$0")" && rm -rf plugins moreplugins
