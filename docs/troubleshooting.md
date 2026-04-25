# Troubleshooting

## VM boot timeout (systemd-networkd stuck)

Occasionally, a VM may fail to boot with a timeout error due to `systemd-networkd` getting stuck during network configuration. This is a known issue with the bento/ubuntu-24.04 box on VirtualBox 7.0. To recover:

```bash
vagrant halt <vm-name>
vagrant up <vm-name>
```

The VM will boot normally on the second attempt.

## Cilium pods not ready

```bash
cilium status --wait
kubectl -n kube-system get pods -l k8s-app=cilium
```

## BGP sessions not established

```bash
# From a K8s node
cilium bgp peers

# From the BIRD router
vagrant ssh bird-router
sudo birdc show protocols all
```

## Nodes not joining the cluster

Check that the join token hasn't expired (tokens are valid for 24 hours by default):

```bash
# On the primary master
kubeadm token list
# Create a new token if needed
kubeadm token create --print-join-command
```

## DNS not resolving inside pods

Verify CoreDNS is running and the ConfigMap was applied:

```bash
kubectl -n kube-system get pods -l k8s-app=kube-dns
kubectl -n kube-system get configmap coredns -o yaml
```
