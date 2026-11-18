#!/usr/bin/env bash
# Everything lives on the throwaway profile: delete it and bring the default cluster back.
"$(dirname "$0")"/konn-lab.sh delete
