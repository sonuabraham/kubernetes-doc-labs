#!/usr/bin/env bash
# Cleanup: the whole "machine" is a container – deleting it (and its /var volume) replaces the docs' Clean up section.
# Do NOT run the docs' "Container Runtime" cleanup on a real machine as written: it deletes ALL of /usr/local/bin, /usr/local/lib, /usr/local/share.
cd "$(dirname "$0")" && ./standalone-machine.sh down
