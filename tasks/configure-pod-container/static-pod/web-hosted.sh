#!/usr/bin/env bash
# NOT from the docs. ./web-hosted.sh up|down  - try the web-hosted static Pod on the minikube node:
#   up  : serve static-web-url.yaml from the node (python3 http.server on 127.0.0.1:8099, systemd unit
#         lab-static-http), back up /var/lib/kubelet/config.yaml, add
#         staticPodURL: http://127.0.0.1:8099/static-web-url.yaml + httpCheckFrequency: 20s, restart the kubelet
#   down: restore the kubelet config, restart the kubelet, stop the web server
set -euo pipefail
cd "$(dirname "$0")"
case ${1:-up} in
up)
  minikube ssh -- "sudo mkdir -p /srv/static-pods"
  minikube cp static-web-url.yaml /srv/static-pods/static-web-url.yaml
  minikube ssh -- 'sudo systemctl stop lab-static-http 2>/dev/null; sudo systemctl reset-failed lab-static-http 2>/dev/null
    sudo systemd-run --unit=lab-static-http python3 -m http.server 8099 --bind 127.0.0.1 --directory /srv/static-pods >/dev/null
    sudo test -f /var/lib/kubelet/config.yaml.lab-orig || sudo cp /var/lib/kubelet/config.yaml /var/lib/kubelet/config.yaml.lab-orig
    sudo sed -i -e "s|^httpCheckFrequency: .*|httpCheckFrequency: 20s|" /var/lib/kubelet/config.yaml
    sudo grep -q "^staticPodURL:" /var/lib/kubelet/config.yaml || echo "staticPodURL: http://127.0.0.1:8099/static-web-url.yaml" | sudo tee -a /var/lib/kubelet/config.yaml >/dev/null
    sudo systemctl restart kubelet; sleep 2; systemctl is-active kubelet; sudo grep -E "^(staticPodURL|httpCheckFrequency|staticPodPath)" /var/lib/kubelet/config.yaml' ;;
down)
  minikube ssh -- 'sudo mv /var/lib/kubelet/config.yaml.lab-orig /var/lib/kubelet/config.yaml && sudo systemctl restart kubelet
    sudo systemctl stop lab-static-http 2>/dev/null; sudo rm -rf /srv/static-pods; systemctl is-active kubelet' ;;
esac
