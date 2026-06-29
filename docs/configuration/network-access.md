# 🌐 Access Modes Configuration

> **Complete guide to configuring LAN and Public access for Lair applications**

Lair supports flexible access configurations to meet different deployment scenarios, from local development to public cloud deployments. This guide covers all access modes and their configuration.

---

## 🎯 Access Modes Overview

Lair supports two mutually exclusive access configurations:

### 🏠 **LAN Access Mode**
- **Target**: Local network access only
- **Domains**: `.local` domains (e.g., `ai.hostname.local`)
- **Security**: Optional HTTPS with mkcert certificates
- **Use Case**: Development, office networks, secure environments

### 🌍 **Public Access Mode**  
- **Target**: Internet access via public domains
- **Domains**: Public domains (e.g., `ai.example.com`)
- **Security**: Automatic HTTPS with Let's Encrypt
- **Use Case**: Cloud deployments, remote access

> **⚠️ Important**: Dual access mode (LAN + Public simultaneously) is **not supported** due to application limitations. Services like n8n and OpenWebUI require a single URL in their environment variables and cannot handle multiple access points.

---

## 🏠 LAN Access Configuration

### 🎯 **Overview**
LAN access provides secure local network access using `.local` domains. This mode is perfect for development, office environments, and scenarios where internet access is not required.

### 🔧 **Configuration**
```yaml
# Generated in values-config.yaml
ingress:
  lan:
    enabled: true
    enableTLS: false  # Set to true for HTTPS
    tlsSecretName: lair-tls-local
    hosts:
      - host: ai.hostname.local
        serviceName: openwebui
        servicePort: 80
      - host: n8n.hostname.local
        serviceName: n8n
        servicePort: 80
      - host: images.hostname.local
        serviceName: comfyui
        servicePort: 80
      - host: storage.hostname.local
        serviceName: minio
        servicePort: 80
```

### 🌐 **DNS Configuration**

#### **Option 1: Router DNS (Recommended)**
Configure your router's DNS server to resolve `.local` domains:

```bash
# Add to router DNS settings:
192.168.1.100  ai.hostname.local
192.168.1.100  n8n.hostname.local
192.168.1.100  images.hostname.local
192.168.1.100  storage.hostname.local
```

#### **Option 2: Local Hosts File**
Add entries to each client's hosts file:

```bash
# Linux/Mac: /etc/hosts
# Windows: C:\Windows\System32\drivers\etc\hosts
192.168.1.100  ai.hostname.local
192.168.1.100  n8n.hostname.local
192.168.1.100  images.hostname.local
192.168.1.100  storage.hostname.local
```

#### **Option 3: Local DNS Server**
Set up a local DNS server (dnsmasq, Pi-hole, etc.):

```bash
# dnsmasq configuration
address=/hostname.local/192.168.1.100

# Pi-hole local DNS records
ai.hostname.local → 192.168.1.100
n8n.hostname.local → 192.168.1.100
```

### 🔐 **HTTPS Configuration (Optional)**

#### **Generate mkcert Certificates**
```bash
# Navigate to helm-chart directory
cd helm-chart

# Generate wildcard certificate for .local domain
sudo ./generate-lan-certificates.sh --wildcard hostname.local

# The script will:
# 1. Install mkcert if not present
# 2. Generate CA and certificates
# 3. Create Kubernetes secret
# 4. Provide client installation instructions
```

#### **Enable TLS in Configuration**
```yaml
# Update values-config.yaml
ingress:
  lan:
    enabled: true
    enableTLS: true  # Enable HTTPS
    tlsSecretName: lair-tls-local
```

#### **Apply Configuration**
```bash
# Upgrade deployment with TLS enabled
helm upgrade --install lair . -n lair -f values-config.yaml
```

#### **Client Certificate Installation**
Install the CA certificate on client devices:

```bash
# Linux
sudo cp ~/.local/share/mkcert/rootCA.pem /usr/local/share/ca-certificates/mkcert.crt
sudo update-ca-certificates

# macOS  
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ~/.local/share/mkcert/rootCA.pem

# Windows
# Import rootCA.pem into "Trusted Root Certification Authorities"
```

### ✅ **Verification**
```bash
# Test HTTP access
curl -I http://ai.hostname.local

# Test HTTPS access (if enabled)
curl -I https://ai.hostname.local

# Browser access
# Open: https://ai.hostname.local
```

---

## 🌍 Public Access Configuration

### 🎯 **Overview**
Public access enables internet access via public domains with automatic HTTPS certificates from Let's Encrypt. This mode supports both cloud and on-premises deployments.

### 🔧 **Configuration**
```yaml
# Generated in values-config.yaml
ingress:
  public:
    enabled: true
    hosts:
      - host: ai.example.com
        serviceName: openwebui
        servicePort: 80
      - host: n8n.example.com
        serviceName: n8n
        servicePort: 80
      - host: images.example.com
        serviceName: comfyui
        servicePort: 80
      - host: storage.example.com
        serviceName: minio
        servicePort: 80

certManager:
  createClusterIssuer: true
  email: admin@example.com
  clusterIssuer: lair-letsencrypt
```

### 🌐 **DNS Configuration**
Create DNS A records pointing to your cluster's external IP:

```bash
# DNS Records Required:
ai.example.com        A    203.0.113.10
n8n.example.com  A    203.0.113.10
images.example.com      A    203.0.113.10
storage.example.com     A    203.0.113.10
api.example.com         A    203.0.113.10  # Optional: Ollama API
```

### 🔍 **Deployment Scenarios**

#### **☁️ Cloud Public Scenario** (AWS, GCP, Azure)
**Characteristics**: Public IP assigned directly to the instance

```bash
# Network Configuration:
- Public IP: Assigned to VM/instance
- MetalLB Pool: Public IP (e.g., 203.0.113.10-203.0.113.10)
- kube-apiserver: Advertises public IP
- Access: Direct internet access

# Automatic Detection:
# The setup script detects this scenario when:
ip addr show | grep 203.0.113.10  # Public IP found on interface
```

**Optimization**:
- Direct public IP binding
- Standard Let's Encrypt HTTP-01 challenges
- Optimal performance for cloud environments

#### **🏠 On-Premises Public Scenario** (Router/NAT)
**Characteristics**: Public IP on router, private IP on machine

```bash
# Network Configuration:
- Public IP: On router/gateway (203.0.113.10)
- Private IP: On machine (192.168.1.100)
- MetalLB Pool: Public IP (203.0.113.10-203.0.113.10)
- kube-apiserver: Advertises private IP for internal optimization
- Access: Via router port forwarding

# Automatic Detection:
# The setup script detects this scenario when:
ip addr show | grep -v 203.0.113.10  # Public IP NOT found on interface
ping -c 1 203.0.113.10  # But public IP is reachable
```

**Optimization**:
- Dual-IP configuration for NAT environments
- Internal traffic uses private IP for efficiency
- External traffic routed through public IP

### 🔧 **Router Configuration (On-Premises)**

#### **Port Forwarding Rules**
```bash
# Required port forwards (External → Internal):
80/tcp   → 192.168.1.100:80   # HTTP (redirects to HTTPS)
443/tcp  → 192.168.1.100:443  # HTTPS (main access)
6443/tcp → 192.168.1.100:6443 # Kubernetes API (if remote access enabled)
```

#### **Firewall Configuration**
```bash
# Allow incoming connections:
iptables -A INPUT -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j ACCEPT
iptables -A INPUT -p tcp --dport 6443 -j ACCEPT  # Optional
```

### 🔐 **Let's Encrypt Configuration**

#### **Automatic Certificate Management**
```yaml
# Cert-Manager ClusterIssuer (automatically created)
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: lair-letsencrypt
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@example.com
    privateKeySecretRef:
      name: lair-letsencrypt
    solvers:
    - http01:
        ingress:
          class: public
```

#### **Certificate Status**
```bash
# Check certificate status
kubectl get certificates -n lair

# Check certificate details
kubectl describe certificate lair-tls -n lair

# Check Let's Encrypt challenges
kubectl get challenges -n lair
```

### ✅ **Verification**
```bash
# Test external access
curl -I https://ai.example.com

# Check certificate validity
openssl s_client -connect ai.example.com:443 -servername ai.example.com

# Browser access
# Open: https://ai.example.com
```

---

## 🔧 Advanced Configuration

### 🎛️ **Custom Domain Configuration**

#### **Multiple Subdomains**
```yaml
ingress:
  public:
    hosts:
      # Main services
      - host: ai.company.com
        serviceName: openwebui
      - host: workflows.company.com
        serviceName: n8n
      
      # API endpoints
      - host: api.company.com
        serviceName: ollama
        paths:
          - path: /ollama
            pathType: Prefix
      
      # Storage
      - host: files.company.com
        serviceName: minio
```

#### **Path-Based Routing**
```yaml
ingress:
  public:
    hosts:
      - host: lair.company.com
        paths:
          - path: /
            serviceName: openwebui
          - path: /automation
            serviceName: n8n
          - path: /images
            serviceName: comfyui
          - path: /storage
            serviceName: minio
```

### 🔒 **Security Configuration**

#### **IP Whitelisting**
```yaml
ingress:
  annotations:
    nginx.ingress.kubernetes.io/whitelist-source-range: "192.168.1.0/24,10.0.0.0/8"
```

#### **Basic Authentication**
```bash
# Create auth secret
htpasswd -c auth admin
kubectl create secret generic basic-auth --from-file=auth -n lair

# Configure ingress
ingress:
  annotations:
    nginx.ingress.kubernetes.io/auth-type: basic
    nginx.ingress.kubernetes.io/auth-secret: basic-auth
```

#### **Rate Limiting**
```yaml
ingress:
  annotations:
    nginx.ingress.kubernetes.io/rate-limit-rps: "10"
    nginx.ingress.kubernetes.io/rate-limit-connections: "5"
```

### 🌐 **Custom Ingress Configuration**

#### **Custom Annotations**
```yaml
ingress:
  annotations:
    # Increase upload size for large files
    nginx.ingress.kubernetes.io/proxy-body-size: "100m"
    
    # Increase timeout for long-running requests
    nginx.ingress.kubernetes.io/proxy-read-timeout: "600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "600"
    
    # Enable CORS
    nginx.ingress.kubernetes.io/enable-cors: "true"
    nginx.ingress.kubernetes.io/cors-allow-origin: "*"
```

#### **Custom TLS Configuration**
```yaml
ingress:
  tls:
    - hosts:
        - ai.example.com
        - n8n.example.com
      secretName: custom-tls-secret
```

---

## 🚨 Troubleshooting

### 🔍 **Common Issues**

#### **DNS Resolution Problems**
```bash
# Test DNS resolution
nslookup ai.hostname.local
nslookup ai.example.com

# Common solutions:
# 1. Check DNS configuration
# 2. Clear DNS cache: sudo systemctl flush-dns
# 3. Try different DNS server: dig @8.8.8.8 ai.example.com
```

#### **Certificate Issues**
```bash
# Check certificate status
kubectl get certificates -n lair
kubectl describe certificate lair-tls -n lair

# Common solutions:
# 1. Check DNS propagation: dig ai.example.com
# 2. Verify port 80 accessibility for HTTP-01 challenge
# 3. Check Let's Encrypt rate limits
```

#### **Ingress Not Working**
```bash
# Check ingress controller
kubectl get pods -n ingress

# Check ingress configuration
kubectl describe ingress -n lair

# Check MetalLB external IP
kubectl get services -n ingress

# Common solutions:
# 1. Restart ingress controller
# 2. Check MetalLB configuration
# 3. Verify firewall rules
```

### 🔧 **Debugging Commands**

#### **Network Connectivity**
```bash
# Test from inside cluster
kubectl run test-pod --image=busybox --rm -it -- wget -qO- http://lair-openwebui:8080

# Test external connectivity
kubectl run test-pod --image=busybox --rm -it -- wget -qO- https://ai.example.com

# Check ingress logs
kubectl logs -n ingress deployment/ingress-nginx-controller
```

#### **Certificate Debugging**
```bash
# Check certificate details
openssl s_client -connect ai.example.com:443 -servername ai.example.com

# Check cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager

# Manual certificate request
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: test-cert
  namespace: lair
spec:
  secretName: test-tls
  issuerRef:
    name: lair-letsencrypt
    kind: ClusterIssuer
  dnsNames:
  - test.example.com
EOF
```

---

## 🔄 Migration Between Access Modes

> **⚠️ Important**: Choose your access mode carefully during initial setup. Migration between modes requires reconfiguration of all services.

### 🏠 **LAN to Public Migration**
```bash
# 1. Configure public DNS records pointing to your external IP
# 2. Configure router port forwarding (80, 443)
# 3. Update configuration
sudo ./setup.sh --update values-config.yaml
# Choose public access mode

# 4. Apply changes
helm upgrade --install lair . -n lair -f values-config.yaml

# 5. Verify Let's Encrypt certificates
kubectl get certificates -n lair

# 6. Update service URLs in applications
# - n8n: WEBHOOK_URL, N8N_HOST
# - OpenWebUI: WEBUI_URL
```

### 🌍 **Public to LAN Migration**
```bash
# 1. Generate mkcert certificates
./generate-lan-certificates.sh --wildcard hostname.local

# 2. Update configuration
sudo ./setup.sh --update values-config.yaml
# Choose LAN access mode

# 3. Apply changes
helm upgrade --install lair . -n lair -f values-config.yaml

# 4. Configure local DNS (router or hosts file)
# Add entries for all .local domains

# 5. Update service URLs in applications
# - n8n: WEBHOOK_URL, N8N_HOST
# - OpenWebUI: WEBUI_URL
```

### ⚠️ **Why Not Dual Access?**

Dual access mode (LAN + Public simultaneously) is **not supported** due to technical limitations:

**Application Constraints:**
- **n8n**: Requires single `WEBHOOK_URL` and `N8N_HOST` environment variables
- **OpenWebUI**: Requires single `WEBUI_URL` for authentication and callbacks
- **ComfyUI**: Single base URL for API endpoints

**Technical Issues:**
- Services cannot distinguish between LAN and public requests
- OAuth callbacks and webhooks only work with configured URL
- Session management breaks with multiple domain configurations
- CORS policies conflict between access modes

**Recommended Approach:**
Choose one access mode based on your primary use case:
- Use **LAN mode** for development/internal networks with VPN for remote access
- Use **Public mode** for production deployments with proper firewall rules

---

## 🔄 Next Steps

### 📚 **Related Documentation**
- **[Certificate Management](security-certificates.md)** - Detailed TLS certificate configuration
- **[Network Configuration](../components/networking.md)** - Advanced networking setup
- **[Security Configuration](advanced-configuration.md)** - Advanced security features

### 🔧 **Advanced Topics**
- **[Custom Ingress Controllers](../components/networking.md)** - Alternative ingress solutions
- **[Load Balancer Configuration](../components/networking.md)** - MetalLB advanced configuration
- **[Multi-Environment Setup](advanced-configuration.md)** - Multiple environment management

---

**🎯 Ready to secure your deployment?** Continue with [Certificate Management](security-certificates.md) or explore [Advanced Configuration](advanced-configuration.md)!
