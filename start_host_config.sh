#!/usr/bin/env bash
set -euo pipefail

echo "==> Configuring host for vagrant-ansible-k8s cluster..."

# Static route for LoadBalancer IPs (172.17.0.0/24) via BIRD router's external interface
if ip route show | grep -q "172.17.0.0/24"; then
  echo "    Route 172.17.0.0/24 already exists, replacing with via 192.168.0.40..."
  sudo ip route replace 172.17.0.0/24 via 192.168.0.40
else
  echo "    Adding route 172.17.0.0/24 via 192.168.0.40..."
  sudo ip route add 172.17.0.0/24 via 192.168.0.40
fi

# KUBECONFIG
mkdir -p ~/.kube
sshpass -p vagrant ssh -o StrictHostKeyChecking=no vagrant@10.10.10.11 \
  "sudo cat /etc/kubernetes/admin.conf" > ~/.kube/config-vagrant-k8s 2>/dev/null
echo "    Kubeconfig saved to ~/.kube/config-vagrant-k8s"

export KUBECONFIG=~/.kube/config-vagrant-k8s
echo "    KUBECONFIG set to $KUBECONFIG"

echo ""
echo "==> Done. To persist KUBECONFIG in this shell, run:"
echo "    source start_host_config.sh"
echo ""
echo "==> Quick verification:"
echo "    kubectl get nodes"
echo "    curl http://172.17.0.1"
