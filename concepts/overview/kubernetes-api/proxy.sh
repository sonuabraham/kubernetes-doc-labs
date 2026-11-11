#!/usr/bin/env bash
# Start/stop "kubectl proxy" on 127.0.0.1:8001 so plain curl can talk to the API
# (the proxy adds your kubeconfig credentials).
# Usage: ./proxy.sh start | stop
PIDFILE=${TMPDIR:-/tmp}/k8s-api-lab-proxy.pid
case "$1" in
  start) if curl -s -m 1 localhost:8001/version >/dev/null; then echo "proxy already running"; exit 0; fi
         nohup kubectl proxy --port=8001 >/dev/null 2>&1 &
         echo $! > "$PIDFILE"
         for i in $(seq 30); do curl -s -m 1 localhost:8001/version >/dev/null && { echo "API proxy on http://localhost:8001"; exit 0; }; sleep 0.3; done
         echo "proxy did not start"; exit 1 ;;
  stop)  [ -f "$PIDFILE" ] && kill "$(cat "$PIDFILE")" 2>/dev/null && rm -f "$PIDFILE" && echo stopped ;;
  *)     echo "usage: $0 start|stop" ;;
esac
