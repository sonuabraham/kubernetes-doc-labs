#!/usr/bin/env bash
# Stop the SSH tunnel and remove the generated kubeconfig. Also run `unset https_proxy HTTPS_PROXY` in your shell.
cd "$(dirname "$0")" || exit 1
[ -f tunnel.pid ] && kill "$(cat tunnel.pid)" 2>/dev/null
rm -f tunnel.pid kubeconfig-socks5
