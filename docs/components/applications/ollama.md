# 🧠 Ollama - Local LLM Serving Platform

> **Complete guide to Ollama configuration, model management, and optimization in Lair**

Ollama is the core LLM serving platform in Lair, providing high-performance local model inference with GPU acceleration support. This guide covers installation, configuration, model management, and optimization.

---

## 🎯 Overview

Ollama serves as the backbone of AI capabilities in Lair, providing a robust API for running large language models locally. It supports both CPU and GPU inference with automatic optimization for different platforms.

### ✨ **Key Features**
- **🚀 High-Performance Inference**: Optimized for local LLM serving
- **🎮 GPU Acceleration**: NVIDIA GPU and Tegra support with automatic detection
- **📦 Model Management**: Easy model installation, switching, and management
- **🔌 OpenAI-Compatible API**: Drop-in replacement for OpenAI API calls
- **⚡ Performance Optimization**: Intelligent memory and compute allocation
- **🤖 Platform Optimization**: Jetson ARM64 and x86_64 support

### 🔗 **Integration Points**
- **OpenWebUI**: Primary consumer for chat and RAG functionality
- **N8N**: Workflow automation with AI model integration
- **ComfyUI**: Potential integration for AI image generation workflows
- **API Access**: Direct API access for custom applications

---

## 🚀 Getting Started

### 🌐 **Accessing Ollama**

#### **Internal API Access (Recommended)**
```bash
# Internal Kubernetes DNS (secure, recommended - runs on service port 80)
http://lair-ollama.lair.svc.cluster.local

# From within cluster (using default port 80)
kubectl exec -n lair deployment/lair-openwebui -- curl lair-ollama/api/tags
```

#### **External API Access (Disabled for Security)**
```bash
# For security reasons, Ollama is strictly restricted to internal cluster access only.
# No public or LAN ingress route is created to prevent unauthorized model execution or DoS.
# If you need to access Ollama externally for development or administration, use port-forwarding:
kubectl port-forward -n lair statefulset/lair-ollama 11434:11434

# Then access on your local machine at:
http://localhost:11434
```

### 🔧 **Basic API Usage**

#### **List Available Models**
```bash
# From within cluster
kubectl exec -n lair statefulset/lair-ollama -- curl http://localhost:11434/api/tags

# Expected response
{
  "models": [
    {
      "name": "llama3.1:8b",
      "modified_at": "2024-01-01T00:00:00Z",
      "size": 4661224676
    }
  ]
}
```

#### **Generate Text**
```bash
# Simple text generation
curl -X POST http://lair-ollama/api/generate \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llama3.1:8b",
    "prompt": "Why is the sky blue?",
    "stream": false
  }'
```

#### **Chat Completion (OpenAI-compatible)**
```bash
# Chat completion format
curl -X POST http://lair-ollama/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llama3.1:8b",
    "messages": [
      {"role": "user", "content": "Hello, how are you?"}
    ]
  }'
```

---

## 🔧 Configuration & Deployment

### ⚙️ **Deployment Configuration**

#### **StatefulSet Configuration**
```yaml
# Ollama runs as a StatefulSet for persistent model storage
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: ollama
  namespace: lair
spec:
  serviceName: "ollama"
  replicas: 1  # Single replica for model consistency
  selector:
    matchLabels:
      app: ollama
```

#### **GPU Configuration**
```yaml
# GPU-enabled configuration
spec:
  template:
    spec:
      runtimeClassName: nvidia  # NVIDIA Container Runtime
      securityContext:
        runAsUser: 0
        fsGroup: 0
        supplementalGroups: [44, 104]  # video and render groups
      containers:
      - name: ollama
        securityContext:
          privileged: true  # Required for GPU access
```

#### **CPU-Only Configuration**
```yaml
# CPU-only configuration (no special runtime)
spec:
  template:
    spec:
      securityContext:
        runAsUser: 0
        fsGroup: 0
      containers:
      - name: ollama
        env:
        - name: OLLAMA_GPU_LAYERS
          value: "0"  # Disable GPU layers
```

### 🖼️ **Container Images**

#### **Standard Platform (x86_64)**
```yaml
ollama:
  image:
    repository: ollama/ollama
    tag: latest
```

#### **Jetson Platform (ARM64)**
```yaml
ollama:
  image:
    repository: ollama/ollama  # Standard image works on Jetson
    tag: latest
    
# Alternative Jetson-optimized images
ollama:
  image:
    repository: dustynv/ollama  # Community Jetson builds
    tag: r36.3.0  # JetPack version specific
```

### 📊 **Resource Configuration**

#### **Memory Allocation**
```yaml
ollama:
  resources:
    requests:
      memory: "2Gi"      # Guaranteed memory
    limits:
      memory: "8Gi"      # Maximum memory (burst)
  
  # Memory calculation based on models
  # Rule of thumb: Model size + 2GB overhead
  # llama3.1:8b ≈ 4.6GB → 8GB limit recommended
  # llama3.1:70b ≈ 40GB → 48GB limit recommended
```

#### **Storage Configuration**
```yaml
ollama:
  persistence:
    size: "50Gi"  # Model storage
    storageClassName: "longhorn"  # or "lair-hostpath" for Jetson
    
# Storage requirements by model type:
# - Small models (1-7B): 5-10GB
# - Medium models (8-13B): 10-20GB  
# - Large models (30-70B): 30-80GB
# - Multiple models: Add sizes + 20% overhead
```

### 🎮 **GPU Configuration**

#### **NVIDIA GPU Settings**
```yaml
ollama:
  gpuEnabled: true
  
  # Environment variables for GPU
  env:
    NVIDIA_VISIBLE_DEVICES: "all"
    NVIDIA_DRIVER_CAPABILITIES: "compute,utility"
    LD_LIBRARY_PATH: "/usr/local/cuda/lib64:${LD_LIBRARY_PATH}"
```

#### **Jetson Tegra GPU Settings**
```yaml
ollama:
  gpuEnabled: true
  
  # Jetson-specific GPU device mounts
  volumes:
    - name: nvhost-gpu
      hostPath:
        path: /dev/nvhost-gpu
    - name: nvhost-ctrl
      hostPath:
        path: /dev/nvhost-ctrl-gpu
  
  # Environment for Jetson
  env:
    LD_LIBRARY_PATH: "/usr/lib/aarch64-linux-gnu/nvidia:/usr/local/cuda/lib:/usr/local/cuda/lib64"
```

---

## 📦 Model Management

### 🔍 **Available Models**

#### **Popular Models by Size**
```bash
# Small Models (1-7B parameters)
gemma2:2b          # 1.6GB - Very fast, basic tasks
phi3:mini          # 2.3GB - Microsoft, good performance
llama3.2:3b        # 2.0GB - Meta, latest small model

# Medium Models (8-13B parameters)  
llama3.1:8b        # 4.7GB - Balanced performance/speed
mistral:7b         # 4.1GB - Good general purpose
codellama:7b       # 3.8GB - Code generation

# Large Models (30-70B parameters)
llama3.1:70b       # 40GB - High quality, slow
mixtral:8x7b       # 26GB - Mixture of experts
codellama:34b      # 19GB - Advanced code generation
```

#### **Specialized Models**
```bash
# Multimodal (Vision + Text)
llava:7b           # 4.5GB - Image understanding
llava:13b          # 7.3GB - Better image analysis

# Code Generation
deepseek-coder:6.7b # 3.8GB - Code-focused
starcoder:7b       # 4.1GB - Code completion

# Instruction Following
vicuna:7b          # 3.8GB - Chat optimized
orca-mini:7b       # 3.8GB - Instruction following
```

### 📥 **Model Installation**

#### **Install Models via API**
```bash
# Install a model
curl -X POST http://lair-ollama/api/pull \
  -H "Content-Type: application/json" \
  -d '{"name": "llama3.1:8b"}'

# Check installation progress
curl http://lair-ollama/api/ps
```

#### **Install Models via CLI**
```bash
# Access Ollama container
kubectl exec -it -n lair statefulset/lair-ollama -- /bin/bash

# Pull models
ollama pull llama3.1:8b
ollama pull mistral:7b
ollama pull codellama:7b

# List installed models
ollama list

# Remove models
ollama rm old-model:tag
```

#### **Batch Model Installation**
```bash
# Create model installation script
cat > install-models.sh << 'EOF'
#!/bin/bash
MODELS=(
  "llama3.1:8b"
  "mistral:7b"
  "codellama:7b"
  "gemma2:2b"
)

for model in "${MODELS[@]}"; do
  echo "Installing $model..."
  kubectl exec -n lair statefulset/lair-ollama -- ollama pull "$model"
done
EOF

chmod +x install-models.sh
./install-models.sh
```

### 🔄 **Model Management Operations**

#### **Model Information**
```bash
# Get model details
kubectl exec -n lair statefulset/lair-ollama -- ollama show llama3.1:8b

# Model file locations (inside container)
kubectl exec -n lair statefulset/lair-ollama -- ls -la /root/.ollama/models/
```

#### **Model Performance Testing**
```bash
# Test model performance
kubectl exec -n lair statefulset/lair-ollama -- ollama run llama3.1:8b "What is artificial intelligence?"

# Benchmark model speed
time kubectl exec -n lair statefulset/lair-ollama -- ollama run llama3.1:8b "Write a short story about AI"
```

#### **Model Storage Management**
```bash
# Check storage usage
kubectl exec -n lair statefulset/lair-ollama -- df -h /root/.ollama

# Clean up unused models
kubectl exec -n lair statefulset/lair-ollama -- ollama list
kubectl exec -n lair statefulset/lair-ollama -- ollama rm unused-model:tag
```

---

## ⚡ Performance Optimization

### 🚀 **Performance Configuration**

#### **Ollama Performance Settings**
```yaml
ollama:
  performances:
    numParallel: 4           # Concurrent requests
    maxQueue: 512            # Request queue size  
    keepAlive: 300           # Model keep-alive (seconds)
    kvCacheType: "q8_0"   # Memory-efficient caching
    maxLoadedModels: 3       # Max models in memory
```

#### **Environment Variables**
```yaml
env:
  # Performance tuning
  OLLAMA_NUM_PARALLEL: "4"
  OLLAMA_MAX_QUEUE: "512"
  OLLAMA_KEEP_ALIVE: "300"
  OLLAMA_KV_CACHE_TYPE: "q8_0"
  OLLAMA_MAX_LOADED_MODELS: "3"
  
  # Memory optimization
  OLLAMA_FLASH_ATTENTION: "1"
  OLLAMA_MMAP: "1"
  
  # Debug settings
  OLLAMA_DEBUG: "0"
  OLLAMA_LOGS: "/dev/stdout"
```

### 🎮 **GPU Optimization**

#### **GPU Memory Management**
```bash
# Monitor GPU usage
kubectl exec -n lair statefulset/lair-ollama -- nvidia-smi

# Check GPU memory allocation
kubectl exec -n lair statefulset/lair-ollama -- nvidia-smi --query-gpu=memory.used,memory.total --format=csv
```

#### **GPU Performance Tuning**
```yaml
# GPU-specific optimizations
env:
  # CUDA optimizations
  CUDA_VISIBLE_DEVICES: "0"
  NVIDIA_VISIBLE_DEVICES: "all"
  
  # Memory management
  PYTORCH_CUDA_ALLOC_CONF: "max_split_size_mb:512"
  
  # Jetson-specific
  TEGRA_OPTIMIZATION: "1"  # If supported by image
```

### 💾 **Memory Optimization**

#### **Memory-Constrained Environments**
```yaml
# Jetson or low-memory optimization
ollama:
  performances:
    maxLoadedModels: 1       # Single model only
    kvCacheType: "kv-4bit"   # More aggressive compression
    numParallel: 2           # Reduce concurrent requests
    
  # Use smaller models
  recommendedModels:
    - "gemma2:2b"
    - "phi3:mini"
    - "llama3.2:3b"
```

#### **Memory Monitoring**
```bash
# Monitor memory usage
kubectl exec -n lair statefulset/lair-ollama -- free -h
kubectl exec -n lair statefulset/lair-ollama -- ps aux | grep ollama

# Check model memory usage
kubectl exec -n lair statefulset/lair-ollama -- ollama ps
```

---

## 🔍 Monitoring & Health Checks

### 📊 **Health Monitoring**

#### **API Health Checks**
```bash
# Basic health check
kubectl exec -n lair statefulset/lair-ollama -- curl -f http://localhost:11434/api/tags

# Detailed status
kubectl exec -n lair statefulset/lair-ollama -- curl http://localhost:11434/api/ps

# Model-specific health
kubectl exec -n lair statefulset/lair-ollama -- curl -X POST http://localhost:11434/api/generate \
  -d '{"model": "llama3.1:8b", "prompt": "test", "stream": false}'
```

#### **Resource Monitoring**
```bash
# Pod resource usage
kubectl top pod -n lair -l app=ollama

# Detailed resource analysis
kubectl describe pod -n lair -l app=ollama | grep -A 10 "Requests\|Limits"

# Storage usage
kubectl exec -n lair statefulset/lair-ollama -- df -h /root/.ollama
```

### 📝 **Logging & Debugging**

#### **Log Analysis**
```bash
# View Ollama logs
kubectl logs -n lair statefulset/lair-ollama -f

# Filter for errors
kubectl logs -n lair statefulset/lair-ollama | grep -i "error\|fail\|exception"

# Performance logs
kubectl logs -n lair statefulset/lair-ollama | grep -i "load\|inference\|model"
```

#### **Performance Metrics**
```bash
# Create performance monitoring script
cat > ollama-performance.sh << 'EOF'
#!/bin/bash
echo "=== Ollama Performance Report ==="
echo "Timestamp: $(date)"

# API response time
echo "=== API Response Time ==="
time kubectl exec -n lair statefulset/lair-ollama -- curl -s http://localhost:11434/api/tags >/dev/null

# Model status
echo "=== Running Models ==="
kubectl exec -n lair statefulset/lair-ollama -- curl -s http://localhost:11434/api/ps

# Resource usage
echo "=== Resource Usage ==="
kubectl top pod -n lair -l app=ollama

# GPU status (if available)
if kubectl exec -n lair statefulset/lair-ollama -- nvidia-smi >/dev/null 2>&1; then
    echo "=== GPU Status ==="
    kubectl exec -n lair statefulset/lair-ollama -- nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total --format=csv,noheader
fi
EOF

chmod +x ollama-performance.sh
```

---

## 🚨 Troubleshooting

### 🔧 **Common Issues**

#### **Model Loading Failures**
```bash
# Symptom: Models fail to load or respond slowly
# Check available memory
kubectl exec -n lair statefulset/lair-ollama -- free -h

# Check model size vs available memory
kubectl exec -n lair statefulset/lair-ollama -- ollama list
kubectl exec -n lair statefulset/lair-ollama -- df -h /root/.ollama

# Solution: Use smaller models or increase memory
kubectl patch statefulset lair-ollama -n lair -p '{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "ollama",
          "resources": {
            "limits": {
              "memory": "16Gi"
            }
          }
        }]
      }
    }
  }
}'
```

#### **GPU Not Detected**
```bash
# Symptom: GPU not available in container
# Check GPU on host
nvidia-smi

# Check GPU in container
kubectl exec -n lair statefulset/lair-ollama -- nvidia-smi

# Check NVIDIA runtime
kubectl describe pod -n lair -l app=ollama | grep -i runtime

# Solution: Ensure GPU addon enabled
sudo microk8s enable gpu
kubectl rollout restart statefulset/lair-ollama -n lair
```

#### **API Connection Issues**
```bash
# Symptom: Cannot connect to Ollama API
# Check service status
kubectl get services -n lair lair-ollama

# Check pod status
kubectl get pods -n lair -l app=ollama

# Check port forwarding
kubectl port-forward -n lair statefulset/lair-ollama 11434:11434

# Test local connection
curl http://localhost:11434/api/tags
```

#### **Performance Issues**
```bash
# Symptom: Slow inference or high latency
# Check resource constraints
kubectl describe pod -n lair -l app=ollama | grep -A 5 -B 5 "cpu\|memory"

# Check concurrent requests
kubectl exec -n lair statefulset/lair-ollama -- curl http://localhost:11434/api/ps

# Optimize performance settings
kubectl set env statefulset/lair-ollama -n lair \
  OLLAMA_NUM_PARALLEL=2 \
  OLLAMA_MAX_LOADED_MODELS=1
```

### 🔄 **Recovery Procedures**

#### **Restart Ollama Service**
```bash
# Restart StatefulSet
kubectl rollout restart statefulset/lair-ollama -n lair

# Check restart status
kubectl rollout status statefulset/lair-ollama -n lair

# Verify health after restart
kubectl exec -n lair statefulset/lair-ollama -- curl http://localhost:11434/api/tags
```

#### **Model Corruption Recovery**
```bash
# Remove corrupted model
kubectl exec -n lair statefulset/lair-ollama -- ollama rm corrupted-model:tag

# Re-download model
kubectl exec -n lair statefulset/lair-ollama -- ollama pull llama3.1:8b

# Verify model integrity
kubectl exec -n lair statefulset/lair-ollama -- ollama run llama3.1:8b "test prompt"
```

---

## 🔧 Advanced Configuration

### 🎛️ **Custom Model Configuration**

#### **Model Quantization**
```bash
# Use quantized models for better performance
kubectl exec -n lair statefulset/lair-ollama -- ollama pull llama3.1:8b-q4_0  # 4-bit quantization
kubectl exec -n lair statefulset/lair-ollama -- ollama pull llama3.1:8b-q8_0  # 8-bit quantization
```

#### **Custom Model Import**
```bash
# Import custom GGUF models
kubectl cp custom-model.gguf lair/lair-ollama-0:/tmp/
kubectl exec -n lair statefulset/lair-ollama -- ollama create custom-model -f /tmp/custom-model.gguf
```

### 🔌 **API Integration**

#### **OpenAI-Compatible Endpoints**
```bash
# Chat completions
POST http://lair-ollama/v1/chat/completions

# Text completions  
POST http://lair-ollama/v1/completions

# Embeddings
POST http://lair-ollama/v1/embeddings
```

#### **Custom Integration Example**
```python
# Python integration example
import requests

def query_ollama(prompt, model="llama3.1:8b"):
    url = "http://lair-ollama.lair.svc.cluster.local:11434/api/generate"
    data = {
        "model": model,
        "prompt": prompt,
        "stream": False
    }
    
    response = requests.post(url, json=data)
    return response.json()["response"]

# Usage
result = query_ollama("What is machine learning?")
print(result)
```

---

## 🎯 Best Practices

### 🚀 **Performance Best Practices**
- **Model Selection**: Choose appropriate model size for your hardware
- **Memory Management**: Monitor memory usage and adjust limits accordingly
- **GPU Utilization**: Use GPU acceleration when available
- **Concurrent Requests**: Tune parallel processing based on resources
- **Model Caching**: Keep frequently used models loaded

### 🔒 **Security Best Practices**
- **Internal Access**: Keep Ollama API internal-only (default configuration)
- **Network Policies**: Restrict network access to authorized services only
- **Resource Limits**: Set appropriate CPU and memory limits
- **Model Validation**: Verify model integrity after downloads
- **Access Control**: Use Kubernetes RBAC for pod access

### 📊 **Operational Best Practices**
- **Regular Monitoring**: Monitor performance and resource usage
- **Model Management**: Regular cleanup of unused models
- **Backup Strategy**: Include model storage in backup procedures
- **Update Planning**: Plan model updates during maintenance windows
- **Documentation**: Document custom models and configurations

---

**🎯 Ready to optimize your AI models?** Continue with [N8N Workflow Integration](n8n.md) or explore [ComfyUI Image Generation](comfyui.md)!
