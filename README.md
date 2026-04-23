# vagrant-ansible-k8s

Provision a **High Availability Multi-Master Kubernetes Cluster** on Ubuntu 24.04 LTS using Vagrant, VirtualBox, and Ansible — with Cilium as the CNI and BGP-based LoadBalancer IP routing via a BIRD 2 router.

## Credits & Attribution

This project is based on the original work by **Ashley Kleynhans**:
[github.com/ashleykleynhans/vagrant-ansible-k8s](https://github.com/ashleykleynhans/vagrant-ansible-k8s)

The original project provisioned a Kubernetes HA cluster on Ubuntu 22.04 with Docker as the container runtime, Flannel as the CNI, and MetalLB for LoadBalancer IP assignment.

### Modernized by

**Luis Salas** — Sr. DevOps Practice Lead | Member of [Cloud Native Costa Rica](https://community.cncf.io/cloud-native-costa-rica/)

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Luis%20Salas-blue?logo=linkedin)](https://www.linkedin.com/in/luis-salas-32ab6259/) [![YouTube](https://img.shields.io/badge/YouTube-Channel-red?logo=youtube)](https://www.youtube.com/channel/UCOvwoiPAZxGE3SqF8p8LSJA)

This fork was updated and modernized for the open source community with significant changes to the OS, container runtime, CNI, BGP routing, Ansible quality, and Kubernetes version.

### What changed in this fork

This fork is a **significant modernization** of the original project. The following modifications were made:

| Area | Original | This Fork |
|------|----------|-----------|
| OS | Ubuntu 22.04 (Jammy) | Ubuntu 24.04 (Noble) |
| Container runtime | Docker CE + containerd | containerd only (Docker removed) |
| containerd config | v2 format (deprecated) | v3 format (containerd 2.x native) |
| Kubernetes version | v1.26 (unpinned) | v1.35.0 (pinned + held) |
| CNI | Flannel | Cilium v1.19.1 with kube-proxy replacement |
| LoadBalancer | MetalLB | Cilium BGP Control Plane + BIRD 2 router |
| BGP router | None | BIRD 2 (bird2 package) |
| Cilium CLI | None | v0.19.2 |
| Hubble observability | None | Enabled |
| Docker apt repo | Jammy (hardcoded) | Noble (correct for 24.04) |
| VirtualBox flags | `--audio` (deprecated) | `--audio-driver` (VBox 7.x) |
| DNS resolution | Manual `/etc/resolv.conf` override | VirtualBox NAT DNS proxy |
| Ansible quality | Shell commands for kubeconfig | Proper Ansible modules, idempotent |
| kubeadm init | Not idempotent, hardcoded IP | Idempotent with stat check, uses variable |
| Cilium prep tasks | Duplicated across 3 playbooks | Extracted to shared include |
| Worker memory | 768MB | 1024MB (prevents OOM with Cilium) |
| Pause image | 3.8 (outdated) | 3.10 (matches K8s 1.35) |

---

## Architecture

```
                    ┌─────────────────────────────────────────────┐
                    │              Host Machine                    │
                    │         (macOS / Linux + VirtualBox)         │
                    └──────────────────┬──────────────────────────┘
                                       │
                    ┌──────────────────┴──────────────────────────┐
                    │          Private Network: 10.10.10.0/24      │
                    └──────────────────┬──────────────────────────┘
                                       │
          ┌────────────────────────────┼────────────────────────────┐
          │                            │                            │
   ┌──────┴──────┐            ┌────────┴────────┐          ┌───────┴───────┐
   │   k8s-lb    │            │  Master Nodes   │          │ Worker Nodes  │
   │ 10.10.10.30 │◄──────────│  .11  .12  .13  │          │   .21   .22   │
   │  HAProxy    │  API 6443  │  Control Plane  │          │  Workloads    │
   └─────────────┘            └────────┬────────┘          └───────┬───────┘
                                       │                           │
                              ┌────────┴───────────────────────────┘
                              │  Cilium CNI (eBPF, kube-proxy replacement)
                              │  BGP peering (ASN 65001)
                              └────────┬───────────────────────────┐
                                       │                           │
                              ┌────────┴────────┐                  │
                              │  bird-router    │    Advertised    │
                              │  10.10.10.40    │◄── LB IPs from ─┘
                              │  BIRD 2 (BGP)   │    172.17.0.0/24
                              │  192.168.0.40   │──► External access
                              └─────────────────┘
```

### How it works

1. **HAProxy** load-balances the Kubernetes API server (port 6443) across the 3 master nodes using TCP round-robin, providing High Availability for the control plane.

2. **kubeadm** initializes the cluster on the primary master (`k8s-master-1`) with the HAProxy endpoint as the control plane address. Secondary masters and workers join using tokens generated during init.

3. **Cilium** is installed as the CNI with full **kube-proxy replacement** via eBPF. This means no iptables rules for service routing — all packet processing happens in the kernel via BPF programs. Cilium also provides:
   - L3/L4/L7 network policies
   - BGP Control Plane for advertising LoadBalancer IPs
   - Hubble for network flow observability

4. **BIRD 2** runs on a dedicated router VM and establishes iBGP sessions (ASN 65001) with all 5 Kubernetes nodes. When a `LoadBalancer` service is created, Cilium assigns an IP from the pool (`172.17.0.0/24`) and advertises it via BGP. BIRD learns the route and installs it in the kernel routing table, making the service reachable from the router's external interface (`192.168.0.40`).

---

## Components & Versions

| Component | Version | Purpose |
|-----------|---------|---------|
| Ubuntu | 24.04 LTS (Noble) | Guest OS for all VMs |
| Kubernetes | v1.35.0 | Container orchestration |
| containerd | 2.x (from Docker repo) | Container runtime (CRI) |
| Cilium | v1.19.1 | CNI, kube-proxy replacement, BGP, network policies |
| Cilium CLI | v0.19.2 | Cilium installation and management |
| Hubble | Enabled via Cilium | Network flow observability |
| HAProxy | Latest from Ubuntu repos | API server load balancer |
| BIRD | 2.x (bird2 package) | BGP router for LB IP routing |
| CoreDNS | Bundled with K8s | Cluster DNS (forwarding to 1.1.1.1, 8.8.8.8) |
| Vagrant | Latest via Homebrew | VM provisioning |
| Ansible | Latest via Homebrew | Configuration management |
| VirtualBox | 7.x | Hypervisor |

---

## VM Specifications

| VM | Hostname | IP Address | CPU | Memory | Role |
|----|----------|------------|:---:|:------:|------|
| k8s-lb | k8s-lb | 10.10.10.30 | 1 | 768MB | HAProxy load balancer |
| k8s-master-1 | k8s-master-1 | 10.10.10.11 | 2 | 2GB | Primary control plane node |
| k8s-master-2 | k8s-master-2 | 10.10.10.12 | 2 | 2GB | Secondary control plane node |
| k8s-master-3 | k8s-master-3 | 10.10.10.13 | 2 | 2GB | Secondary control plane node |
| k8s-worker-1 | k8s-worker-1 | 10.10.10.21 | 1 | 1GB | Worker node |
| k8s-worker-2 | k8s-worker-2 | 10.10.10.22 | 1 | 1GB | Worker node |
| bird-router | bird-router | 10.10.10.40 / 192.168.0.40 | 1 | 512MB | BGP router |
| | | | **10** | **9.25GB** | **Total** |

---

## Network Design

| Network | CIDR | Purpose |
|---------|------|---------|
| Node network | 10.10.10.0/24 | VM-to-VM communication (VirtualBox host-only) |
| Pod network | 10.244.0.0/16 | Kubernetes pod CIDR (managed by Cilium) |
| Service network | 10.96.0.0/12 | Kubernetes ClusterIP services (default) |
| LoadBalancer pool | 172.17.0.0/24 | Cilium-managed external IPs for LoadBalancer services |
| External | 192.168.0.0/24 | BIRD router's public-facing interface |

### BGP Configuration

- **ASN**: 65001 (iBGP — same AS for all peers)
- **Cilium** peers with the BIRD router at 10.10.10.40
- **BIRD** peers with all 5 K8s nodes (masters + workers)
- **Advertised routes**: Pod CIDRs and LoadBalancer service IPs

---

## Requirements

### Hardware

Your host machine needs at least **10 CPU cores** and **9.25 GB of free RAM** for the VMs, plus resources for the host OS itself. Recommended: 16GB+ RAM.

### Software

- macOS or Linux (Ubuntu tested)
- [Homebrew](https://brew.sh/) package manager
- VirtualBox 7.x
- Vagrant
- Ansible

---

## Quick Start

### 1. Clone the repository

```bash
git clone https://github.com/<your-username>/vagrant-ansible-k8s.git
cd vagrant-ansible-k8s
```

### 2. Install dependencies

```bash
./setup.sh
```

This installs VirtualBox, Vagrant, and Ansible via Homebrew, and configures VirtualBox host-only network permissions.

### 3. Start the cluster

```bash
vagrant up
```

This provisions all 7 VMs sequentially. The full process takes approximately 15–25 minutes depending on your hardware and internet speed.

### 4. Post-provisioning setup

After all VMs are up, SSH into the primary master and apply the remaining configurations:

```bash
vagrant ssh k8s-master-1
kubectl replace -f /vagrant/coredns.yaml
kubectl -n kube-system rollout restart deployment coredns
kubectl apply -f /vagrant/cilium-bgp.yml
```

This:
- Configures CoreDNS to forward external queries to 1.1.1.1 and 8.8.8.8
- Deploys the Cilium BGP cluster configuration, peer config, advertisements, and LoadBalancer IP pool

### 5. Verify the cluster

```bash
# Check nodes
kubectl get nodes -o wide

# Check Cilium status
cilium status

# Check BGP peering
cilium bgp peers
```

---

## Deploying a Sample Application

SSH to the primary master:

```bash
vagrant ssh k8s-master-1
```

Deploy an nginx application with 2 replicas:

```bash
kubectl apply -f /vagrant/k8s/deployment.yml
```

Expose it via a LoadBalancer service:

```bash
kubectl apply -f /vagrant/k8s/service.yml
```

Check the assigned external IP:

```bash
kubectl get svc nginx-service
```

The service will receive an IP from the Cilium pool (`172.17.0.0/24`), advertised via BGP to the BIRD router.

---

## Managing the Stack

### Stop all VMs (preserves state)

```bash
vagrant halt
```

### Start VMs after halt

```bash
vagrant up
```

### Destroy all VMs (deletes everything)

```bash
vagrant destroy -f
```

### SSH into a specific VM

```bash
vagrant ssh k8s-master-1
vagrant ssh k8s-worker-1
vagrant ssh bird-router
```

---

## Project Structure

```
.
├── Vagrantfile                          # VM definitions and provisioning config
├── README.md
├── setup.sh                             # Host dependency installer
├── coredns.yaml                         # CoreDNS ConfigMap with external forwarders
├── cilium-bgp.yml                       # Cilium BGP cluster config, peer, advertisements, IP pool
├── k8s/
│   ├── deployment.yml                   # Sample nginx deployment (2 replicas)
│   └── service.yml                      # LoadBalancer service with bgp:public label
└── ansible/
    ├── files/
    │   ├── config.toml                  # containerd v3 config (SystemdCgroup + pause image)
    │   ├── haproxy.cfg                  # HAProxy config for API server load balancing
    │   ├── hosts                        # /etc/hosts for all VMs
    │   └── bird.conf                    # BIRD 2 BGP config (peers with all K8s nodes)
    ├── templates/
    │   ├── join_command.j2              # kubeadm join command template
    │   └── cert_key.j2                  # Certificate key template for control plane join
    └── playbooks/
        ├── k8s_lb.yml                   # HAProxy load balancer setup
        ├── k8s_master_primary.yml       # Primary master: kubeadm init + Cilium install
        ├── k8s_master_secondary.yml     # Secondary masters: join as control plane
        ├── k8s_worker.yml               # Workers: join cluster
        ├── bird_install.yml             # BIRD 2 router setup
        └── includes/
            ├── apt_over_https.yml       # APT HTTPS transport packages
            ├── install_useful_packages.yml  # net-tools
            ├── create_hosts_file.yml    # Deploy /etc/hosts
            ├── install_docker.yml       # containerd.io from Docker repo
            ├── bootstrap_k8s.yml        # K8s repo, kubelet, kubeadm, kubectl
            ├── prepare_cilium.yml       # BPF mount, sysctl, kernel tools
            └── setup_kube_config.yml    # kubeconfig for root and vagrant users
```

---

## Troubleshooting

### Cilium pods not ready

```bash
cilium status --wait
kubectl -n kube-system get pods -l k8s-app=cilium
```

### BGP sessions not established

```bash
# From a K8s node
cilium bgp peers

# From the BIRD router
vagrant ssh bird-router
sudo birdc show protocols all
```

### Nodes not joining the cluster

Check that the join token hasn't expired (tokens are valid for 24 hours by default):

```bash
# On the primary master
kubeadm token list
# Create a new token if needed
kubeadm token create --print-join-command
```

### DNS not resolving inside pods

Verify CoreDNS is running and the ConfigMap was applied:

```bash
kubectl -n kube-system get pods -l k8s-app=kube-dns
kubectl -n kube-system get configmap coredns -o yaml
```

---

## License

The original project by [Ashley Kleynhans](https://github.com/ashleykleynhans) did not include a license. This fork maintains the same status. Please contact the original author regarding licensing terms before using this in production or commercial contexts.
