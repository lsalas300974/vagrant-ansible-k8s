# How Cilium and BIRD Work Together

This document explains how Cilium BGP Control Plane and BIRD 2 work together in this setup to provide external access to Kubernetes `LoadBalancer` services.

## The Problem

By default, Kubernetes `LoadBalancer` services only work on cloud providers (AWS, GCP, Azure) that have native load balancer integrations. On bare-metal or VM-based clusters, there is no external component to assign and route IPs to services. You need something to:

1. **Assign** an external IP to the service
2. **Advertise** that IP so external clients can reach it
3. **Route** traffic from outside the cluster to the correct node

## The Solution: Cilium + BIRD via BGP

This setup solves all three problems using BGP (Border Gateway Protocol):

```
┌──────────────────────────────────────────────────────────────────┐
│                        External Network                          │
│                       (192.168.0.0/24)                           │
│                                                                  │
│   Your browser ──► 192.168.0.40 (bird-router external IP)       │
└──────────────────────────┬───────────────────────────────────────┘
                           │
                           │ MASQUERADE (NAT)
                           │ 192.168.0.40 → 172.17.0.x
                           ▼
┌──────────────────────────────────────────────────────────────────┐
│                    BIRD 2 Router (bird-router)                   │
│                    10.10.10.40 / 192.168.0.40                    │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐     │
│  │ Routing Table (learned via BGP):                        │     │
│  │   172.17.0.1/32 → via 10.10.10.21 (k8s-worker-1)       │     │
│  │   172.17.0.2/32 → via 10.10.10.22 (k8s-worker-2)       │     │
│  │   10.0.3.0/24   → via 10.10.10.21 (pod CIDR worker-1)  │     │
│  │   10.0.4.0/24   → via 10.10.10.22 (pod CIDR worker-2)  │     │
│  └─────────────────────────────────────────────────────────┘     │
│                           ▲                                      │
│                           │ iBGP (ASN 65001)                     │
│                           │ 5 sessions                           │
└───────────────────────────┼──────────────────────────────────────┘
                            │
              ┌─────────────┼─────────────┐
              │             │             │
              ▼             ▼             ▼
┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│ k8s-master-1 │ │ k8s-worker-1 │ │ k8s-worker-2 │
│ 10.10.10.11  │ │ 10.10.10.21  │ │ 10.10.10.22  │
│              │ │              │ │              │
│  Cilium      │ │  Cilium      │ │  Cilium      │
│  Agent       │ │  Agent       │ │  Agent       │
│  (BGP        │ │  (BGP        │ │  (BGP        │
│   speaker)   │ │   speaker)   │ │   speaker)   │
└──────────────┘ └──────────────┘ └──────────────┘
```

## Step by Step: What Happens When You Create a LoadBalancer Service

### 1. IP Assignment (Cilium)

When you create a service with `type: LoadBalancer` and label `bgp: public`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
  labels:
    bgp: public    # ← This label triggers BGP advertisement
spec:
  type: LoadBalancer
```

Cilium's **CiliumLoadBalancerIPPool** assigns an IP from the pool `172.17.0.1–172.17.0.254`:

```yaml
apiVersion: cilium.io/v2
kind: CiliumLoadBalancerIPPool
metadata:
  name: ip-pool-public
spec:
  blocks:
    - start: "172.17.0.1"
      stop: "172.17.0.254"
  serviceSelector:
    matchExpressions:
      - {key: bgp, operator: In, values: [public]}
```

### 2. BGP Advertisement (Cilium → BIRD)

The Cilium agent on each node runs a BGP speaker. The **CiliumBGPClusterConfig** tells every node to peer with the BIRD router:

```yaml
apiVersion: cilium.io/v2
kind: CiliumBGPClusterConfig
metadata:
  name: cilium-bgp
spec:
  bgpInstances:
  - name: cilium-bgp
    localASN: 65001
    peers:
    - name: "router"
      peerASN: 65001              # Same ASN = iBGP
      peerAddress: "10.10.10.40"  # BIRD router
```

The **CiliumBGPAdvertisement** controls what gets advertised:

```yaml
apiVersion: cilium.io/v2
kind: CiliumBGPAdvertisement
metadata:
  name: bgp-advertisements
spec:
  advertisements:
    - advertisementType: "PodCIDR"       # Pod network routes
    - advertisementType: "Service"        # LoadBalancer IPs
      service:
        addresses:
          - LoadBalancerIP
      selector:
        matchExpressions:
          - { key: bgp, operator: In, values: [ public ] }
```

Each Cilium agent advertises:
- Its **Pod CIDR** (e.g., `10.0.3.0/24` from worker-1)
- Any **LoadBalancer IPs** for services with `bgp: public`

### 3. Route Learning (BIRD)

BIRD 2 runs on the dedicated router VM and peers with all 5 K8s nodes:

```
BIRD config (simplified):

template bgp k8s_node {
  local 10.10.10.40 as 65001;    ← Same ASN (iBGP)
  ipv4 {
    import filter {
      gw = from;                  ← Use neighbor IP as gateway
      accept;
    };
  };
}

protocol bgp k8s_worker_1 from k8s_node {
  neighbor 10.10.10.21 as 65001;  ← Peer with worker-1
}
```

When BIRD receives the BGP advertisement for `172.17.0.1/32` from worker-1, it:
1. Learns the route
2. Rewrites the next-hop to `10.10.10.21` (the neighbor's private IP)
3. Installs it in the Linux kernel routing table

Result in the kernel:
```
172.17.0.1 via 10.10.10.21 dev eth2 proto bird
```

### 4. External Access (Host → BIRD → K8s)

The BIRD router has two interfaces:
- `eth2` (10.10.10.40) — private network, connected to K8s nodes
- `eth1` (192.168.0.40) — external network, reachable from your LAN

IP forwarding is enabled so the router forwards packets between interfaces. From your host, you add a static route pointing the LoadBalancer pool to the BIRD router:

```bash
sudo ip route add 172.17.0.0/24 via 10.10.10.40
```

Traffic flow (pure routing, no NAT):
```
Host → 172.17.0.1 → via 10.10.10.40 (bird-router)
  → kernel route (BGP-learned) → via 10.10.10.21 (worker-1)
    → Cilium eBPF → nginx pod
```

### 5. Return Path

The response follows the reverse path:
```
nginx pod → Cilium eBPF → worker-1
  → 10.10.10.40 (bird-router, on the same subnet)
    → host (10.10.10.1, on the same subnet)
```

No NAT is involved — the BIRD router acts as a pure IP router.

## Why iBGP?

All peers use **ASN 65001** — this is iBGP (internal BGP). This is appropriate because all nodes and the router are in the same administrative domain (your lab). iBGP does not modify the AS path, which simplifies the setup.

## Key Configuration Files

| File | Role |
|------|------|
| `cilium-bgp.yml` | Cilium BGP cluster config, peer config, advertisements, IP pool |
| `ansible/files/bird.conf` | BIRD 2 BGP peering with all K8s nodes |
| `k8s/service.yml` | Example LoadBalancer service with `bgp: public` label |
