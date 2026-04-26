#!/usr/bin/env bash
set -euo pipefail

echo "==> Configuring host for vagrant-ansible-k8s cluster..."

# Static route for LoadBalancer IPs (172.17.0.0/24) via BIRD router
if ip route show | grep -q "172.17.0.0/24"; then
  echo "    Route 172.17.0.0/24 via 10.10.10.40 already exists, skipping."
else
  echo "    Adding route 172.17.0.0/24 via 10.10.10.40..."
  sudo ip route add 172.17.0.0/24 via 10.10.10.40
fi

# KUBECONFIG
export KUBECONFIG=~/.kube/config-vagrant-k8s
echo "    KUBECONFIG set to $KUBECONFIG"

echo ""
echo "==> Done. To persist KUBECONFIG in this shell, run:"
echo "    source start_host_config.sh"
echo ""
echo "==> Quick verification:"
echo "    kubectl get nodes"
echo "    curl http://172.17.0.1"
