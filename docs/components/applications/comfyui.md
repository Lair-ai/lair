# 🎨 ComfyUI - AI Image Generation Platform

> **Complete guide to ComfyUI configuration, model management, and AI image generation in Lair**

ComfyUI is the powerful AI image generation platform in Lair, providing node-based workflow creation for Stable Diffusion and other AI image models. This guide covers installation, configuration, workflow creation, and optimization.

---

## 🎯 Overview

ComfyUI serves as the visual AI image generation platform in Lair, offering a node-based interface for creating complex image generation workflows with Stable Diffusion and other AI models.

### ✨ **Key Features**
- **🎨 Node-Based Interface**: Visual workflow creation for complex image generation
- **🤖 Multiple AI Models**: Support for Stable Diffusion, ControlNet, and custom models
- **🎮 GPU Acceleration**: NVIDIA GPU and Tegra optimization for fast generation
- **📦 Model Management**: Easy installation and switching between different models
- **🔧 Custom Nodes**: Extensible architecture with community plugins
- **⚡ Performance Optimization**: Memory-efficient processing and batch generation
- **🖼️ Advanced Features**: ControlNet, LoRA, embeddings, and custom workflows

### 🔗 **Integration Points**
- **N8N**: Automated image generation workflows
- **MinIO**: Storage for generated images and models
- **OpenWebUI**: Potential integration for AI-powered image requests
- **API Access**: REST API for programmatic image generation

---

## 🚀 Getting Started

### 🌐 **Accessing ComfyUI**

#### **Web Interface Access**
```bash
# LAN Access (default configuration)
https://images.hostname.local

# Public Access (if configured)
https://images.example.com

# Internal Access (from within cluster)
http://lair-comfyui.lair.svc.cluster.local:8188
```

#### **System Requirements**
```yaml
# Minimum Requirements
GPU: NVIDIA GPU with 4GB+ VRAM (or Jetson Tegra)
RAM: 8GB+ system memory
Storage: 20GB+ for models and outputs
Platform: x86_64 with GPU or ARM64 Jetson

# Recommended Requirements
GPU: NVIDIA GPU with 8GB+ VRAM
RAM: 16GB+ system memory
Storage: 50GB+ for multiple models
```

### 🔧 **Initial Setup**

#### **First Access**
```bash
# Check ComfyUI status
kubectl get pods -n lair -l app=comfyui

# Access ComfyUI interface
# Navigate to your configured domain
# Load default workflow or create new one
```

#### **Default Workflow**
ComfyUI starts with a basic text-to-image workflow:
1. **Text Prompt Input** → Model processing → **Image Output**
2. **Checkpoint Loader** → **CLIP Text Encode** → **KSampler** → **VAE Decode** → **Save Image**

---

## 🔧 Architecture & Deployment

### 🏗️ **ComfyUI Architecture**

#### **Container Architecture**
```
┌─────────────────────────────────────────────────────────────────┐
│                   🎨 COMFYUI ARCHITECTURE                       │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │   ComfyUI Web   │  │   Model Store   │  │   GPU Engine    │  │
│  │   Interface     │  │  (Checkpoints)  │  │  (Generation)   │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                                │
┌─────────────────────────────────────────────────────────────────┐
│                    💾 STORAGE ARCHITECTURE                      │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │     Models      │  │     Output      │  │  Custom Nodes   │  │
│  │ (Checkpoints)   │  │   (Images)      │  │   (Plugins)     │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

#### **Deployment Configuration**
```yaml
# ComfyUI Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: comfyui
  namespace: lair
spec:
  replicas: 1  # Single replica for GPU resource management
  selector:
    matchLabels:
      app: comfyui
  template:
    spec:
      runtimeClassName: nvidia  # GPU runtime
      securityContext:
        fsGroup: 1000
```

#### **GPU Configuration**
```yaml
# GPU-enabled configuration
spec:
  template:
    spec:
      containers:
      - name: comfyui
        resources:
          limits:
            nvidia.com/gpu: 1  # GPU allocation
        env:
        - name: NVIDIA_VISIBLE_DEVICES
          value: "all"
        - name: NVIDIA_DRIVER_CAPABILITIES
          value: "compute,utility"
```

### 🖼️ **Container Images**

#### **Standard Platform (x86_64)**
```yaml
comfyUI:
  image:
    repository: mmartial/comfyui
    tag: latest
  
  # Alternative high-performance image
  image:
    repository: comfyui/comfyui
    tag: latest
```

#### **Jetson Platform (ARM64)**
```yaml
comfyUI:
  image:
    repository: dustynv/comfyui
    tag: r36.3.0  # JetPack version specific
  
  # Jetson-optimized settings
  gpuEnabled: true
  lowVram: true  # Memory optimization for Jetson
```

### 📊 **Resource Configuration**

#### **Standard Configuration**
```yaml
comfyUI:
  resources:
    limits:
      memory: "8Gi"      # Burst memory for large models
      cpu: "2000m"       # CPU for preprocessing
      nvidia.com/gpu: 1  # Single GPU
    requests:
      memory: "4Gi"      # Guaranteed memory
      cpu: "1000m"       # Base CPU
  
  persistence:
    size: "50Gi"  # Models and outputs storage
    storageClassName: "longhorn"
```

#### **Jetson Optimization**
```yaml
comfyUI:
  resources:
    limits:
      memory: "4Gi"      # Reduced for Jetson
      cpu: "1500m"
    requests:
      memory: "2Gi"
      cpu: "750m"
  
  # Jetson-specific optimizations
  lowVram: true
  persistence:
    size: "30Gi"
    storageClassName: "lair-hostpath"
```

---

## 🎨 Model Management

### 📦 **Model Types**

#### **Checkpoint Models (Base Models)**
```bash
# Popular Stable Diffusion models
Stable Diffusion 1.5    # 4GB - General purpose
Stable Diffusion XL     # 7GB - High resolution
Realistic Vision        # 2GB - Photorealistic images
DreamShaper            # 2GB - Artistic generation
Anything V3            # 4GB - Anime/cartoon style
```

#### **ControlNet Models**
```bash
# ControlNet for guided generation
control_canny          # Edge detection
control_depth          # Depth maps
control_pose           # Human pose
control_scribble       # Sketch to image
control_seg            # Segmentation
```

#### **LoRA Models (Style Adapters)**
```bash
# LoRA for style modification
portrait_lora          # Portrait enhancement
landscape_lora         # Landscape styles
anime_lora            # Anime character styles
photorealistic_lora   # Photo enhancement
```

### 📥 **Model Installation**

#### **Manual Model Installation**
```bash
# Access ComfyUI container
kubectl exec -it -n lair deployment/lair-comfyui -- /bin/bash

# Navigate to models directory
cd /data/models/checkpoints  # or /basedir/models/checkpoints

# Download model (example)
wget https://huggingface.co/runwayml/stable-diffusion-v1-5/resolve/main/v1-5-pruned-emaonly.ckpt

# Verify model installation
ls -la /data/models/checkpoints/
```

#### **ComfyUI Manager Installation**
```bash
# Install ComfyUI Manager (if not present)
kubectl exec -n lair deployment/lair-comfyui -- git clone https://github.com/ltdrdata/ComfyUI-Manager.git /data/custom_nodes/ComfyUI-Manager

# Restart ComfyUI to load manager
kubectl rollout restart deployment/lair-comfyui -n lair
```

#### **Model Installation via ComfyUI Manager**
1. Access ComfyUI web interface
2. Click **Manager** button
3. Go to **Model Manager**
4. Browse and install models directly
5. Models are automatically placed in correct directories

### 🔄 **Model Organization**

#### **Directory Structure**
```bash
# Standard model organization
/data/models/
├── checkpoints/          # Base Stable Diffusion models
├── controlnet/          # ControlNet models
├── loras/              # LoRA style adapters
├── vae/                # VAE models
├── embeddings/         # Textual inversions
├── upscale_models/     # Upscaling models
└── clip_vision/        # CLIP models

# Custom nodes and extensions
/data/custom_nodes/
├── ComfyUI-Manager/    # Model and node manager
├── ComfyUI-Impact-Pack/ # Advanced nodes
└── other-extensions/
```

#### **Model Management Commands**
```bash
# Check model storage usage
kubectl exec -n lair deployment/lair-comfyui -- df -h /data/models

# List installed models
kubectl exec -n lair deployment/lair-comfyui -- find /data/models -name "*.ckpt" -o -name "*.safetensors"

# Clean up old models
kubectl exec -n lair deployment/lair-comfyui -- rm /data/models/checkpoints/old-model.ckpt
```

---

## 🎨 Workflow Creation

### 📝 **Basic Workflows**

#### **Text-to-Image Workflow**
```json
{
  "workflow": {
    "nodes": {
      "1": {
        "class_type": "CheckpointLoaderSimple",
        "inputs": {
          "ckpt_name": "v1-5-pruned-emaonly.ckpt"
        }
      },
      "2": {
        "class_type": "CLIPTextEncode",
        "inputs": {
          "text": "a beautiful landscape, detailed, 4k",
          "clip": ["1", 1]
        }
      },
      "3": {
        "class_type": "CLIPTextEncode",
        "inputs": {
          "text": "blurry, low quality, distorted",
          "clip": ["1", 1]
        }
      },
      "4": {
        "class_type": "KSampler",
        "inputs": {
          "seed": 42,
          "steps": 20,
          "cfg": 7.0,
          "sampler_name": "euler",
          "scheduler": "normal",
          "model": ["1", 0],
          "positive": ["2", 0],
          "negative": ["3", 0]
        }
      }
    }
  }
}
```

#### **Image-to-Image Workflow**
```json
{
  "workflow": {
    "nodes": {
      "1": {
        "class_type": "LoadImage",
        "inputs": {
          "image": "input_image.png"
        }
      },
      "2": {
        "class_type": "CheckpointLoaderSimple",
        "inputs": {
          "ckpt_name": "v1-5-pruned-emaonly.ckpt"
        }
      },
      "3": {
        "class_type": "KSampler",
        "inputs": {
          "denoise": 0.7,
          "latent_image": ["1", 0],
          "model": ["2", 0]
        }
      }
    }
  }
}
```

### 🎛️ **Advanced Workflows**

#### **ControlNet Workflow**
```json
{
  "workflow": {
    "nodes": {
      "controlnet_loader": {
        "class_type": "ControlNetLoader",
        "inputs": {
          "control_net_name": "control_canny.pth"
        }
      },
      "canny_preprocessor": {
        "class_type": "CannyEdgePreprocessor",
        "inputs": {
          "image": ["input_image", 0],
          "low_threshold": 100,
          "high_threshold": 200
        }
      },
      "controlnet_apply": {
        "class_type": "ControlNetApply",
        "inputs": {
          "conditioning": ["positive_prompt", 0],
          "control_net": ["controlnet_loader", 0],
          "image": ["canny_preprocessor", 0],
          "strength": 1.0
        }
      }
    }
  }
}
```

#### **Batch Processing Workflow**
```json
{
  "workflow": {
    "nodes": {
      "batch_loader": {
        "class_type": "LoadImageBatch",
        "inputs": {
          "mode": "incremental",
          "index": 0,
          "label": "Batch"
        }
      },
      "batch_processor": {
        "class_type": "KSampler",
        "inputs": {
          "seed": ["seed_generator", 0],
          "steps": 20,
          "batch_size": 4
        }
      }
    }
  }
}
```

---

## ⚡ Performance Optimization

### 🚀 **GPU Optimization**

#### **Memory Management**
```yaml
# GPU memory optimization
comfyUI:
  extraEnv:
    - name: PYTORCH_CUDA_ALLOC_CONF
      value: "max_split_size_mb:512"
    - name: CUDA_VISIBLE_DEVICES
      value: "0"
  
  # Low VRAM mode for Jetson
  lowVram: true
```

#### **Performance Settings**
```bash
# ComfyUI performance configuration
# Access via web interface → Settings

# Memory optimization
"lowvram": true,              # For <8GB VRAM
"normalvram": false,          # Standard mode
"highvram": false,            # For >12GB VRAM

# Processing optimization
"preview_method": "auto",     # Preview generation
"disable_smart_memory": false, # Memory management
"force_fp16": true,           # Half precision for speed
```

### 💾 **Memory Optimization**

#### **Model Loading Strategies**
```python
# Model loading optimization
{
  "model_management": "gpu",     # Keep models in GPU memory
  "vae_decode_tiled": true,     # Tiled VAE for large images
  "attention_split": true,      # Split attention for memory
  "free_memory": 0.9           # Free memory threshold
}
```

#### **Batch Processing**
```json
{
  "batch_settings": {
    "batch_size": 4,            # Process multiple images
    "queue_size": 10,           # Queue management
    "parallel_processing": true  # Parallel execution
  }
}
```

### 🔧 **Jetson Optimization**

#### **Jetson-Specific Settings**
```yaml
comfyUI:
  # Jetson memory constraints
  resources:
    limits:
      memory: "4Gi"
    requests:
      memory: "2Gi"
  
  # Jetson optimizations
  extraEnv:
    - name: COMFYUI_LOWVRAM
      value: "true"
    - name: PYTORCH_CUDA_ALLOC_CONF
      value: "max_split_size_mb:256"
```

#### **Model Selection for Jetson**
```bash
# Recommended models for Jetson
Stable Diffusion 1.5 (pruned)  # 2GB - Best balance
TinySD                          # 1GB - Fastest generation
OpenJourney                     # 2GB - Artistic style
Waifu Diffusion               # 2GB - Anime optimized
```

---

## 🔍 Monitoring & Management

### 📊 **Performance Monitoring**

#### **Resource Usage**
```bash
# Monitor ComfyUI resource usage
kubectl top pod -n lair -l app=comfyui

# GPU utilization
kubectl exec -n lair deployment/lair-comfyui -- nvidia-smi

# Memory usage
kubectl exec -n lair deployment/lair-comfyui -- free -h

# Storage usage
kubectl exec -n lair deployment/lair-comfyui -- df -h /data
```

#### **Generation Monitoring**
```bash
# Monitor generation queue
kubectl logs -n lair deployment/lair-comfyui | grep -i "queue\|generation\|progress"

# Check active workflows
kubectl exec -n lair deployment/lair-comfyui -- curl http://localhost:8188/queue

# Monitor output directory
kubectl exec -n lair deployment/lair-comfyui -- ls -la /data/output/
```

### 📝 **Logging & Debugging**

#### **Log Analysis**
```bash
# ComfyUI application logs
kubectl logs -n lair deployment/lair-comfyui -f

# Filter for errors
kubectl logs -n lair deployment/lair-comfyui | grep -i "error\|fail\|exception"

# Model loading logs
kubectl logs -n lair deployment/lair-comfyui | grep -i "model\|checkpoint\|loading"
```

#### **Debug Mode**
```yaml
# Enable debug logging
comfyUI:
  extraEnv:
    - name: COMFYUI_DEBUG
      value: "true"
    - name: PYTORCH_CUDA_LAUNCH_BLOCKING
      value: "1"  # For CUDA debugging
```

---

## 🚨 Troubleshooting

### 🔧 **Common Issues**

#### **Out of Memory Errors**
```bash
# Symptom: CUDA out of memory errors
# Check GPU memory
kubectl exec -n lair deployment/lair-comfyui -- nvidia-smi

# Solution: Enable low VRAM mode
kubectl patch deployment lair-comfyui -n lair -p '{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "comfyui",
          "env": [
            {"name": "COMFYUI_LOWVRAM", "value": "true"},
            {"name": "PYTORCH_CUDA_ALLOC_CONF", "value": "max_split_size_mb:256"}
          ]
        }]
      }
    }
  }
}'
```

#### **Model Loading Failures**
```bash
# Symptom: Models fail to load
# Check model files
kubectl exec -n lair deployment/lair-comfyui -- ls -la /data/models/checkpoints/

# Check file permissions
kubectl exec -n lair deployment/lair-comfyui -- ls -la /data/models/

# Solution: Fix permissions
kubectl exec -n lair deployment/lair-comfyui -- chown -R 1000:1000 /data/models/
```

#### **Slow Generation**
```bash
# Symptom: Very slow image generation
# Check GPU utilization
kubectl exec -n lair deployment/lair-comfyui -- nvidia-smi

# Check CPU usage
kubectl top pod -n lair -l app=comfyui

# Solution: Optimize settings
# Use smaller models, enable optimizations, check resource limits
```

#### **Web Interface Not Loading**
```bash
# Symptom: Cannot access ComfyUI web interface
# Check pod status
kubectl get pods -n lair -l app=comfyui

# Check service
kubectl get services -n lair lair-comfyui

# Check ingress
kubectl describe ingress -n lair lair-ingress

# Test internal connectivity
kubectl exec -n lair deployment/lair-openwebui -- curl http://lair-comfyui:8188
```

### 🔄 **Recovery Procedures**

#### **Restart ComfyUI**
```bash
# Restart deployment
kubectl rollout restart deployment/lair-comfyui -n lair

# Check restart status
kubectl rollout status deployment/lair-comfyui -n lair

# Verify functionality
kubectl exec -n lair deployment/lair-comfyui -- curl http://localhost:8188
```

#### **Model Recovery**
```bash
# Backup models
kubectl exec -n lair deployment/lair-comfyui -- tar -czf /tmp/models-backup.tar.gz /data/models/

# Restore models
kubectl cp models-backup.tar.gz lair/lair-comfyui-0:/tmp/
kubectl exec -n lair deployment/lair-comfyui -- tar -xzf /tmp/models-backup.tar.gz -C /
```

---

## 🔧 Advanced Configuration

### 🎛️ **Custom Nodes**

#### **Installing Custom Nodes**
```bash
# Install via ComfyUI Manager (recommended)
# 1. Access ComfyUI web interface
# 2. Click Manager → Install Custom Nodes
# 3. Browse and install desired nodes

# Manual installation
kubectl exec -n lair deployment/lair-comfyui -- git clone https://github.com/author/custom-node.git /data/custom_nodes/custom-node

# Install dependencies
kubectl exec -n lair deployment/lair-comfyui -- pip install -r /data/custom_nodes/custom-node/requirements.txt
```

#### **Popular Custom Nodes**
```bash
# Essential custom nodes
ComfyUI-Manager          # Node and model management
ComfyUI-Impact-Pack      # Advanced processing nodes
ComfyUI-AnimateDiff      # Animation generation
ComfyUI-ControlNet-Aux   # Additional ControlNet preprocessors
ComfyUI-Custom-Scripts   # Utility scripts
```

### 🔌 **API Integration**

#### **REST API Usage**
```python
# Python API client example
import requests
import json

def generate_image(prompt, negative_prompt="", steps=20):
    workflow = {
        "prompt": {
            "1": {
                "class_type": "CheckpointLoaderSimple",
                "inputs": {"ckpt_name": "v1-5-pruned-emaonly.ckpt"}
            },
            "2": {
                "class_type": "CLIPTextEncode",
                "inputs": {"text": prompt, "clip": ["1", 1]}
            },
            "3": {
                "class_type": "CLIPTextEncode", 
                "inputs": {"text": negative_prompt, "clip": ["1", 1]}
            },
            "4": {
                "class_type": "KSampler",
                "inputs": {
                    "seed": 42,
                    "steps": steps,
                    "cfg": 7.0,
                    "sampler_name": "euler",
                    "scheduler": "normal",
                    "model": ["1", 0],
                    "positive": ["2", 0],
                    "negative": ["3", 0]
                }
            }
        }
    }
    
    response = requests.post(
        "http://lair-comfyui:8188/prompt",
        json=workflow
    )
    return response.json()

# Usage
result = generate_image("a beautiful sunset over mountains")
```

#### **N8N Integration**
```json
{
  "name": "ComfyUI Image Generation",
  "nodes": [
    {
      "name": "Trigger",
      "type": "n8n-nodes-base.webhook"
    },
    {
      "name": "ComfyUI Generate",
      "type": "n8n-nodes-base.httpRequest",
      "parameters": {
        "url": "http://lair-comfyui:8188/prompt",
        "method": "POST",
        "body": {
          "prompt": "={{$json.workflow}}"
        }
      }
    }
  ]
}
```

---

## 🎯 Best Practices

### 🚀 **Performance Best Practices**
- **Model Selection**: Choose appropriate model size for your hardware
- **Memory Management**: Use low VRAM mode for memory-constrained systems
- **Batch Processing**: Process multiple images together for efficiency
- **GPU Utilization**: Monitor GPU usage and optimize settings
- **Storage Management**: Regular cleanup of output images

### 🔒 **Security Best Practices**
- **Access Control**: Restrict access to authorized users only
- **Model Validation**: Verify model integrity after downloads
- **Resource Limits**: Set appropriate CPU and memory limits
- **Network Security**: Use internal access when possible
- **Content Filtering**: Implement content moderation for generated images

### 📊 **Operational Best Practices**
- **Regular Monitoring**: Monitor performance and resource usage
- **Model Management**: Organize and backup important models
- **Workflow Documentation**: Document complex workflows
- **Update Planning**: Plan updates during maintenance windows
- **Backup Strategy**: Include models and workflows in backup procedures

---

**🎯 Ready to create amazing AI art?** Continue with [MinIO Object Storage](minio.md) or explore [PostgreSQL Database](README.md)!
