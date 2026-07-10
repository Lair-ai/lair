# 🔐 Certificate Management Guide

> **Complete guide to TLS certificate configuration for secure HTTPS access in Lair**

This guide covers all aspects of TLS certificate management in Lair, from automatic Let's Encrypt certificates for public domains to local mkcert certificates for LAN access.

---

## 🎯 Overview

Lair supports multiple certificate management strategies depending on your access mode and deployment scenario. The system automatically configures the appropriate certificate solution based on your chosen access mode.

### 🔒 **Certificate Strategies**

| Access Mode | Certificate Type | Automation | Use Case |
|-------------|------------------|------------|----------|
| **Public** | Let's Encrypt | Automatic | Internet domains |
| **LAN** | mkcert | Manual | .local domains |
| **Dual** | Both | Mixed | Hybrid environments |

### 🏗️ **Certificate Architecture**
```
┌─────────────────────────────────────────────────────────────────┐
│                    🔐 TLS TERMINATION                           │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐ │
│  │  Let's Encrypt  │  │     mkcert      │  │   Custom CA     │ │
│  │   (Public)      │  │    (LAN)        │  │  (Enterprise)   │ │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                                │
┌─────────────────────────────────────────────────────────────────┐
│                  📋 CERT-MANAGER                                │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐ │
│  │ ClusterIssuer   │  │   Certificate   │  │    Secret       │ │
│  │ (Automation)    │  │  (Requests)     │  │ (TLS Storage)   │ │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                                │
┌─────────────────────────────────────────────────────────────────┐
│                   🌐 NGINX INGRESS                              │
│              TLS Certificate Application                        │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🌍 Let's Encrypt (Public Domains)

### 🎯 **Overview**
Let's Encrypt provides free, automated TLS certificates for public domains. This is the recommended solution for internet-accessible Lair deployments.

### ⚙️ **Automatic Configuration**
When you choose **Public Access** mode, Lair automatically configures Let's Encrypt:

```yaml
# Automatically generated in values-config.yaml
certManager:
  createClusterIssuer: true
  email: admin@example.com
  clusterIssuer: lair-letsencrypt

ingress:
  public:
    enabled: true
    # Certificates automatically requested for all public hosts
```

### 🔧 **Manual ClusterIssuer Setup**
If you need to configure Let's Encrypt manually:

```yaml
# Create ClusterIssuer for Let's Encrypt
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: lair-letsencrypt
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@example.com
    privateKeySecretRef:
      name: lair-letsencrypt-key
    solvers:
    - http01:
        ingress:
          class: public
```

### 📋 **Prerequisites for Let's Encrypt**

#### **DNS Configuration**
```bash
# Required: DNS A records pointing to your cluster
ai.example.com        A    203.0.113.10
n8n.example.com  A    203.0.113.10
images.example.com      A    203.0.113.10
storage.example.com     A    203.0.113.10

# Verify DNS propagation
nslookup ai.example.com
dig ai.example.com
```

#### **Network Requirements**
```bash
# Required: Port 80 accessible from internet (for HTTP-01 challenge)
curl -I http://ai.example.com/.well-known/acme-challenge/test

# Required: Port 443 for HTTPS traffic
curl -I https://ai.example.com
```

#### **Firewall Configuration**
```bash
# Cloud platforms: Usually automatic
# On-premises: Configure router port forwarding
80/tcp   → cluster-ip:80   # HTTP (ACME challenges)
443/tcp  → cluster-ip:443  # HTTPS (main traffic)
```

### 🔍 **Verification & Troubleshooting**

#### **Check Certificate Status**
```bash
# List all certificates
kubectl get certificates -n lair

# Check specific certificate
kubectl describe certificate lair-tls -n lair

# Check certificate details
kubectl get secret lair-tls -n lair -o yaml
```

#### **Monitor Certificate Requests**
```bash
# Check certificate requests
kubectl get certificaterequests -n lair

# Check ACME challenges
kubectl get challenges -n lair

# Check cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager -f
```

#### **Common Let's Encrypt Issues**

##### **Challenge Failed**
```bash
# Issue: HTTP-01 challenge cannot be completed
# Check: DNS points to correct IP
nslookup ai.example.com

# Check: Port 80 accessible
curl -I http://ai.example.com/.well-known/acme-challenge/test

# Check: Ingress controller responding
kubectl get services -n ingress-nginx
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller
```

##### **Rate Limits**
```bash
# Issue: Let's Encrypt rate limits exceeded
# Solution: Use staging environment for testing
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    # ... rest of configuration
```

##### **DNS Propagation**
```bash
# Issue: DNS not propagated globally
# Check: Multiple DNS servers
dig @8.8.8.8 ai.example.com
dig @1.1.1.1 ai.example.com
dig @208.67.222.222 ai.example.com

# Wait: DNS propagation can take up to 48 hours
```

---

## 🏠 mkcert (LAN Domains)

### 🎯 **Overview**
mkcert creates locally-trusted development certificates for `.local` domains. Perfect for LAN access where Let's Encrypt cannot validate domain ownership.

### 🔧 **Automatic Certificate Generation**
Lair includes a script to automatically generate mkcert certificates:

```bash
# Navigate to helm-chart directory
cd helm-chart

# Generate wildcard certificate for .local domain
sudo ./generate-lan-certificates.sh --wildcard hostname.local
```

### 📝 **Manual mkcert Setup**

#### **Install mkcert**
```bash
# Linux (Ubuntu/Debian)
sudo apt update
sudo apt install libnss3-tools
curl -JLO "https://dl.filippo.io/mkcert/v1.4.4?for=linux/amd64"
echo "6d31c65b03972c6dc4a14ab429f2928300518b26503f58723e532d1b0a3bbb52  mkcert-v1.4.4-linux-amd64" | sha256sum -c -
chmod +x mkcert-v1.4.4-linux-amd64
sudo mv mkcert-v1.4.4-linux-amd64 /usr/local/bin/mkcert

# macOS
brew install mkcert
brew install nss # if you use Firefox

# Windows (PowerShell as Administrator)
choco install mkcert
```

#### **Generate Certificates**
```bash
# Install local CA
mkcert -install

# Generate wildcard certificate
mkcert "*.hostname.local" hostname.local

# Files created:
# _wildcard.hostname.local.pem      # Certificate
# _wildcard.hostname.local-key.pem  # Private key
```

#### **Create Kubernetes Secret**
```bash
# Create TLS secret for Kubernetes
kubectl create secret tls lair-tls-local \
  --cert=_wildcard.hostname.local.pem \
  --key=_wildcard.hostname.local-key.pem \
  -n lair
```

### 🔧 **Enable TLS in Configuration**
```yaml
# Update values-config.yaml to enable LAN TLS
ingress:
  lan:
    enabled: true
    enableTLS: true
    tlsSecretName: lair-tls-local
```

### 📱 **Client Certificate Installation**

#### **Automatic Installation (Recommended)**
```bash
# The generate-lan-certificates.sh script provides instructions
# Follow the output for your operating system
```

#### **Manual Installation**

##### **Linux**
```bash
# Copy CA certificate
cp "$(mkcert -CAROOT)/rootCA.pem" /usr/local/share/ca-certificates/mkcert.crt
sudo update-ca-certificates

# Verify installation
curl -I https://ai.hostname.local
```

##### **macOS**
```bash
# Install CA certificate
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain "$(mkcert -CAROOT)/rootCA.pem"

# Verify installation
curl -I https://ai.hostname.local
```

##### **Windows**
```powershell
# Import CA certificate (PowerShell as Administrator)
$cert = "$(mkcert -CAROOT)\rootCA.pem"
Import-Certificate -FilePath $cert -CertStoreLocation Cert:\LocalMachine\Root

# Or use GUI: certmgr.msc → Trusted Root Certification Authorities
```

##### **Mobile Devices**

**iOS:**
```bash
# Email CA certificate to device
# Settings → General → VPN & Device Management → Install Profile
# Settings → General → About → Certificate Trust Settings → Enable
```

**Android:**
```bash
# Copy CA certificate to device
# Settings → Security → Encryption & Credentials → Install from storage
# Select rootCA.pem file
```

### 🔍 **Verification & Troubleshooting**

#### **Test Certificate**
```bash
# Test HTTPS access
curl -I https://ai.hostname.local

# Check certificate details
openssl s_client -connect ai.hostname.local:443 -servername ai.hostname.local

# Browser test: Should show green lock icon
```

#### **Common mkcert Issues**

##### **Certificate Not Trusted**
```bash
# Issue: Browser shows "Not Secure"
# Solution: Ensure CA is installed on client device
mkcert -install  # On certificate generation machine

# Copy CA to client:
cp "$(mkcert -CAROOT)/rootCA.pem" ./
# Transfer and install on client device
```

##### **DNS Resolution**
```bash
# Issue: Cannot resolve .local domains
# Solution: Configure DNS (see Access Modes guide)

# Router DNS (recommended)
192.168.1.100  ai.hostname.local

# Hosts file (/etc/hosts or C:\Windows\System32\drivers\etc\hosts)
192.168.1.100  ai.hostname.local
192.168.1.100  n8n.hostname.local
```

##### **Certificate Expired**
```bash
# Issue: Certificate expired (mkcert certs last 10 years by default)
# Solution: Regenerate certificates
mkcert "*.hostname.local" hostname.local

# Update Kubernetes secret
kubectl delete secret lair-tls-local -n lair
kubectl create secret tls lair-tls-local \
  --cert=_wildcard.hostname.local.pem \
  --key=_wildcard.hostname.local-key.pem \
  -n lair
```

---

## 🔄 Dual Certificate Management

### 🎯 **Overview**
Dual certificate management enables both LAN and Public access with appropriate certificates for each domain type.

### ⚙️ **Configuration**
```yaml
# Dual access configuration
ingress:
  # LAN access with mkcert
  lan:
    enabled: true
    enableTLS: true
    tlsSecretName: lair-tls-local
    hosts:
      - host: ai.hostname.local
        serviceName: openwebui
  
  # Public access with Let's Encrypt
  public:
    enabled: true
    hosts:
      - host: ai.example.com
        serviceName: openwebui

certManager:
  createClusterIssuer: true
  email: admin@example.com
```

### 🔧 **Setup Process**
```bash
# 1. Generate mkcert certificates for LAN
./generate-lan-certificates.sh --wildcard hostname.local

# 2. Configure DNS for both domains
# Local DNS: hostname.local → 192.168.1.100
# Public DNS: example.com → 203.0.113.10

# 3. Apply configuration
helm upgrade --install lair . -n lair -f values-config.yaml

# 4. Verify both access methods
curl -I https://ai.hostname.local      # LAN access
curl -I https://ai.example.com         # Public access
```

---

## 🏢 Enterprise Certificate Management

### 🔒 **Custom Certificate Authority**
For enterprise environments with existing PKI infrastructure:

```yaml
# Use custom CA certificates
apiVersion: v1
kind: Secret
metadata:
  name: custom-ca-tls
  namespace: lair
type: kubernetes.io/tls
data:
  tls.crt: <base64-encoded-certificate>
  tls.key: <base64-encoded-private-key>
```

### 🔧 **External Certificate Management**
```yaml
# Use externally managed certificates
ingress:
  annotations:
    cert-manager.io/cluster-issuer: "enterprise-ca-issuer"
  tls:
    - hosts:
        - ai.internal.company.com
      secretName: enterprise-tls-secret
```

### 🛡️ **Certificate Policies**
```yaml
# Enterprise certificate policies
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: lair-enterprise-cert
spec:
  secretName: lair-enterprise-tls
  issuerRef:
    name: enterprise-ca-issuer
    kind: ClusterIssuer
  dnsNames:
  - ai.internal.company.com
  - n8n.internal.company.com
  duration: 8760h  # 1 year
  renewBefore: 720h  # 30 days
```

---

## 🔧 Advanced Certificate Configuration

### 🎛️ **Certificate Annotations**
```yaml
# Advanced ingress annotations for certificates
ingress:
  annotations:
    # Certificate configuration
    cert-manager.io/cluster-issuer: "lair-letsencrypt"
    cert-manager.io/acme-challenge-type: "http01"
    
    # Security headers
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    nginx.ingress.kubernetes.io/ssl-protocols: "TLSv1.2 TLSv1.3"
    nginx.ingress.kubernetes.io/ssl-ciphers: "ECDHE-RSA-AES128-GCM-SHA256,ECDHE-RSA-AES256-GCM-SHA384"
    
    # HSTS (HTTP Strict Transport Security)
    nginx.ingress.kubernetes.io/server-snippet: |
      add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
```

### 🔄 **Certificate Renewal**
```bash
# Check certificate expiration
kubectl get certificates -n lair -o custom-columns=NAME:.metadata.name,READY:.status.conditions[0].status,EXPIRY:.status.notAfter

# Force certificate renewal
kubectl delete certificate lair-tls -n lair
# Certificate will be automatically recreated

# Check renewal logs
kubectl logs -n cert-manager deployment/cert-manager | grep renewal
```

### 📊 **Certificate Monitoring**
```bash
# Monitor certificate status
kubectl get certificates -n lair -w

# Check certificate events
kubectl get events -n lair --field-selector involvedObject.kind=Certificate

# Certificate expiry monitoring script
#!/bin/bash
kubectl get certificates -n lair -o json | jq -r '.items[] | select(.status.notAfter) | "\(.metadata.name): \(.status.notAfter)"'
```

---

## 🚨 Troubleshooting Guide

### 🔍 **Diagnostic Commands**

#### **Certificate Status**
```bash
# Check all certificates
kubectl get certificates -A

# Detailed certificate information
kubectl describe certificate lair-tls -n lair

# Check certificate secret
kubectl get secret lair-tls -n lair -o yaml

# Decode certificate
kubectl get secret lair-tls -n lair -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -text -noout
```

#### **Cert-Manager Status**
```bash
# Check cert-manager pods
kubectl get pods -n cert-manager

# Check cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager -f

# Check webhook status
kubectl get validatingwebhookconfigurations | grep cert-manager
kubectl get mutatingwebhookconfigurations | grep cert-manager
```

#### **Ingress Configuration**
```bash
# Check ingress configuration
kubectl get ingress -n lair -o yaml

# Check ingress controller logs
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller -f

# Test TLS handshake
openssl s_client -connect ai.example.com:443 -servername ai.example.com
```

### 🛠️ **Common Solutions**

#### **Certificate Stuck in Pending**
```bash
# Check certificate request
kubectl get certificaterequests -n lair

# Check challenge status
kubectl get challenges -n lair

# Check ACME order
kubectl get orders -n lair

# Delete and recreate certificate
kubectl delete certificate lair-tls -n lair
# Will be recreated automatically
```

#### **DNS Challenge Issues**
```bash
# For DNS-01 challenges (if configured)
# Check DNS provider credentials
kubectl get secret dns-provider-secret -n cert-manager

# Check DNS propagation
dig _acme-challenge.ai.example.com TXT
```

#### **Webhook Issues**
```bash
# Check webhook connectivity
kubectl get validatingwebhookconfigurations cert-manager-webhook -o yaml

# Test webhook
kubectl apply --dry-run=server -f - <<EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: test-cert
spec:
  secretName: test-secret
  issuerRef:
    name: lair-letsencrypt
    kind: ClusterIssuer
  dnsNames:
  - test.example.com
EOF
```

---

## 🔄 Certificate Backup & Recovery

### 💾 **Backup Certificates**
```bash
# Backup all certificate secrets
kubectl get secrets -n lair -o yaml | grep -A 10 -B 5 "type: kubernetes.io/tls" > certificates-backup.yaml

# Backup specific certificate
kubectl get secret lair-tls -n lair -o yaml > lair-tls-backup.yaml

# Backup Let's Encrypt account key
kubectl get secret lair-letsencrypt-key -n cert-manager -o yaml > letsencrypt-account-backup.yaml
```

### 🔄 **Restore Certificates**
```bash
# Restore certificate secrets
kubectl apply -f certificates-backup.yaml

# Restore specific certificate
kubectl apply -f lair-tls-backup.yaml

# Verify restoration
kubectl get certificates -n lair
```

### 🚨 **Emergency Certificate Recovery**
```bash
# If certificates are lost, force recreation
kubectl delete certificates --all -n lair
kubectl delete secrets -l cert-manager.io/certificate-name -n lair

# Certificates will be automatically recreated
kubectl get certificates -n lair -w
```

---

## 🎯 Best Practices

### 🔒 **Security Best Practices**
- **Use strong TLS versions**: TLSv1.2 minimum, TLSv1.3 preferred
- **Enable HSTS**: Force HTTPS for all connections
- **Regular certificate monitoring**: Set up expiry alerts
- **Secure private keys**: Protect certificate private keys
- **Certificate rotation**: Regular certificate renewal

### 📊 **Operational Best Practices**
- **Monitor certificate expiry**: Set up alerts 30 days before expiration
- **Test certificate renewal**: Regular testing of renewal process
- **Backup certificates**: Regular backup of certificate secrets
- **Document procedures**: Clear documentation for certificate management
- **Staging environment**: Test certificate changes in staging first

### 🔧 **Configuration Best Practices**
- **Use wildcard certificates**: Reduce certificate management overhead
- **Separate environments**: Different certificates for dev/staging/prod
- **Consistent naming**: Clear naming convention for certificate secrets
- **Resource limits**: Set appropriate resource limits for cert-manager
- **Network policies**: Restrict cert-manager network access

---

**🎯 Ready to secure your deployment?** Continue with [Storage Configuration](../components/storage.md) or explore [Advanced Security](advanced-configuration.md)!
