# 🤖 Platform-Specific Troubleshooting

> **Comprehensive troubleshooting guide for platform-specific issues in Lair deployments**

This guide covers troubleshooting procedures specific to different deployment platforms: NVIDIA Jetson, cloud providers (AWS, GCP, Azure), and various hardware configurations.

---

## 🎯 Overview

Different platforms present unique challenges and require specific troubleshooting approaches. This guide provides targeted solutions for platform-specific issues that may not apply to general Kubernetes troubleshooting.

### 🏗️ **Platform Categories**
```
┌─────────────────────────────────────────────────────────────────┐
│                    🤖 EDGE PLATFORMS                            │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐ │
│  │ NVIDIA Jetson   │  │ Raspberry Pi    │  │   Other ARM64   │ │
│  │ (Tegra GPU)     │  │   (ARM64)       │  │   (Single Board)│ │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                                │
┌─────────────────────────────────────────────────────────────────┐
│                     ☁️ CLOUD PLATFORMS                          │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │   AWS EKS       │  │   Google GKE    │  │   Azure AKS     │  │
│  │ (EC2 Instances) │  │ (GCE Instances) │  │ (Azure VMs)     │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                                │
┌─────────────────────────────────────────────────────────────────┐
│                  🖥️ STANDARD PLATFORMS                          │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │   x86_64 PC     │  │    Servers      │  │   Workstations  │  │
│  │  (Desktop)      │  │ (Data Center)   │  │   (High-End)    │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🤖 NVIDIA Jetson Platform Issues

### 🎯 **Jetson-Specific Architecture**
NVIDIA Jetson devices require special handling due to ARM64 architecture, Tegra GPU, and memory constraints.

### 🚨 **Common Jetson Issues**

#### **Flannel CNI Problems**

##### **Issue: Pods Stuck in ContainerCreating**
```bash
# Symptoms
kubectl get pods -n lair
# Shows pods stuck in ContainerCreating state

# Diagnosis
kubectl describe pod <pod-name> -n lair
# Look for CNI-related errors

# Check Flannel status
kubectl get pods -n kube-system -l app=flannel
kubectl logs -n kube-system daemonset/kube-flannel-ds

# Common causes:
# 1. Calico conflicts (not properly removed)
# 2. Network interface detection issues
# 3. Kernel module problems
```

**Solution: Flannel Network Reset**
```bash
# Complete Flannel reset procedure
sudo microk8s reset --destructive

# Reinstall with Jetson optimization
sudo ./microk8s/setup.sh

# Or manual Flannel fix:
# 1. Remove existing CNI config
sudo rm -rf /var/snap/microk8s/current/args/cni-network/*

# 2. Restart MicroK8s
sudo snap restart microk8s

# 3. Check kernel modules
sudo modprobe br_netfilter
sudo modprobe overlay
sudo modprobe vxlan

# 4. Verify network interface
ip link show
```

##### **Issue: WiFi Interface Not Detected**
```bash
# Symptoms
# Flannel fails to detect correct network interface on WiFi-only Jetson

# Diagnosis
ip route show default
ip addr show

# Check Flannel configuration
kubectl get configmap kube-flannel-cfg -n kube-system -o yaml
```

**Solution: Manual Interface Configuration**
```bash
# Edit Flannel configuration to specify WiFi interface
kubectl patch configmap kube-flannel-cfg -n kube-system --patch '
{
  "data": {
    "net-conf.json": "{\"Network\": \"10.1.0.0/16\", \"Backend\": {\"Type\": \"host-gw\"}, \"iface\": \"wlan0\"}"
  }
}'

# Restart Flannel pods
kubectl delete pods -n kube-system -l app=flannel

# Verify interface binding
kubectl logs -n kube-system -l app=flannel | grep -i interface
```

#### **GPU and CUDA Issues**

##### **Issue: Tegra GPU Not Detected**
```bash
# Symptoms
kubectl exec -n lair statefulset/lair-ollama -- nvidia-smi
# Command not found or no GPU detected

# Diagnosis
# Check GPU status on host
nvidia-smi
ls -la /dev/nvidia*

# Check CUDA installation
nvcc --version
```

**Solution: GPU Runtime Configuration**
```bash
# Install NVIDIA Container Runtime (if missing)
sudo apt update
sudo apt install nvidia-container-runtime

# Configure Docker for GPU access
sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
    "default-runtime": "nvidia",
    "runtimes": {
        "nvidia": {
            "path": "nvidia-container-runtime",
            "runtimeArgs": []
        }
    }
}
EOF

# Restart Docker and MicroK8s
sudo systemctl restart docker
sudo snap restart microk8s

# Enable GPU addon
sudo microk8s enable gpu

# Verify GPU access in pods
kubectl run gpu-test --image=nvcr.io/nvidia/cuda:11.8-runtime-ubuntu20.04 --rm -it --restart=Never -- nvidia-smi
```

##### **Issue: CUDA Version Mismatch**
```bash
# Symptoms
# Applications fail to use GPU with CUDA version errors

# Diagnosis
# Check host CUDA version
nvcc --version
nvidia-smi

# Check container CUDA version
kubectl exec -n lair statefulset/lair-ollama -- nvcc --version
```

**Solution: CUDA Version Alignment**
```bash
# Use Jetson-specific container images
# Update values-config.yaml:
ollama:
  image:
    repository: dustynv/ollama
    tag: r36.3.0  # Matches JetPack version

comfyUI:
  image:
    repository: dustynv/comfyui
    tag: r36.3.0

# Apply configuration
helm upgrade --install lair . -n lair -f values-config.yaml
```

#### **Memory and Storage Issues**

##### **Issue: Out of Memory on Jetson**
```bash
# Symptoms
# Pods frequently killed with OOMKilled status
kubectl get pods -n lair
kubectl describe pod <pod-name> -n lair | grep -i oom

# Diagnosis
# Check memory usage
free -h
kubectl top nodes
kubectl top pods -n lair
```

**Solution: Memory Optimization for Jetson**
```bash
# Reduce resource allocations for Jetson
# Create Jetson-optimized values:
cat > values-jetson-optimized.yaml << 'EOF'
openWebUI:
  resources:
    limits:
      memory: 1Gi
      cpu: 1000m
    requests:
      memory: 512Mi
      cpu: 500m

ollama:
  resources:
    limits:
      memory: 2Gi
      cpu: 1500m
    requests:
      memory: 1Gi
      cpu: 750m

comfyUI:
  enabled: false  # Disable for memory-constrained Jetson

n8n:
  resources:
    limits:
      memory: 256Mi
      cpu: 250m
    requests:
      memory: 128Mi
      cpu: 125m
  worker:
    replicas: 1
EOF

# Apply optimized configuration
helm upgrade --install lair . -n lair -f values-jetson-optimized.yaml

# Enable swap as emergency measure (not recommended for production)
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

##### **Issue: SD Card Performance Problems**
```bash
# Symptoms
# Slow application performance, high I/O wait times

# Diagnosis
# Check SD card performance
sudo hdparm -t /dev/mmcblk0
iostat -x 1 5

# Check mount options
mount | grep mmcblk0
```

**Solution: SD Card Optimization**
```bash
# Optimize SD card mount options
sudo umount /var/snap/microk8s/common/default-storage
sudo mount -o remount,noatime,commit=60 /var/snap/microk8s/common/default-storage

# Make permanent in /etc/fstab
echo '/dev/mmcblk0p1 /var/snap/microk8s/common/default-storage ext4 defaults,noatime,commit=60 0 2' | sudo tee -a /etc/fstab

# Reduce write amplification
echo 'vm.dirty_ratio = 5' | sudo tee -a /etc/sysctl.conf
echo 'vm.dirty_background_ratio = 2' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# Use high-quality SD card (Class 10, UHS-I or better)
# Consider using external SSD for better performance
```

#### **Power and Thermal Issues**

##### **Issue: Thermal Throttling**
```bash
# Symptoms
# Performance degradation under load, system instability

# Diagnosis
# Check temperature
cat /sys/class/thermal/thermal_zone*/temp
sudo tegrastats

# Check CPU frequency scaling
cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq
```

**Solution: Thermal Management**
```bash
# Monitor thermal zones
watch -n 1 'cat /sys/class/thermal/thermal_zone*/temp'

# Improve cooling
# 1. Ensure adequate ventilation
# 2. Add heatsink/fan if not present
# 3. Reduce ambient temperature

# Adjust power mode (if available)
sudo nvpmodel -m 0  # Maximum performance
sudo nvpmodel -m 1  # Balanced mode
sudo nvpmodel -q    # Query current mode

# Set CPU governor
echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
```

##### **Issue: Power Supply Insufficient**
```bash
# Symptoms
# Random reboots, system instability under load

# Diagnosis
# Check power supply specifications
# Jetson AGX Orin: 60W+ recommended
# Jetson Orin Nano: 25W+ recommended

# Monitor power consumption
sudo tegrastats | grep POM
```

**Solution: Power Supply Upgrade**
```bash
# Use adequate power supply:
# - Jetson AGX Orin: 65W+ USB-C PD or barrel jack
# - Jetson Orin Nano: 30W+ USB-C PD

# Reduce power consumption if needed:
# 1. Lower CPU/GPU frequencies
sudo nvpmodel -m 2  # Power-efficient mode

# 2. Disable unnecessary services
sudo systemctl disable bluetooth
sudo systemctl disable cups

# 3. Optimize application resource usage
# Use lower resource limits in Helm values
```

---

## ☁️ Cloud Platform Issues

### 🔧 **AWS EKS Issues**

#### **Issue: LoadBalancer Service Pending**
```bash
# Symptoms
kubectl get services -n ingress-nginx
# External IP shows <pending>

# Diagnosis
kubectl describe service ingress-nginx-controller -n ingress-nginx
# Check events for LoadBalancer creation errors
```

**Solution: AWS LoadBalancer Configuration**
```bash
# Check AWS LoadBalancer Controller
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# Install AWS LoadBalancer Controller if missing
helm repo add eks https://aws.github.io/eks-charts
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=<cluster-name> \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller

# Check IAM permissions
aws iam get-role --role-name <node-group-role>
# Ensure AmazonEKS_CNI_Policy and AmazonEKSWorkerNodePolicy are attached

# Use ALB instead of Classic LoadBalancer
kubectl annotate service ingress-nginx-controller -n ingress-nginx \
  service.beta.kubernetes.io/aws-load-balancer-type=nlb
```

#### **Issue: EBS Volume Mount Failures**
```bash
# Symptoms
# Pods stuck in ContainerCreating with volume mount errors

# Diagnosis
kubectl describe pod <pod-name> -n lair
# Look for EBS volume attachment errors

# Check EBS CSI driver
kubectl get pods -n kube-system -l app=ebs-csi-controller
```

**Solution: EBS CSI Driver Configuration**
```bash
# Install EBS CSI driver addon
aws eks create-addon --cluster-name <cluster-name> --addon-name aws-ebs-csi-driver

# Or install manually
kubectl apply -k "github.com/kubernetes-sigs/aws-ebs-csi-driver/deploy/kubernetes/overlays/stable/?ref=release-1.19"

# Check IAM service account
kubectl describe serviceaccount ebs-csi-controller-sa -n kube-system

# Ensure proper IAM role for EBS operations
aws iam attach-role-policy \
  --role-name <ebs-csi-role> \
  --policy-arn arn:aws:iam::aws:policy/service-role/Amazon_EBS_CSI_DriverPolicy
```

#### **Issue: VPC CNI Network Problems**
```bash
# Symptoms
# Pod networking issues, IP address exhaustion

# Diagnosis
kubectl get pods -n kube-system -l k8s-app=aws-node
kubectl logs -n kube-system -l k8s-app=aws-node

# Check available IP addresses
aws ec2 describe-subnets --subnet-ids <subnet-id>
```

**Solution: VPC CNI Optimization**
```bash
# Increase IP address pool
kubectl set env daemonset aws-node -n kube-system WARM_IP_TARGET=10

# Enable prefix delegation (for larger clusters)
kubectl set env daemonset aws-node -n kube-system ENABLE_PREFIX_DELEGATION=true

# Check ENI limits for instance type
aws ec2 describe-instance-types --instance-types <instance-type> \
  --query 'InstanceTypes[0].NetworkInfo'

# Consider using secondary CIDR blocks
aws ec2 associate-vpc-cidr-block --vpc-id <vpc-id> --cidr-block 100.64.0.0/16
```

### 🔧 **Google GKE Issues**

#### **Issue: GKE Autopilot Resource Constraints**
```bash
# Symptoms
# Pods rejected due to resource constraints in Autopilot mode

# Diagnosis
kubectl describe pod <pod-name> -n lair
# Look for resource constraint errors
```

**Solution: GKE Autopilot Optimization**
```bash
# Adjust resource requests for Autopilot
# Autopilot requires specific resource increments
cat > values-gke-autopilot.yaml << 'EOF'
openWebUI:
  resources:
    requests:
      memory: 1Gi      # Must be in 256Mi increments
      cpu: 500m       # Must be in 250m increments
    limits:
      memory: 2Gi
      cpu: 1000m

ollama:
  resources:
    requests:
      memory: 2Gi
      cpu: 1000m
    limits:
      memory: 4Gi
      cpu: 2000m
EOF

# Apply Autopilot-optimized configuration
helm upgrade --install lair . -n lair -f values-gke-autopilot.yaml
```

#### **Issue: GKE Ingress vs NGINX Ingress Conflicts**
```bash
# Symptoms
# Multiple ingress controllers causing conflicts

# Diagnosis
kubectl get ingressclass
kubectl get ingress -A
```

**Solution: Ingress Controller Selection**
```bash
# Disable GKE ingress and use NGINX
kubectl annotate ingressclass gce ingressclass.kubernetes.io/is-default-class-

# Set NGINX as default
kubectl annotate ingressclass nginx ingressclass.kubernetes.io/is-default-class=true

# Or use GKE ingress exclusively
# Update ingress configuration to use 'gce' class
kubectl patch ingress lair-ingress -n lair -p '{"spec":{"ingressClassName":"gce"}}'
```

### 🔧 **Azure AKS Issues**

#### **Issue: Azure Disk Attachment Problems**
```bash
# Symptoms
# PVCs stuck in pending state with Azure Disk errors

# Diagnosis
kubectl describe pvc <pvc-name> -n lair
kubectl get events -n lair | grep -i disk
```

**Solution: Azure Disk Configuration**
```bash
# Check Azure Disk CSI driver
kubectl get pods -n kube-system -l app=csi-azuredisk-controller

# Use appropriate storage class
kubectl get storageclass
# Use 'managed-premium' for SSD or 'managed' for standard

# Update PVC to use correct storage class
kubectl patch pvc <pvc-name> -n lair -p '{"spec":{"storageClassName":"managed-premium"}}'

# Check Azure resource quotas
az vm list-usage --location <region> --query "[?name.value=='cores']"
```

#### **Issue: Azure Load Balancer Configuration**
```bash
# Symptoms
# LoadBalancer service not getting external IP

# Diagnosis
kubectl describe service ingress-nginx-controller -n ingress-nginx
az network lb list --resource-group <resource-group>
```

**Solution: Azure LoadBalancer Setup**
```bash
# Use Azure LoadBalancer annotations
kubectl annotate service ingress-nginx-controller -n ingress-nginx \
  service.beta.kubernetes.io/azure-load-balancer-resource-group=<resource-group>

# For static IP
kubectl annotate service ingress-nginx-controller -n ingress-nginx \
  service.beta.kubernetes.io/azure-load-balancer-ipv4=<static-ip>

# Check NSG rules
az network nsg rule list --resource-group <resource-group> --nsg-name <nsg-name>
```

---

## 🖥️ Standard Platform Issues

### 🔧 **x86_64 Desktop/Server Issues**

#### **Issue: GPU Driver Conflicts**
```bash
# Symptoms
# NVIDIA GPU not accessible in containers

# Diagnosis
nvidia-smi
docker run --rm --gpus all nvidia/cuda:11.8-runtime-ubuntu20.04 nvidia-smi
```

**Solution: NVIDIA Container Runtime Setup**
```bash
# Install NVIDIA Container Runtime
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -
curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | sudo tee /etc/apt/sources.list.d/nvidia-docker.list

sudo apt update
sudo apt install nvidia-container-runtime

# Configure Docker
sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
    "default-runtime": "nvidia",
    "runtimes": {
        "nvidia": {
            "path": "nvidia-container-runtime",
            "runtimeArgs": []
        }
    }
}
EOF

sudo systemctl restart docker
sudo snap restart microk8s
```

#### **Issue: Firewall Blocking Cluster Communication**
```bash
# Symptoms
# Pods cannot communicate, ingress not accessible

# Diagnosis
sudo ufw status
sudo iptables -L
```

**Solution: Firewall Configuration**
```bash
# Configure UFW for MicroK8s
sudo ufw allow in on cni0
sudo ufw allow out on cni0
sudo ufw allow in on flannel.1
sudo ufw allow out on flannel.1

# Allow specific ports
sudo ufw allow 16443/tcp  # Kubernetes API
sudo ufw allow 80/tcp     # HTTP
sudo ufw allow 443/tcp    # HTTPS
sudo ufw allow 10250/tcp  # Kubelet API
sudo ufw allow 10255/tcp  # Kubelet read-only
sudo ufw allow 25000/tcp  # Cluster agent
sudo ufw allow 12379/tcp  # etcd
sudo ufw allow 10257/tcp  # kube-controller-manager
sudo ufw allow 10259/tcp  # kube-scheduler

# Or disable UFW (not recommended for production)
sudo ufw disable
```

#### **Issue: DNS Resolution Problems**
```bash
# Symptoms
# Cannot resolve external domains from pods

# Diagnosis
kubectl exec -n lair deployment/lair-openwebui -- nslookup google.com
systemctl status systemd-resolved
```

**Solution: DNS Configuration**
```bash
# Configure systemd-resolved
sudo tee /etc/systemd/resolved.conf > /dev/null <<EOF
[Resolve]
DNS=8.8.8.8 1.1.1.1
FallbackDNS=8.8.4.4 1.0.0.1
Domains=~.
EOF

sudo systemctl restart systemd-resolved

# Or use static DNS
echo 'nameserver 8.8.8.8' | sudo tee /etc/resolv.conf
echo 'nameserver 1.1.1.1' | sudo tee -a /etc/resolv.conf

# Make immutable (prevent overwrite)
sudo chattr +i /etc/resolv.conf
```

---

## 🔧 Hardware-Specific Issues

### 💾 **Storage Hardware Issues**

#### **Issue: NVMe SSD Not Detected**
```bash
# Symptoms
# Storage performance issues, limited storage space

# Diagnosis
lsblk
sudo fdisk -l
sudo nvme list
```

**Solution: NVMe Configuration**
```bash
# Check NVMe status
sudo nvme list
sudo smartctl -a /dev/nvme0n1

# Format and mount NVMe SSD
sudo mkfs.ext4 /dev/nvme0n1
sudo mkdir -p /mnt/nvme
sudo mount /dev/nvme0n1 /mnt/nvme

# Configure for Kubernetes storage
sudo mkdir -p /mnt/nvme/microk8s-storage
sudo chown -R root:microk8s /mnt/nvme/microk8s-storage

# Update storage path
sudo microk8s disable hostpath-storage
sudo microk8s enable hostpath-storage:/mnt/nvme/microk8s-storage
```

#### **Issue: RAID Configuration Problems**
```bash
# Symptoms
# Storage redundancy issues, performance problems

# Diagnosis
cat /proc/mdstat
sudo mdadm --detail /dev/md0
```

**Solution: RAID Optimization**
```bash
# Check RAID status
sudo mdadm --detail --scan

# Optimize RAID for Kubernetes
echo 'echo madvise | sudo tee /sys/kernel/mm/transparent_hugepage/enabled' | sudo tee -a /etc/rc.local
echo 'echo 8192 | sudo tee /sys/block/md0/md/stripe_cache_size' | sudo tee -a /etc/rc.local

# Set appropriate read-ahead
sudo blockdev --setra 4096 /dev/md0
```

### 🌐 **Network Hardware Issues**

#### **Issue: Multiple Network Interfaces**
```bash
# Symptoms
# Incorrect interface selection, network routing issues

# Diagnosis
ip route show
ip addr show
```

**Solution: Interface Selection**
```bash
# Manually specify interface for MetalLB
kubectl patch configmap config -n metallb-system --patch '
{
  "data": {
    "config": "address-pools:\n- name: default\n  protocol: layer2\n  addresses:\n  - 192.168.1.100-192.168.1.100\n  interfaces:\n  - eth0"
  }
}'

# Or for Flannel (Jetson)
kubectl patch configmap kube-flannel-cfg -n kube-system --patch '
{
  "data": {
    "net-conf.json": "{\"Network\": \"10.1.0.0/16\", \"Backend\": {\"Type\": \"host-gw\"}, \"iface\": \"eth0\"}"
  }
}'
```

#### **Issue: WiFi Stability Problems**
```bash
# Symptoms
# Intermittent connectivity, pod networking issues on WiFi

# Diagnosis
iwconfig
ping -c 10 <gateway-ip>
```

**Solution: WiFi Optimization**
```bash
# Disable power management
sudo iwconfig wlan0 power off

# Set static IP (more stable than DHCP)
sudo tee /etc/netplan/01-netcfg.yaml > /dev/null <<EOF
network:
  version: 2
  wifis:
    wlan0:
      dhcp4: no
      addresses: [192.168.1.100/24]
      gateway4: 192.168.1.1
      nameservers:
        addresses: [8.8.8.8, 1.1.1.1]
      access-points:
        "YourWiFiSSID":
          password: "YourPassword"
EOF

sudo netplan apply

# Use host-gw backend for Flannel (better for WiFi)
# This is automatically configured for Jetson platforms
```

---

## 🔍 Platform Detection and Optimization

### 🤖 **Automatic Platform Detection**
```bash
# Platform detection script (used in setup)
detect_platform() {
    # Check for Jetson
    if [ -f /proc/device-tree/model ] && grep -qi jetson /proc/device-tree/model; then
        echo "jetson"
        return
    fi
    
    # Check for cloud platforms
    if curl -s --max-time 2 http://169.254.169.254/latest/meta-data/ >/dev/null 2>&1; then
        echo "aws"
        return
    fi
    
    if curl -s --max-time 2 -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/ >/dev/null 2>&1; then
        echo "gcp"
        return
    fi
    
    if curl -s --max-time 2 -H "Metadata: true" http://169.254.169.254/metadata/instance >/dev/null 2>&1; then
        echo "azure"
        return
    fi
    
    # Default to standard
    echo "standard"
}
```

### ⚙️ **Platform-Specific Optimizations**
```bash
# Apply platform-specific configurations
apply_platform_optimizations() {
    local platform=$1
    
    case $platform in
        "jetson")
            # Jetson optimizations
            echo "Applying Jetson optimizations..."
            # Use Flannel CNI
            # Enable Tegra GPU
            # Optimize for ARM64
            # Use hostpath storage
            ;;
        "aws")
            # AWS optimizations
            echo "Applying AWS optimizations..."
            # Use VPC CNI
            # Configure EBS storage
            # Set up ALB ingress
            ;;
        "gcp")
            # GCP optimizations
            echo "Applying GCP optimizations..."
            # Use GKE CNI
            # Configure Persistent Disk
            # Set up GCE ingress
            ;;
        "azure")
            # Azure optimizations
            echo "Applying Azure optimizations..."
            # Use Azure CNI
            # Configure Azure Disk
            # Set up Azure LB
            ;;
        *)
            # Standard optimizations
            echo "Applying standard optimizations..."
            # Use Calico CNI
            # Use Longhorn storage
            # Configure MetalLB
            ;;
    esac
}
```

---

## 🚨 Emergency Recovery Procedures

### 🔧 **Platform-Specific Recovery**

#### **Jetson Recovery Mode**
```bash
# If Jetson becomes unresponsive
# 1. Force recovery mode
# Hold recovery button and power on

# 2. Flash with SDK Manager
# Use NVIDIA SDK Manager to reflash JetPack

# 3. Restore Lair configuration
# After reflashing, run setup again
sudo ./microk8s/setup.sh
```

#### **Cloud Platform Recovery**
```bash
# AWS: Use Systems Manager Session Manager
aws ssm start-session --target <instance-id>

# GCP: Use serial console
gcloud compute instances get-serial-port-output <instance-name>

# Azure: Use serial console
az serial-console connect --resource-group <rg> --name <vm-name>
```

#### **Standard Platform Recovery**
```bash
# Boot from USB/CD for recovery
# Mount filesystem and restore configuration
sudo mount /dev/sda1 /mnt
sudo chroot /mnt
# Restore Lair configuration from backup
```

---

## 🎯 Best Practices by Platform

### 🤖 **Jetson Best Practices**
- **Use high-quality SD cards** (Class 10, UHS-I or better)
- **Ensure adequate cooling** (heatsink/fan)
- **Use appropriate power supply** (60W+ for AGX Orin)
- **Monitor thermal throttling** regularly
- **Optimize for memory constraints** (reduce resource allocations)

### ☁️ **Cloud Platform Best Practices**
- **Use platform-native services** where possible
- **Configure appropriate IAM roles** and permissions
- **Monitor costs** and resource usage
- **Use availability zones** for high availability
- **Implement proper backup strategies**

### 🖥️ **Standard Platform Best Practices**
- **Use dedicated hardware** for production
- **Implement proper firewall rules**
- **Use UPS** for power protection
- **Monitor hardware health** (temperature, disk health)
- **Plan for hardware redundancy**

---

**🎯 Need more specific help?** Continue with [Debugging Tools](../debugging/README.md) or explore [Component-Specific Issues](../../components/README.md)!
