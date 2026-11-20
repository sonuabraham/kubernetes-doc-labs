#!/usr/bin/env bash
# The docs' commands, in order, for the machine made by standalone-machine.sh (run inside it as root:
#   docker cp docs-steps.sh kubelet-standalone:/root/ && docker exec -w /root kubelet-standalone bash docs-steps.sh <step>).
# Differences from the docs are marked "LAB:". Steps: prepare | crio | kubelet | pod | info
set -u
case ${1:?prepare|crio|kubelet|pod|info} in
prepare)
  sudo swapon --show                 # LAB: shows the HOST's swap (/proc/swaps is not namespaced) – do NOT swapoff here,
                                     #      it would turn off swap on the host. The kubelet config gets failSwapOn: false instead.
  cat /proc/sys/net/ipv4/ip_forward  # 1 already (the host's docker setup); the docs' sysctl file is then not needed
  ;;
crio)
  # LAB: the docs run the CRI-O static bundle installer (curl …/cri-o/packaging/main/get | sudo bash). kicbase already contains
  # CRI-O 1.35 + crun/runc/conmon + CNI plugins in the same layout; the installer's CNI config is written here verbatim from the page.
  sudo tee /etc/cni/net.d/11-crio-ipv4-bridge.conflist >/dev/null <<'EOF'
{
  "cniVersion": "1.0.0",
  "name": "crio",
  "plugins": [
    {
      "type": "bridge",
      "bridge": "cni0",
      "isGateway": true,
      "ipMasq": true,
      "hairpinMode": true,
      "ipam": {
        "type": "host-local",
        "routes": [
            { "dst": "0.0.0.0/0" }
        ],
        "ranges": [
            [{ "subnet": "10.85.0.0/16" }]
        ]
      }
    }
  ]
}
EOF
  sudo systemctl daemon-reload
  sudo systemctl enable --now crio.service
  sudo systemctl is-active crio.service
  /opt/cni/bin/bridge --version
  cat /etc/cni/net.d/11-crio-ipv4-bridge.conflist
  ;;
kubelet)
  sudo mkdir -p /etc/kubernetes/manifests
  sudo tee /etc/kubernetes/kubelet.yaml <<EOF
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
authentication:
  webhook:
    enabled: false # Do NOT use in production clusters!
authorization:
  mode: AlwaysAllow # Do NOT use in production clusters!
enableServer: false
logging:
  format: text
address: 127.0.0.1 # Restrict access to localhost
readOnlyPort: 10255 # Do NOT use in production clusters!
staticPodPath: /etc/kubernetes/manifests
containerRuntimeEndpoint: unix:///var/run/crio/crio.sock
EOF
  # LAB: the docs' "add failSwapOn: false if swap is enabled" (swap is the host's here)
  echo 'failSwapOn: false' | sudo tee -a /etc/kubernetes/kubelet.yaml
  chmod +x kubelet
  sudo cp kubelet /usr/bin/
  sudo tee /etc/systemd/system/kubelet.service <<EOF
[Unit]
Description=Kubelet

[Service]
ExecStart=/usr/bin/kubelet \
 --config=/etc/kubernetes/kubelet.yaml
Restart=always

[Install]
WantedBy=multi-user.target
EOF
  sudo systemctl daemon-reload
  sudo systemctl enable --now kubelet.service
  sleep 5
  sudo systemctl is-active kubelet.service
  curl -s http://localhost:10255/healthz?verbose; echo
  curl -s http://localhost:10255/pods | python3 -m json.tool    # LAB: no jq in kicbase; python3 -m json.tool instead of jq '.'
  ;;
pod)
  cat <<EOF > static-web.yaml
apiVersion: v1
kind: Pod
metadata:
  name: static-web
spec:
  containers:
    - name: web
      image: nginx
      ports:
        - name: web
          containerPort: 80
          protocol: TCP
EOF
  sudo cp static-web.yaml /etc/kubernetes/manifests/
  ;;
info)
  # LAB: jq '.items[].status.podIP' done with python3
  curl -s http://localhost:10255/pods | python3 -c 'import json,sys; [print(json.dumps(p["status"].get("podIP"))) for p in json.load(sys.stdin)["items"] or []]'
  IP=$(curl -s http://localhost:10255/pods | python3 -c 'import json,sys; print(json.load(sys.stdin)["items"][0]["status"]["podIP"])')
  curl -s http://$IP | head -4
  ;;
esac
