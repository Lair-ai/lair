# 🌐 Network Configuration Guide

> **Complete guide to networking components in Lair: CNI, Ingress, Load Balancing, and DNS**

This guide covers all networking aspects of Lair deployments, from Container Network Interface (CNI) configuration to ingress controllers and load balancing strategies.

---

## 🎯 Overview

Lair's networking architecture provides flexible, scalable, and secure connectivity for all components. The networking layer handles internal cluster communication, external access, and platform-specific optimizations.

### 🏗️ **Network Architecture**
```
┌─────────────────────────────────────────────────────────────────┐
│                       🌍 EXTERNAL ACCESS                        │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │   Internet      │  │   LAN Access    │  │  Direct Access  │  │
│  │ (Public IPs)    │  │ (.local domains)│  │ (NodePort/LB)   │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                                │
┌─────────────────────────────────────────────────────────────────┐
│                       🔀 LOAD BALANCING                         │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │    MetalLB      │  │  Cloud LB       │  │   NodePort      │  │
│  │ (On-Premises)   │  │ (EKS/GKE/AKS)   │  │  (Fallback)     │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                                │
┌─────────────────────────────────────────────────────────────────┐
│                       🚪 INGRESS LAYER                          │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │ NGINX Ingress   │  │  TLS Termination│  │   Routing       │  │
│  │  Controller     │  │ (Let's Encrypt) │  │   Rules         │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                                │
┌─────────────────────────────────────────────────────────────────┐
│                        🔗 SERVICE MESH                          │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │   Services      │  │   Endpoints     │  │    DNS          │  │
│  │ (ClusterIP)     │  │  (Pod IPs)      │  │ (CoreDNS)       │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                                │
┌─────────────────────────────────────────────────────────────────┐
│                         🔌 CNI LAYER                            │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │     Calico      │  │    Flannel      │  │   Cloud CNI     │  │
│  │  (Standard)     │  │   (Jetson)      │  │ (EKS/GKE/AKS)   │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### 📊 **Network Configuration by Platform**

| Platform | CNI | Load Balancer | Ingress | DNS | Optimization |
|----------|-----|---------------|---------|-----|--------------|
| **MicroK8s Standard** | Calico | MetalLB | NGINX | CoreDNS | High performance |
| **MicroK8s Jetson** | Flannel | MetalLB | NGINX | CoreDNS | ARM64 + WiFi optimized |
| **AWS EKS** | VPC CNI | ALB/NLB | NGINX | Route53 | Cloud native |
| **Google GKE** | GKE CNI | Cloud LB | NGINX | Cloud DNS | Google optimized |
| **Azure AKS** | Azure CNI | Azure LB | NGINX | Azure DNS | Microsoft optimized |

---

## 🔌 Container Network Interface (CNI)

### 🎯 **CNI Overview**
The CNI provides pod-to-pod networking within the Kubernetes cluster. Lair uses different CNI solutions based on the platform for optimal performance.

### 🖥️ **Calico CNI (Standard Platforms)**

#### **Automatic Configuration**
Calico is the default CNI for standard MicroK8s installations:

```bash
# Calico is enabled by default in MicroK8s
# No additional configuration required for standard deployments
sudo microk8s status | grep calico
```

#### **Calico Features**
- **High Performance**: Optimized for x86_64 architectures
- **Network Policies**: Built-in network security policies
- **BGP Routing**: Advanced routing capabilities
- **IPv4/IPv6**: Dual-stack networking support
- **Scalability**: Handles large cluster deployments

#### **Calico Configuration**
```yaml
# Calico configuration (automatically applied)
apiVersion: projectcalico.org/v3
kind: IPPool
metadata:
  name: default-ipv4-ippool
spec:
  cidr: 10.1.0.0/16
  ipipMode: Always
  natOutgoing: true
```

#### **Calico Troubleshooting**
```bash
# Check Calico pods
kubectl get pods -n calico-system

# Check Calico node status
kubectl get nodes -o wide

# Verify pod networking
kubectl run network-test --image=busybox --rm -it -- ping 10.1.0.1

# Check Calico logs
kubectl logs -n calico-system -l k8s-app=calico-node
```

### 🤖 **Flannel CNI (Jetson Platforms)**

#### **Jetson-Specific Configuration**
Flannel is automatically configured for NVIDIA Jetson devices with ARM64 optimizations:

```bash
# Flannel configuration applied by microk8s/lib/microk8s_flannel.sh
# - Aggressive Calico removal
# - Host-gateway backend for WiFi reliability
# - ARM64-specific optimizations
```

#### **Flannel Features for Jetson**
- **ARM64 Optimized**: Specifically tuned for ARM64 architecture
- **WiFi Friendly**: Host-gateway backend works reliably over WiFi
- **Low Overhead**: Minimal resource consumption for edge devices
- **Simple Configuration**: Reduced complexity for single-node deployments

#### **Flannel Configuration**
```yaml
# Flannel CNI configuration (automatically created)
apiVersion: v1
kind: ConfigMap
metadata:
  name: kube-flannel-cfg
  namespace: kube-system
data:
  cni-conf.json: |
    {
      "name": "cbr0",
      "cniVersion": "0.3.1",
      "plugins": [
        {
          "type": "flannel",
          "delegate": {
            "hairpinMode": true,
            "isDefaultGateway": true
          }
        },
        {
          "type": "portmap",
          "capabilities": {
            "portMappings": true
          }
        }
      ]
    }
  net-conf.json: |
    {
      "Network": "10.1.0.0/16",
      "Backend": {
        "Type": "host-gw"
      }
    }
```

#### **Flannel Troubleshooting**
```bash
# Check Flannel pods
kubectl get pods -n kube-system -l app=flannel

# Check Flannel configuration
kubectl get configmap kube-flannel-cfg -n kube-system -o yaml

# Verify network interface
ip route show | grep flannel

# Check Flannel logs
kubectl logs -n kube-system daemonset/kube-flannel-ds
```

### ☁️ **Cloud CNI Solutions**

#### **AWS VPC CNI**
```bash
# AWS EKS uses VPC CNI by default
# Provides native VPC networking for pods

# Check VPC CNI status
kubectl get pods -n kube-system -l k8s-app=aws-node

# VPC CNI configuration
kubectl get configmap amazon-vpc-cni -n kube-system -o yaml
```

#### **Google GKE CNI**
```bash
# GKE uses Google's container-optimized CNI
# Integrated with Google Cloud networking

# Check GKE CNI status
kubectl get nodes -o wide
kubectl describe node <node-name> | grep PodCIDR
```

#### **Azure CNI**
```bash
# AKS can use Azure CNI or Kubenet
# Azure CNI provides advanced networking features

# Check Azure CNI status
kubectl get pods -n kube-system -l component=azure-cni-networkmonitor
```

---

## 🚪 Ingress Controllers

### 🎯 **NGINX Ingress Controller**
NGINX Ingress is the standard ingress controller for all Lair deployments, providing HTTP/HTTPS routing and TLS termination.

#### **Automatic Installation**
NGINX Ingress is automatically installed during cluster setup:

```bash
# MicroK8s: Enabled via addon
sudo microk8s enable ingress

# Managed K8s: Installed via Helm
helm install ingress-nginx ingress-nginx/ingress-nginx -n ingress-nginx --create-namespace
```

#### **Ingress Controller Configuration**
```yaml
# NGINX Ingress Controller configuration
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-configuration
  namespace: ingress-nginx
data:
  # Performance optimizations
  worker-processes: "auto"
  worker-connections: "1024"
  
  # Security settings
  ssl-protocols: "TLSv1.2 TLSv1.3"
  ssl-ciphers: "ECDHE-RSA-AES128-GCM-SHA256,ECDHE-RSA-AES256-GCM-SHA384"
  
  # Upload limits
  proxy-body-size: "100m"
  client-max-body-size: "100m"
  
  # Timeout settings
  proxy-read-timeout: "600"
  proxy-send-timeout: "600"
```

#### **Ingress Classes**
```yaml
# Public ingress class (default)
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: public
  annotations:
    ingressclass.kubernetes.io/is-default-class: "true"
spec:
  controller: k8s.io/ingress-nginx

# Alternative ingress class for specific use cases
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: internal
spec:
  controller: k8s.io/ingress-nginx
  parameters:
    apiGroup: k8s.io
    kind: ConfigMap
    name: internal-nginx-configuration
```

#### **Ingress Rules Configuration**
```yaml
# Lair ingress configuration (automatically generated)
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: lair-ingress
  namespace: lair
  annotations:
    kubernetes.io/ingress.class: public
    cert-manager.io/cluster-issuer: lair-letsencrypt
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/proxy-body-size: "100m"
spec:
  tls:
  - hosts:
    - ai.example.com
    - n8n.example.com
    secretName: lair-tls
  rules:
  - host: ai.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: lair-openwebui
            port:
              number: 80
  - host: n8n.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: lair-n8n
            port:
              number: 80
```

### 🔧 **Advanced Ingress Configuration**

#### **Custom Annotations**
```yaml
# Advanced ingress annotations for specific requirements
metadata:
  annotations:
    # Rate limiting
    nginx.ingress.kubernetes.io/rate-limit-rps: "10"
    nginx.ingress.kubernetes.io/rate-limit-connections: "5"
    
    # IP whitelisting
    nginx.ingress.kubernetes.io/whitelist-source-range: "192.168.1.0/24,10.0.0.0/8"
    
    # Custom headers
    nginx.ingress.kubernetes.io/configuration-snippet: |
      add_header X-Frame-Options "SAMEORIGIN" always;
      add_header X-Content-Type-Options "nosniff" always;
    
    # WebSocket support
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
    
    # CORS configuration
    nginx.ingress.kubernetes.io/enable-cors: "true"
    nginx.ingress.kubernetes.io/cors-allow-origin: "https://trusted-domain.com"
```

#### **Path-Based Routing**
```yaml
# Multiple services on single domain
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: lair-path-based
  namespace: lair
spec:
  rules:
  - host: lair.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: lair-openwebui
            port:
              number: 80
      - path: /automation
        pathType: Prefix
        backend:
          service:
            name: lair-n8n
            port:
              number: 80
      - path: /images
        pathType: Prefix
        backend:
          service:
            name: lair-comfyui
            port:
              number: 80
```

---

## ⚖️ Load Balancing

### 🎯 **MetalLB (On-Premises)**
MetalLB provides LoadBalancer services for on-premises Kubernetes clusters, automatically configured during MicroK8s setup.

#### **MetalLB Configuration**
```yaml
# MetalLB IP pool configuration (automatically created)
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
  namespace: metallb-system
spec:
  addresses:
  - 192.168.1.100-192.168.1.100  # LAN mode
  # OR
  - 203.0.113.10-203.0.113.10    # Public mode

---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default-advertisement
  namespace: metallb-system
spec:
  ipAddressPools:
  - default-pool
```

#### **MetalLB Modes**

##### **Layer 2 Mode (Default)**
```yaml
# L2 mode configuration
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: l2-advertisement
  namespace: metallb-system
spec:
  ipAddressPools:
  - default-pool
  interfaces:
  - eth0  # Specific interface (optional)
```

##### **BGP Mode (Advanced)**
```yaml
# BGP mode configuration for advanced setups
apiVersion: metallb.io/v1beta2
kind: BGPPeer
metadata:
  name: router-peer
  namespace: metallb-system
spec:
  myASN: 64500
  peerASN: 64501
  peerAddress: 192.168.1.1
```

#### **MetalLB Troubleshooting**
```bash
# Check MetalLB pods
kubectl get pods -n metallb-system

# Check IP pool configuration
kubectl get ipaddresspools -n metallb-system

# Check service external IPs
kubectl get services -A | grep LoadBalancer

# Check MetalLB logs
kubectl logs -n metallb-system -l app=metallb
```

### ☁️ **Cloud Load Balancers**

#### **AWS Application Load Balancer (ALB)**
```yaml
# AWS ALB ingress configuration
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: lair-alb
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:region:account:certificate/cert-id
spec:
  rules:
  - host: ai.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: lair-openwebui
            port:
              number: 80
```

#### **Google Cloud Load Balancer**
```yaml
# GCP load balancer configuration
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: lair-gcp-lb
  annotations:
    kubernetes.io/ingress.class: gce
    kubernetes.io/ingress.global-static-ip-name: lair-global-ip
    ingress.gcp.kubernetes.io/managed-certificates: lair-ssl-cert
spec:
  rules:
  - host: ai.example.com
    http:
      paths:
      - path: /*
        pathType: ImplementationSpecific
        backend:
          service:
            name: lair-openwebui
            port:
              number: 80
```

#### **Azure Application Gateway**
```yaml
# Azure Application Gateway configuration
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: lair-azure-ag
  annotations:
    kubernetes.io/ingress.class: azure/application-gateway
    appgw.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  tls:
  - hosts:
    - ai.example.com
    secretName: lair-tls
  rules:
  - host: ai.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: lair-openwebui
            port:
              number: 80
```

---

## 🔍 DNS Configuration

### 🎯 **CoreDNS (Cluster DNS)**
CoreDNS provides internal DNS resolution for Kubernetes services and pods.

#### **CoreDNS Configuration**
```yaml
# CoreDNS configuration (automatically managed)
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns
  namespace: kube-system
data:
  Corefile: |
    .:53 {
        errors
        health {
            lameduck 5s
        }
        ready
        kubernetes cluster.local in-addr.arpa ip6.arpa {
            pods insecure
            fallthrough in-addr.arpa ip6.arpa
            ttl 30
        }
        prometheus :9153
        forward . /etc/resolv.conf {
            max_concurrent 1000
        }
        cache 30
        loop
        reload
        loadbalance
    }
```

#### **Custom DNS Configuration**
```yaml
# Custom DNS entries for internal services
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns-custom
  namespace: kube-system
data:
  lair.server: |
    lair.local:53 {
        errors
        cache 30
        forward . 192.168.1.1
    }
```

### 🏠 **Local DNS (.local domains)**

#### **Router DNS Configuration**
```bash
# Configure router to resolve .local domains
# Add DNS entries in router admin panel:
192.168.1.100  ai.hostname.local
192.168.1.100  n8n.hostname.local
192.168.1.100  images.hostname.local
192.168.1.100  storage.hostname.local
```

#### **Local DNS Server (dnsmasq)**
```bash
# Install and configure dnsmasq for local DNS
sudo apt install dnsmasq

# Configure dnsmasq
echo "address=/hostname.local/192.168.1.100" | sudo tee -a /etc/dnsmasq.conf

# Restart dnsmasq
sudo systemctl restart dnsmasq
sudo systemctl enable dnsmasq
```

#### **Hosts File Configuration**
```bash
# Client-side hosts file configuration
# Linux/Mac: /etc/hosts
# Windows: C:\Windows\System32\drivers\etc\hosts

192.168.1.100  ai.hostname.local
192.168.1.100  n8n.hostname.local
192.168.1.100  images.hostname.local
192.168.1.100  storage.hostname.local
```

### 🌍 **Public DNS Configuration**

#### **DNS Records for Public Access**
```bash
# Required DNS A records for public domains
ai.example.com        A    203.0.113.10
n8n.example.com  A    203.0.113.10
images.example.com      A    203.0.113.10
storage.example.com     A    203.0.113.10
api.example.com         A    203.0.113.10

# Optional CNAME records
www.example.com         CNAME ai.example.com
lair.example.com        CNAME ai.example.com
```

#### **DNS Propagation Verification**
```bash
# Check DNS propagation from multiple locations
dig ai.example.com @8.8.8.8
dig ai.example.com @1.1.1.1
dig ai.example.com @208.67.222.222

# Check DNS propagation tools
# https://dnschecker.org/
# https://www.whatsmydns.net/
```

---

## 🔧 Network Security

### 🛡️ **Network Policies**

#### **Default Deny Policy**
```yaml
# Default deny all ingress traffic
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: lair
spec:
  podSelector: {}
  policyTypes:
  - Ingress
```

#### **Application-Specific Policies**
```yaml
# Allow OpenWebUI to access Ollama and Tika
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: openwebui-policy
  namespace: lair
spec:
  podSelector:
    matchLabels:
      app: openwebui
  policyTypes:
  - Egress
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: ollama
    ports:
    - protocol: TCP
      port: 11434
  - to:
    - podSelector:
        matchLabels:
          app: tika
    ports:
    - protocol: TCP
      port: 9998
```

#### **Ingress Access Control**
```yaml
# Restrict ingress access by source IP
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: ingress-access-control
  namespace: lair
spec:
  podSelector:
    matchLabels:
      app: openwebui
  policyTypes:
  - Ingress
  ingress:
  - from:
    - ipBlock:
        cidr: 192.168.1.0/24  # Allow only local network
    ports:
    - protocol: TCP
      port: 8080
```

### 🔒 **TLS Configuration**

#### **TLS Termination at Ingress**
```yaml
# TLS configuration in ingress
spec:
  tls:
  - hosts:
    - ai.example.com
    - n8n.example.com
    secretName: lair-tls
  rules:
  - host: ai.example.com
    # ... routing rules
```

#### **End-to-End TLS**
```yaml
# Backend TLS configuration (if services support HTTPS)
metadata:
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
    nginx.ingress.kubernetes.io/proxy-ssl-verify: "off"
```

---

## 📊 Network Monitoring & Troubleshooting

### 🔍 **Network Diagnostics**

#### **Connectivity Testing**
```bash
# Test pod-to-pod connectivity
kubectl run network-test --image=busybox --rm -it -- ping lair-ollama.lair.svc.cluster.local

# Test external connectivity
kubectl run external-test --image=busybox --rm -it -- ping google.com

# Test DNS resolution
kubectl run dns-test --image=busybox --rm -it -- nslookup kubernetes.default

# Test service connectivity
kubectl exec -n lair deployment/lair-openwebui -- curl lair-ollama:11434/api/tags
```

#### **Network Performance Testing**
```bash
# Install network performance tools
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: network-tools
  namespace: lair
spec:
  replicas: 1
  selector:
    matchLabels:
      app: network-tools
  template:
    metadata:
      labels:
        app: network-tools
    spec:
      containers:
      - name: tools
        image: nicolaka/netshoot
        command: ["sleep", "3600"]
EOF

# Test network performance
kubectl exec -n lair deployment/network-tools -- iperf3 -c lair-ollama.lair.svc.cluster.local
```

### 📊 **Network Monitoring**

#### **Service Mesh Observability**
```bash
# Check service endpoints
kubectl get endpoints -n lair

# Monitor service traffic
kubectl top pods -n lair

# Check ingress controller metrics
kubectl get --raw /metrics | grep nginx
```

#### **Network Policy Monitoring**
```bash
# Check network policy status
kubectl get networkpolicies -n lair

# Test network policy enforcement
kubectl exec -n lair deployment/lair-openwebui -- curl lair-postgresql:5432
```

---

## 🚨 Common Network Issues

### 🔧 **Connectivity Problems**

#### **Pod Cannot Reach Service**
```bash
# Diagnosis
kubectl get services -n lair
kubectl get endpoints -n lair
kubectl describe service lair-ollama -n lair

# Solution
# 1. Check service selector matches pod labels
# 2. Verify pod is running and ready
# 3. Check network policies
```

#### **External Access Not Working**
```bash
# Diagnosis
kubectl get ingress -n lair
kubectl describe ingress lair-ingress -n lair
kubectl get services -n ingress-nginx

# Solution
# 1. Check ingress controller is running
# 2. Verify DNS resolution
# 3. Check firewall rules
# 4. Verify TLS certificates
```

#### **DNS Resolution Failures**
```bash
# Diagnosis
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl logs -n kube-system -l k8s-app=kube-dns

# Solution
# 1. Restart CoreDNS pods
# 2. Check /etc/resolv.conf in pods
# 3. Verify upstream DNS servers
```

### 🔧 **Performance Issues**

#### **High Network Latency**
```bash
# Diagnosis
kubectl exec -n lair deployment/lair-openwebui -- ping -c 10 lair-ollama

# Solution
# 1. Check CNI configuration
# 2. Verify network interface settings
# 3. Check for network congestion
# 4. Optimize MTU settings
```

#### **Ingress Controller Overload**
```bash
# Diagnosis
kubectl top pods -n ingress-nginx
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller

# Solution
# 1. Scale ingress controller replicas
# 2. Increase resource limits
# 3. Configure rate limiting
# 4. Use multiple ingress controllers
```

---

## 🎯 Best Practices

### 🔒 **Security Best Practices**
- **Network Policies**: Implement least-privilege network access
- **TLS Everywhere**: Use TLS for all external and internal communications
- **IP Whitelisting**: Restrict access to trusted IP ranges
- **Regular Updates**: Keep network components updated

### 📊 **Performance Best Practices**
- **Resource Allocation**: Properly size network components
- **Load Balancing**: Distribute traffic across multiple replicas
- **Caching**: Use appropriate caching strategies
- **Monitoring**: Implement comprehensive network monitoring

### 🔧 **Operational Best Practices**
- **Documentation**: Document network configuration and changes
- **Testing**: Regular network connectivity and performance testing
- **Backup**: Backup network configurations
- **Automation**: Automate network configuration management

---

**🎯 Ready to optimize your network?** Continue with [Cluster Configuration](cluster.md) or explore [Backup Components](backup.md)!
