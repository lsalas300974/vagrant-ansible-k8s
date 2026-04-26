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
┌─────────────────────────────────────────────────────────────────────────────┐
│                        External Network (192.168.0.0/24)                    │
│                                                                             │
│  ┌──────────────────────────────────────┐  ┌────────────────────────────┐   │
│  │   Host Machine (192.168.0.132)        │  │  test-client (192.168.0.50) │  │
│  │   also on 10.10.10.1 (vboxnet0)       │  │  XFCE desktop + Firefox    │  │
│  │                                       │  │                            │  │
│  │   browser ──► http://172.17.0.1       │  │  browser ──► http://172.17 │  │
│  │   route: 172.17.0.0/24               │  │              .0.1          │  │
│  │          via 192.168.0.40             │  │  route: 172.17.0.0/24      │  │
│  └───────────────┬───────────────────────┘  │         via 192.168.0.40   │  │
│                  │                          └─────────────┬──────────────┘  │
│                  └──────────────┬──────────────────────────┘                │
│                                │ static route (next-hop: bird-router eth1) │
└────────────────────────────────┼────────────────────────────────────────────┘
                                 ▼
┌──────────────────────────────────────────────────────────────────┐
│                    BIRD 2 Router (bird-router)                   │
│                    eth1: 192.168.0.40 (external)                 │
│                    eth2: 10.10.10.40 (private)                   │
│                    ip_forward=1 (no NAT)                         │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐     │
│  │ Routing Table (learned via BGP):                        │     │
│  │   172.17.0.1/32 → via 10.10.10.21 (k8s-worker-1)       │     │
│  │   10.0.0.0/24   → via 10.10.10.11 (pod CIDR master-1)  │     │
│  │   10.0.1.0/24   → via 10.10.10.12 (pod CIDR master-2)  │     │
│  │   10.0.2.0/24   → via 10.10.10.13 (pod CIDR master-3)  │     │
│  │   10.0.3.0/24   → via 10.10.10.21 (pod CIDR worker-1)  │     │
│  │   10.0.4.0/24   → via 10.10.10.22 (pod CIDR worker-2)  │     │
│  └─────────────────────────────────────────────────────────┘     │
│                           ▲                                      │
│                           │ iBGP (ASN 65001)                     │
│                           │ 5 sessions                           │
└───────────────────────────┼──────────────────────────────────────┘
                            │ BGP-learned route (next-hop: worker)
         ┌──────────────────┼──────────────────┐
         │          ┌───────┼───────┐          │
         ▼          ▼       ▼       ▼          ▼
┌────────────┐┌────────────┐┌────────────┐┌────────────┐┌────────────┐
│k8s-master-1││k8s-master-2││k8s-master-3││k8s-worker-1││k8s-worker-2│
│10.10.10.11 ││10.10.10.12 ││10.10.10.13 ││10.10.10.21 ││10.10.10.22 │
│            ││            ││            ││            ││            │
│  Cilium    ││  Cilium    ││  Cilium    ││  Cilium    ││  Cilium    │
│  Agent     ││  Agent     ││  Agent     ││  Agent     ││  Agent     │
│  (BGP      ││  (BGP      ││  (BGP      ││  (BGP      ││  (BGP      │
│   speaker) ││   speaker) ││   speaker) ││   speaker) ││   speaker) │
│            ││            ││            ││            ││            │
│  route:    ││  route:    ││  route:    ││  route:    ││  route:    │
│  192.168.  ││  192.168.  ││  192.168.  ││  192.168.  ││  192.168.  │
│  0.0/24 via││  0.0/24 via││  0.0/24 via││  0.0/24 via││  0.0/24 via│
│  10.10.10. ││  10.10.10. ││  10.10.10. ││  10.10.10. ││  10.10.10. │
│  40        ││  40        ││  40        ││  40        ││  40        │
└────────────┘└────────────┘└────────────┘└──────┬─────┘└────────────┘
                                                 │
                                                 ▼
                                  ┌──────────────────────────────┐
                                  │  nginx-service (LoadBalancer) │
                                  │  VIP: 172.17.0.1:80           │
                                  │  Handled by Cilium eBPF       │
                                  │                               │
                                  │  ┌────────┐    ┌────────┐    │
                                  │  │ nginx  │    │ nginx  │    │
                                  │  │10.0.3. │    │10.0.3. │    │
                                  │  │  16    │    │  124   │    │
                                  │  └────────┘    └────────┘    │
                                  │  Pod CIDR: 10.0.3.0/24       │
                                  └──────────────────────────────┘
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
  externalTrafficPolicy: Local
  selector:
    app: nginx
  ports:
    - port: 80
      targetPort: 80
```

Cilium's **CiliumLoadBalancerIPPool** assigns an IP from the pool `172.17.0.1–172.17.0.254`:

```yaml
apiVersion: cilium.io/v2
kind: CiliumLoadBalancerIPPool
metadata:
  name: ip-pool-public
  labels:
    bgp: public
spec:
  blocks:
    - start: "172.17.0.1"
      stop: "172.17.0.254"
  serviceSelector:
    matchExpressions:
      - {key: bgp, operator: In, values: [public]}
```

### 2. BGP Advertisement (Cilium → BIRD)

The Cilium agent on each node runs a BGP speaker. Three resources work together to configure BGP:

The **CiliumBGPClusterConfig** tells every node to peer with the BIRD router and references a peer configuration:

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
      peerConfigRef:
        name: "cilium-peer"       # References the CiliumBGPPeerConfig below
```

The **CiliumBGPPeerConfig** defines the address family and links to the advertisements via label selector:

```yaml
apiVersion: cilium.io/v2
kind: CiliumBGPPeerConfig
metadata:
  name: cilium-peer
spec:
  families:
    - afi: ipv4
      safi: unicast
      advertisements:
        matchLabels:
          advertise: "bgp"        # Selects CiliumBGPAdvertisement with this label
```

The **CiliumBGPAdvertisement** controls what gets advertised. It must have the label that the peer config selects:

```yaml
apiVersion: cilium.io/v2
kind: CiliumBGPAdvertisement
metadata:
  name: bgp-advertisements
  labels:
    advertise: bgp                # ← Matched by CiliumBGPPeerConfig above
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
      attributes:
        communities:
          standard: [ "65001" ]
```

The relationship between these resources:

```
CiliumBGPClusterConfig
  └── peers[].peerConfigRef ──► CiliumBGPPeerConfig
                                  └── families[].advertisements.matchLabels ──► CiliumBGPAdvertisement
```

Each Cilium agent advertises:
- Its **Pod CIDR** (e.g., `10.0.3.0/24` from worker-1)
- Any **LoadBalancer IPs** for services with `bgp: public` label

### 3. Route Learning (BIRD)

BIRD 2 runs on the dedicated router VM and peers with all 5 K8s nodes (3 masters + 2 workers):

```
BIRD config (simplified):

template bgp k8s_node {
  local 10.10.10.40 as 65001;    ← Same ASN (iBGP)
  ipv4 {
    import filter {
      gw = from;                  ← Use neighbor IP as gateway
      accept;
    };
    export none;                  ← BIRD does not advertise anything back
  };
}

protocol bgp k8s_node_1 from k8s_node {
  neighbor 10.10.10.11 as 65001;  ← Peer with master-1
}

protocol bgp k8s_node_2 from k8s_node {
  neighbor 10.10.10.12 as 65001;  ← Peer with master-2
}

protocol bgp k8s_node_3 from k8s_node {
  neighbor 10.10.10.13 as 65001;  ← Peer with master-3
}

protocol bgp k8s_worker_1 from k8s_node {
  neighbor 10.10.10.21 as 65001;  ← Peer with worker-1
}

protocol bgp k8s_worker_2 from k8s_node {
  neighbor 10.10.10.22 as 65001;  ← Peer with worker-2
}
```

When BIRD receives the BGP advertisement for `172.17.0.1/32` from worker-1, it:
1. Learns the route
2. Rewrites the next-hop to `10.10.10.21` (the neighbor's IP, via the `gw = from` filter)
3. Installs it in the Linux kernel routing table (via the `kernel` protocol with `export all`)

Result in the kernel:
```
172.17.0.1 via 10.10.10.21 dev eth2 proto bird metric 32
```

### 4. External Access (Host → BIRD → K8s)

The BIRD router has two interfaces:
- `eth2` (10.10.10.40) — private network, connected to K8s nodes
- `eth1` (192.168.0.40) — external network, reachable from your LAN

From your host, a static route points the LoadBalancer pool to the BIRD router's external interface:

```bash
sudo ip route add 172.17.0.0/24 via 192.168.0.40
```

On the BIRD router, `ip_forward=1` allows it to forward packets that are not destined for itself. There are no NAT/masquerade rules — it acts as a pure IP router.

Each K8s node has a static route back to the external network via the bird-router:

```
192.168.0.0/24 via 10.10.10.40
```

This ensures return traffic goes back through the bird-router instead of being dropped.

Traffic flow:
```
1. Host (192.168.0.132) sends packet to 172.17.0.1
   → static route: 172.17.0.0/24 via 192.168.0.40 dev enp8s0
   → packet sent to bird-router eth1

2. bird-router receives packet on eth1 (192.168.0.40)
   → ip_forward=1, packet is not for itself, so it forwards
   → BGP-learned kernel route: 172.17.0.1 via 10.10.10.21 dev eth2
   → packet forwarded from eth1 to eth2 → k8s-worker-1

3. k8s-worker-1 (10.10.10.21) receives packet
   → Cilium eBPF intercepts dst 172.17.0.1:80
   → DNAT to nginx pod (e.g., 10.0.3.16:80)
   → pod responds
```

### 5. Return Path (symmetric)

The return path goes back through the BIRD router:
```
1. nginx pod responds to 192.168.0.132 (the host)
   → Cilium eBPF rewrites src back to 172.17.0.1

2. k8s-worker-1 routes the reply to 192.168.0.132
   → static route: 192.168.0.0/24 via 10.10.10.40 (bird-router)
   → packet sent to bird-router eth2

3. bird-router receives on eth2, forwards out eth1
   → 192.168.0.132 is on eth1's subnet (192.168.0.0/24)
   → packet delivered to host
```

The path is symmetric:
```
Outbound:  Host → eth1 → bird-router → eth2 → worker-1
Return:    worker-1 → eth2 → bird-router → eth1 → Host
```

No NAT is involved at any point. The BIRD router acts as a pure IP router in both directions, just like a real network router.

## Why iBGP?

All peers use **ASN 65001** — this is iBGP (internal BGP). This is appropriate because all nodes and the router are in the same administrative domain (your lab). iBGP does not modify the AS path, which simplifies the setup.

## Key Configuration Files

| File | Role |
|------|------|
| `cilium-bgp.yml` | All Cilium BGP resources: CiliumBGPClusterConfig, CiliumBGPPeerConfig, CiliumBGPAdvertisement, CiliumLoadBalancerIPPool |
| `ansible/files/bird.conf` | BIRD 2 BGP peering with all 5 K8s nodes |
| `ansible/playbooks/includes/external_route.yml` | Static route on K8s nodes for return traffic to 192.168.0.0/24 |
| `k8s/service.yml` | Example LoadBalancer service with `bgp: public` label |
