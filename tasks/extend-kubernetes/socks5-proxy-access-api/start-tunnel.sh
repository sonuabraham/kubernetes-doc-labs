#!/usr/bin/env bash
# NOT from the docs: the docs' `ssh -D 1080 -q -N username@kubernetes-remote-server.example`, with the minikube node as the
# "remote server / bastion" (user docker, minikube's key, the SSH port Docker publishes on 127.0.0.1).
#   ./start-tunnel.sh        (runs in the background; PID in ./tunnel.pid)      kill $(cat tunnel.pid) to stop
cd "$(dirname "$0")" || exit 1
PORT=$(docker port minikube 22 | head -1 | cut -d: -f2)
ssh -D 1080 -q -N -i "$(minikube ssh-key)" -p "$PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null docker@127.0.0.1 &
echo $! > tunnel.pid; echo "SOCKS5 proxy on localhost:1080 (pid $(cat tunnel.pid))"
