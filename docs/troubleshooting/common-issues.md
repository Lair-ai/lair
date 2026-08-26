# 🔍 Common Issues & Troubleshooting

> **Comprehensive troubleshooting guide for common Lair deployment and operational issues**

This guide covers the most frequently encountered issues in Lair deployments, from installation problems to runtime issues, with step-by-step solutions and diagnostic procedures.

---

## 🎯 Overview

Troubleshooting Lair involves understanding the multi-layered architecture and identifying where issues occur. This guide is organized by component and symptom to help you quickly identify and resolve problems.

### 🏗️ **Troubleshooting Layers**
```
🌐 Access Layer (DNS, Ingress, Certificates)
     ↓
📦 Application Layer (OpenWebUI, N8N, Ollama, etc.)
     ↓
🔧 Infrastructure Layer (Storage, Network, Backup)
     ↓
🖥️ Cluster Layer (Kubernetes, MicroK8s)
```

### 🚨 **Issue Categories**
- **🔧 Installation Issues**: Problems during setup and deployment
- **🌐 Network Issues**: DNS, ingress, and connectivity problems
- **💾 Storage Issues**: Persistent volume and storage backend problems
- **📦 Application Issues**: Service-specific problems and errors
- **🔐 Certificate Issues**: TLS and HTTPS configuration problems
- **🚀 Performance Issues**: Resource constraints and optimization

---

## 🔧 Installation Issues

### 🚨 **MicroK8s Installation Problems**

#### **Snap Installation Fails**
```bash
# Symptom: snap install microk8s fails
# Error: "cannot install microk8s: snap not found"

# Diagnosis:
systemctl status snapd
snap version

# Solutions:
# 1. Install snapd
sudo apt update
sudo apt install snapd
sudo systemctl enable --now snapd

# 2. Refresh snap store
sudo snap refresh

# 3. Alternative: Use snap from edge channel
sudo snap install microk8s --classic --channel=1.34/stable
```

#### **MicroK8s Won't Start**
```bash
# Symptom: microk8s status shows "not running"
# Error: "microk8s is not running"

# Diagnosis:
sudo microk8s inspect
journalctl -u snap.microk8s.daemon-kubelite -f

# Common causes and solutions:
# 1. Port conflicts
sudo netstat -tulpn | grep :16443
sudo lsof -i :16443

# 2. Insufficient resources
free -h
df -h

# 3. Firewall blocking
sudo ufw status
sudo iptables -L

# 4. Reset and restart
sudo microk8s reset
sudo snap restart microk8s
```

#### **Addon Enable Failures**
```bash
# Symptom: microk8s enable <addon> fails
# Error: "Addon <addon> is already enabled" or timeout

# Diagnosis:
sudo microk8s status --wait-ready
kubectl get pods -A | grep -v Running

# Solutions:
# 1. Wait for cluster readiness
sudo microk8s status --wait-ready --timeout=300

# 2. Check addon status
sudo microk8s disable <addon>
sudo microk8s enable <addon>

# 3. Manual addon restart
sudo systemctl restart snap.microk8s.daemon-kubelite
```

### 🚨 **Helm Chart Deployment Problems**

#### **Resource Detection Fails**
```bash
# Symptom: setup.sh cannot detect system resources
# Error: "Failed to detect CPU/memory/storage"

# Diagnosis:
nproc
free -h
df -h
lscpu

# Solutions:
# 1. Manual resource specification
sudo ./setup.sh --interactive
# Manually enter resources when prompted

# 2. Check system tools
sudo apt install util-linux procps coreutils

# 3. Run with debug mode
sudo bash -x ./setup.sh
```

#### **Helm Installation Fails**
```bash
# Symptom: Helm chart installation fails
# Error: "Error: failed to install chart"

# Diagnosis:
helm version
kubectl cluster-info
kubectl get nodes

# Solutions:
# 1. Check cluster connectivity
kubectl get pods -A

# 2. Verify Helm repositories
helm repo list
helm repo update

# 3. Check resource availability
kubectl describe nodes
kubectl top nodes

# 4. Manual installation with debug
helm install lair . -n lair --create-namespace --debug --dry-run
```

#### **Image Pull Failures**
```bash
# Symptom: Pods stuck in ImagePullBackOff
# Error: "Failed to pull image"

# Diagnosis:
kubectl describe pod <pod-name> -n lair
kubectl get events -n lair --sort-by='.lastTimestamp'

# Solutions:
# 1. Check internet connectivity
kubectl run connectivity-test --image=busybox --rm -it -- ping google.com

# 2. Check DNS resolution
kubectl run dns-test --image=busybox --rm -it -- nslookup google.com

# 3. Check image registry access
docker pull ghcr.io/open-webui/open-webui:main

# 4. Use alternative image registry
# Edit values.yaml to use different registry
```

---

## 🌐 Network Issues

### 🚨 **DNS Resolution Problems**

#### **Cannot Resolve .local Domains**
```bash
# Symptom: ai.hostname.local not accessible
# Error: "Name or service not known"

# Diagnosis:
nslookup ai.hostname.local
dig ai.hostname.local

# Solutions:
# 1. Configure router DNS
# Add to router's DNS server:
192.168.1.100  ai.hostname.local

# 2. Update hosts file
echo "192.168.1.100  ai.hostname.local" | sudo tee -a /etc/hosts

# 3. Check local DNS server
systemctl status systemd-resolved
sudo systemd-resolve --status
```

#### **Public Domain DNS Issues**
```bash
# Symptom: Public domains not resolving
# Error: "NXDOMAIN" or wrong IP

# Diagnosis:
nslookup ai.example.com
dig ai.example.com @8.8.8.8

# Solutions:
# 1. Check DNS records at registrar
# Ensure A records point to correct IP

# 2. Wait for DNS propagation
# Can take up to 48 hours

# 3. Test from multiple locations
dig @1.1.1.1 ai.example.com
dig @8.8.8.8 ai.example.com
```

### 🚨 **Ingress Controller Issues**

#### **Ingress Controller Not Running**
```bash
# Symptom: No external access to services
# Error: "Connection refused" or timeout

# Diagnosis:
kubectl get pods -n ingress-nginx
kubectl get services -n ingress-nginx
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller

# Solutions:
# 1. Restart ingress controller
kubectl rollout restart deployment/ingress-nginx-controller -n ingress-nginx

# 2. Check ingress addon (MicroK8s)
sudo microk8s disable ingress
sudo microk8s enable ingress

# 3. Verify ingress configuration
kubectl get ingress -n lair -o yaml
```

#### **LoadBalancer Stuck in Pending**
```bash
# Symptom: External IP shows <pending>
# Error: LoadBalancer service has no external IP

# Diagnosis:
kubectl get services -n ingress-nginx
kubectl describe service ingress-nginx-controller -n ingress-nginx

# Solutions:
# 1. Check MetalLB configuration (MicroK8s)
kubectl get configmap config -n metallb-system -o yaml

# 2. Restart MetalLB
kubectl rollout restart daemonset/metallb-speaker -n metallb-system

# 3. Use NodePort as fallback
kubectl patch service ingress-nginx-controller -n ingress-nginx -p '{"spec":{"type":"NodePort"}}'
```

### 🚨 **Connectivity Issues**

#### **Services Cannot Communicate**
```bash
# Symptom: Applications cannot reach each other
# Error: "Connection refused" between services

# Diagnosis:
kubectl get services -n lair
kubectl get endpoints -n lair
kubectl exec -n lair deployment/lair-openwebui -- curl lair-ollama

# Solutions:
# 1. Check service names and ports
kubectl describe service lair-ollama -n lair

# 2. Verify network policies
kubectl get networkpolicies -n lair

# 3. Test pod-to-pod connectivity
kubectl exec -n lair deployment/lair-openwebui -- ping lair-ollama
```

---

## 💾 Storage Issues

### 🚨 **Persistent Volume Problems**

#### **PVC Resize Forbidden (Cannot Reduce Storage)**
```bash
# Symptom: Helm upgrade/apply fails when a PVC request size is smaller than the existing PVC size
# Error example:
# Error: UPGRADE FAILED: cannot patch "minio-pvc" with kind PersistentVolumeClaim:
# PersistentVolumeClaim "minio-pvc" is invalid:
# spec.resources.requests.storage: Forbidden: field can not be less than status.capacity
#
# Cause:
# Kubernetes does NOT allow decreasing PVC sizes (only increasing), to prevent data loss.
#
# Fix (recommended):
# 1) Check current PVC size
kubectl get pvc -n lair minio-pvc
kubectl get pvc -n lair minio-pvc -o jsonpath='{.status.capacity.storage}{"\n"}'
#
# 2) Ensure your values file requests >= the current size (e.g., keep 50Gi or increase to 100Gi)
# 3) Re-apply with Helm using your (updated) values file
cd helm-chart
helm upgrade --install lair . -n lair -f values-myconfig.yaml
#
# Notes:
# - If you run the interactive configurator again, DO NOT set smaller storage sizes than what is already deployed.
# - To "shrink" a volume you must create a NEW PVC and migrate data (or delete the PVC = data loss).
```

#### **PVCs Stuck in Pending**
```bash
# Symptom: Persistent Volume Claims not bound
# Error: "ProvisioningFailed" or "Pending"

# Diagnosis:
kubectl get pvc -n lair
kubectl describe pvc <pvc-name> -n lair
kubectl get storageclass

# Solutions:
# 1. Check storage class availability
kubectl get storageclass
kubectl describe storageclass longhorn

# 2. Verify storage provisioner
kubectl get pods -n longhorn-system  # For Longhorn
kubectl get pods -n kube-system | grep hostpath  # For Hostpath

# 3. Check node storage capacity
kubectl describe nodes
df -h  # On cluster nodes
```

#### **Volume Mount Failures**
```bash
# Symptom: Pods stuck in ContainerCreating
# Error: "Unable to attach or mount volumes"

# Diagnosis:
kubectl describe pod <pod-name> -n lair
kubectl get volumeattachments

# Solutions:
# 1. Check storage backend health
kubectl get pods -n longhorn-system
kubectl logs -n longhorn-system -l app=longhorn-manager

# 2. Restart storage components
kubectl rollout restart daemonset/longhorn-manager -n longhorn-system

# 3. Check node storage dependencies
# For Longhorn: ensure iSCSI is running
sudo systemctl status iscsid
sudo systemctl restart iscsid
```

### 🚨 **Longhorn Specific Issues**

#### **Longhorn Volumes Degraded**
```bash
# Symptom: Longhorn UI shows degraded volumes
# Error: "Volume degraded" or "Replica failed"

# Diagnosis:
kubectl get volumes.longhorn.io -n longhorn-system
kubectl describe volume.longhorn.io <volume-name> -n longhorn-system

# Solutions:
# 1. Check node health
kubectl get nodes.longhorn.io -n longhorn-system

# 2. Restart failed replicas
# Use Longhorn UI to detach and reattach volume

# 3. Check disk space on nodes
kubectl exec -n longhorn-system daemonset/longhorn-manager -- df -h
```

#### **Backup Failures**
```bash
# Symptom: Longhorn backups failing
# Error: "Backup failed" in Longhorn UI

# Diagnosis:
kubectl get backups.longhorn.io -n longhorn-system
kubectl logs -n longhorn-system -l app=longhorn-engine

# Solutions:
# 1. Check S3 credentials
kubectl get secret -n longhorn-system <backup-secret>

# 2. Verify S3 connectivity
kubectl run s3-test --image=amazon/aws-cli --rm -it -- aws s3 ls s3://your-bucket

# 3. Check backup target configuration
kubectl get setting.longhorn.io backup-target -n longhorn-system -o yaml
```

---

## 📦 Application Issues

### 🚨 **OpenWebUI Problems**

#### **Cannot Login or Create Account**
```bash
# Symptom: Login fails or signup doesn't work
# Error: "Authentication failed" or "Cannot create user"

# Diagnosis:
kubectl logs -n lair deployment/lair-openwebui
kubectl get secret -n lair openwebui-auth

# Solutions:
# 1. Reset admin password
kubectl exec -n lair deployment/lair-openwebui -- python manage.py reset-admin

# 2. Check database connectivity
kubectl exec -n lair deployment/lair-openwebui -- python manage.py check-db

# 3. Verify authentication configuration
kubectl describe configmap lair-openwebui-config -n lair
```

#### **Models Not Available**
```bash
# Symptom: No models in OpenWebUI dropdown
# Error: "No models available"

# Diagnosis:
kubectl exec -n lair deployment/lair-openwebui -- curl lair-ollama/api/tags
kubectl logs -n lair statefulset/lair-ollama

# Solutions:
# 1. Check Ollama connectivity
kubectl get services -n lair lair-ollama
kubectl exec -n lair deployment/lair-openwebui -- ping lair-ollama

# 2. Pull models in Ollama
kubectl exec -n lair statefulset/lair-ollama -- ollama pull llama3.1:8b

# 3. Restart OpenWebUI
kubectl rollout restart deployment/lair-openwebui -n lair
```

#### **Document Upload Fails**
```bash
# Symptom: Cannot upload documents for RAG
# Error: "Upload failed" or "Processing error"

# Diagnosis:
kubectl logs -n lair deployment/lair-openwebui
kubectl exec -n lair deployment/lair-openwebui -- curl lair-tika:9998

# Solutions:
# 1. Check Tika service
kubectl get pods -n lair -l app=tika
kubectl logs -n lair deployment/lair-tika

# 2. Verify storage space
kubectl exec -n lair deployment/lair-openwebui -- df -h

# 3. Check file size limits
kubectl describe ingress -n lair | grep proxy-body-size
```

### 🚨 **Ollama Problems**

#### **Model Loading Fails**
```bash
# Symptom: Ollama cannot load models
# Error: "Model not found" or "Loading failed"

# Diagnosis:
kubectl exec -n lair statefulset/lair-ollama -- ollama list
kubectl logs -n lair statefulset/lair-ollama
kubectl exec -n lair statefulset/lair-ollama -- df -h

# Solutions:
# 1. Check available storage
kubectl get pvc -n lair lair-ollama-data

# 2. Pull model manually
kubectl exec -n lair statefulset/lair-ollama -- ollama pull llama3.1:8b

# 3. Check GPU availability (if enabled)
kubectl exec -n lair statefulset/lair-ollama -- nvidia-smi
```

#### **GPU Not Detected**
```bash
# Symptom: Ollama not using GPU acceleration
# Error: "No GPU detected" or slow inference

# Diagnosis:
kubectl describe pod -n lair -l app=ollama
nvidia-smi  # On cluster nodes

# Solutions:
# 1. Enable GPU addon (MicroK8s)
sudo microk8s enable gpu

# 2. Check GPU resources in pod
kubectl get pod -n lair -l app=ollama -o yaml | grep -A 5 resources

# 3. Verify NVIDIA runtime
kubectl get nodes -o yaml | grep nvidia
```

### 🚨 **N8N Problems**

#### **Workflows Not Executing**
```bash
# Symptom: N8N workflows stuck or failing
# Error: "Execution failed" or "Workflow timeout"

# Diagnosis:
kubectl logs -n lair deployment/lair-n8n
kubectl logs -n lair deployment/lair-n8n-worker
kubectl get pods -n lair -l app=n8n

# Solutions:
# 1. Check worker connectivity
kubectl exec -n lair deployment/lair-n8n -- redis-cli -h lair-redis ping

# 2. Restart N8N components
kubectl rollout restart deployment/lair-n8n -n lair
kubectl rollout restart deployment/lair-n8n-worker -n lair

# 3. Check database connectivity
kubectl exec -n lair deployment/lair-n8n -- psql -h lair-postgresql -U n8n -c "SELECT 1"
```

#### **Database Connection Issues**
```bash
# Symptom: N8N cannot connect to database
# Error: "Database connection failed"

# Diagnosis:
kubectl logs -n lair statefulset/lair-postgresql
kubectl get services -n lair lair-postgresql

# Solutions:
# 1. Check PostgreSQL status
kubectl exec -n lair statefulset/lair-postgresql -- pg_isready

# 2. Verify credentials
kubectl get secret -n lair lair-postgresql-secret -o yaml

# 3. Test database connection
kubectl exec -n lair statefulset/lair-postgresql -- psql -U n8n -c "SELECT version()"
```

---

## 🔐 Certificate Issues

### 🚨 **Let's Encrypt Problems**

#### **Certificate Request Fails**
```bash
# Symptom: Let's Encrypt certificate not issued
# Error: "Challenge failed" or "Certificate pending"

# Diagnosis:
kubectl get certificates -n lair
kubectl describe certificate lair-tls -n lair
kubectl get challenges -n lair

# Solutions:
# 1. Check DNS propagation
nslookup ai.example.com
dig ai.example.com

# 2. Verify HTTP-01 challenge accessibility
curl -I http://ai.example.com/.well-known/acme-challenge/test

# 3. Check cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager
```

#### **Rate Limit Exceeded**
```bash
# Symptom: Let's Encrypt rate limit hit
# Error: "Rate limit exceeded"

# Diagnosis:
kubectl logs -n cert-manager deployment/cert-manager | grep "rate limit"

# Solutions:
# 1. Use staging environment for testing
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: admin@example.com
    privateKeySecretRef:
      name: letsencrypt-staging
    solvers:
    - http01:
        ingress:
          class: public
EOF

# 2. Wait for rate limit reset (1 week)
# 3. Use DNS-01 challenge if available
```

### 🚨 **mkcert Problems**

#### **Certificate Not Trusted**
```bash
# Symptom: Browser shows "Not Secure" for .local domains
# Error: "Certificate not trusted"

# Diagnosis:
curl -I https://ai.hostname.local
openssl s_client -connect ai.hostname.local:443

# Solutions:
# 1. Install CA certificate on client
mkcert -install  # On certificate generation machine

# 2. Copy CA to client device
cp "$(mkcert -CAROOT)/rootCA.pem" ./
# Transfer and install on client

# 3. Verify certificate installation
curl -I https://ai.hostname.local  # Should not show certificate errors
```

---

## 🚀 Performance Issues

### 🚨 **Resource Constraints**

#### **Out of Memory Errors**
```bash
# Symptom: Pods being killed or restarting
# Error: "OOMKilled" in pod status

# Diagnosis:
kubectl top pods -n lair
kubectl describe pod <pod-name> -n lair
dmesg | grep -i "killed process"

# Solutions:
# 1. Increase memory limits
kubectl patch deployment lair-openwebui -n lair -p '{"spec":{"template":{"spec":{"containers":[{"name":"openwebui","resources":{"limits":{"memory":"4Gi"}}}]}}}}'

# 2. Add more memory to nodes
# 3. Optimize application configuration
# 4. Enable swap (not recommended for production)
```

#### **CPU Throttling**
```bash
# Symptom: Applications running slowly
# Error: High CPU wait times

# Diagnosis:
kubectl top pods -n lair
kubectl top nodes
htop  # On cluster nodes

# Solutions:
# 1. Increase CPU limits
kubectl patch deployment lair-ollama -n lair -p '{"spec":{"template":{"spec":{"containers":[{"name":"ollama","resources":{"limits":{"cpu":"4000m"}}}]}}}}'

# 2. Optimize resource allocation
# Edit values-config.yaml and redeploy

# 3. Add more CPU cores to nodes
```

#### **Storage Performance Issues**
```bash
# Symptom: Slow application response times
# Error: High I/O wait times

# Diagnosis:
kubectl exec -n lair deployment/lair-openwebui -- df -h
iostat -x 1  # On cluster nodes
sudo fio --name=test --ioengine=libaio --rw=randrw --bs=4k --numjobs=1 --size=1G --runtime=60 --direct=1

# Solutions:
# 1. Optimize storage class
# Use faster storage class or increase IOPS

# 2. Tune Longhorn settings
kubectl patch setting.longhorn.io guaranteed-engine-manager-cpu -n longhorn-system -p '{"spec":{"value":"20"}}'

# 3. Use SSD storage for critical components
```

---

## 🔧 Diagnostic Tools & Commands

### 📊 **System Health Checks**

#### **Cluster Health**
```bash
# Overall cluster status
kubectl cluster-info
kubectl get nodes -o wide
kubectl get pods -A | grep -v Running

# Resource usage
kubectl top nodes
kubectl top pods -A

# Events and logs
kubectl get events -A --sort-by='.lastTimestamp' | tail -20
```

#### **Application Health**
```bash
# Lair application status
kubectl get pods -n lair
kubectl get services -n lair
kubectl get ingress -n lair

# Application logs
kubectl logs -n lair deployment/lair-openwebui --tail=50
kubectl logs -n lair statefulset/lair-ollama --tail=50
kubectl logs -n lair deployment/lair-n8n --tail=50
```

#### **Network Diagnostics**
```bash
# Network connectivity
kubectl run network-test --image=busybox --rm -it -- ping google.com
kubectl run dns-test --image=busybox --rm -it -- nslookup kubernetes.default

# Service connectivity
kubectl exec -n lair deployment/lair-openwebui -- curl lair-ollama/api/tags
kubectl exec -n lair deployment/lair-openwebui -- curl lair-tika:9998
```

### 🛠️ **Advanced Debugging**

#### **Pod Debugging**
```bash
# Get detailed pod information
kubectl describe pod <pod-name> -n lair

# Access pod shell
kubectl exec -it <pod-name> -n lair -- /bin/bash

# Check pod filesystem
kubectl exec -n lair <pod-name> -- df -h
kubectl exec -n lair <pod-name> -- ls -la /app

# Copy files from pod
kubectl cp lair/<pod-name>:/path/to/file ./local-file
```

#### **Network Debugging**
```bash
# Check ingress configuration
kubectl get ingress -n lair -o yaml

# Test ingress controller
kubectl exec -n ingress-nginx deployment/ingress-nginx-controller -- nginx -t

# Check MetalLB configuration
kubectl get configmap config -n metallb-system -o yaml
kubectl logs -n metallb-system daemonset/metallb-speaker
```

#### **Storage Debugging**
```bash
# Check storage class and PVs
kubectl get storageclass
kubectl get pv
kubectl describe pv <pv-name>

# Longhorn debugging
kubectl get volumes.longhorn.io -n longhorn-system
kubectl logs -n longhorn-system -l app=longhorn-manager
```

---

## 📋 Emergency Recovery Procedures

### 🚨 **Cluster Recovery**

#### **MicroK8s Complete Reset**
```bash
# WARNING: This will destroy all data
sudo microk8s reset --destructive

# Reinstall MicroK8s
sudo snap remove microk8s
sudo snap install microk8s --classic

# Restore from backup
# Follow backup restoration procedures
```

#### **Application Recovery**
```bash
# Restart all Lair applications
kubectl rollout restart deployment -n lair
kubectl rollout restart statefulset -n lair

# Force pod recreation
kubectl delete pods -n lair --all

# Restore from backup
# Follow application-specific backup procedures
```

### 🔄 **Data Recovery**

#### **Database Recovery**
```bash
# PostgreSQL recovery
kubectl exec -n lair statefulset/lair-postgresql -- pg_dump -U postgres lair > backup.sql
kubectl exec -n lair statefulset/lair-postgresql -- psql -U postgres lair < backup.sql

# Check database integrity
kubectl exec -n lair statefulset/lair-postgresql -- psql -U postgres -c "SELECT version()"
```

#### **Volume Recovery**
```bash
# Longhorn volume recovery
# Use Longhorn UI or CLI to restore from backup

# Hostpath recovery
sudo rsync -av /backup/path/ /var/snap/microk8s/common/default-storage/
```

---

## 📞 Getting Help

### 🔍 **Information to Collect**
When seeking help, collect this information:

```bash
# System information
uname -a
lsb_release -a
kubectl version
helm version

# Cluster status
kubectl cluster-info
kubectl get nodes -o wide
kubectl get pods -A

# Lair specific
kubectl get all -n lair
kubectl logs -n lair deployment/lair-openwebui --tail=100
kubectl describe ingress -n lair

# Resource usage
kubectl top nodes
kubectl top pods -n lair
df -h
free -h
```

### 📚 **Additional Resources**
- **Kubernetes Documentation**: https://kubernetes.io/docs/
- **MicroK8s Documentation**: https://microk8s.io/docs/
- **Longhorn Documentation**: https://longhorn.io/docs/
- **Cert-Manager Documentation**: https://cert-manager.io/docs/
- **NGINX Ingress Documentation**: https://kubernetes.github.io/ingress-nginx/

---

**🎯 Need more specific help?** Check [Platform-Specific Issues](platform-specific.md) or [Debugging Tools](debugging.md)!
