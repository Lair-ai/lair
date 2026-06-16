#!/bin/bash

# ============================================================================
# COMFYUI.SH - ComfyUI Component Configuration
# ============================================================================

# Configure ComfyUI component (interactive mode)
configure_comfyui() {
  echo ""
  echo -e "${GREEN}🎨 ComfyUI Configuration${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "ComfyUI provides Stable Diffusion and AI image generation capabilities"
  echo ""
  
  # Safety check: ensure IS_JETSON is defined
  IS_JETSON=${IS_JETSON:-"n"}
  
  # Check GPU requirements based on platform
  if [ "$IS_JETSON" != "y" ] && [ "$IS_JETSON" != "Y" ] && [ "$HAS_GPU" != "y" ] && [ "$HAS_GPU" != "Y" ]; then
    echo -e "${YELLOW}⚠️  No GPU detected on non-Jetson system${NC}"
    echo -e "${YELLOW}   ComfyUI requires GPU acceleration and will be automatically disabled${NC}"
    echo -e "${YELLOW}   Platform: $([ "$IS_JETSON" = "y" ] && echo "Jetson" || echo "Standard") | GPU: $([ "$HAS_GPU" = "y" ] && echo "Available" || echo "Not detected")${NC}"
    echo "❌ ComfyUI: Disabled (GPU required for non-Jetson systems)"
    ENABLE_COMFYUI="n"
    COMFYUI_ENABLED=false
    COMFYUI_DOMAIN=""
    COMFYUI_DOMAIN_LAN=""
    COMFYUI_DOMAIN_PUBLIC=""
    COMFYUI_STORAGE_SIZE=""
    COMFYUI_STORAGE_GB=0
    return
  fi
  
  # Check if system has enough memory for ComfyUI (8GB threshold on total system memory)
  if [ "$TOTAL_MEMORY_MB" -lt 8192 ]; then
    echo -e "${YELLOW}⚠️  Limited memory system detected (< 8GB total)${NC}"
    echo -e "${YELLOW}   ComfyUI requires significant resources and will be automatically disabled${NC}"
    echo -e "${YELLOW}   Total system memory: $(echo "scale=1; $TOTAL_MEMORY_MB/1024" | bc)GB (minimum 8GB needed)${NC}"
    echo "❌ ComfyUI: Disabled (insufficient total memory < 8GB)"
    ENABLE_COMFYUI="n"
    COMFYUI_ENABLED=false
    COMFYUI_DOMAIN=""
    COMFYUI_DOMAIN_LAN=""
    COMFYUI_DOMAIN_PUBLIC=""
    COMFYUI_STORAGE_SIZE=""
    COMFYUI_STORAGE_GB=0
    return
  fi
  
    # Ask if user wants to enable ComfyUI
  if [ "$IS_JETSON" = "y" ] || [ "$IS_JETSON" = "Y" ]; then
    echo -e "${GREEN}✅ Jetson platform detected with GPU support${NC}"
    echo -e "${GREEN}   Total system memory: $(echo "scale=1; $TOTAL_MEMORY_MB/1024" | bc)GB${NC}"
  else
    echo -e "${GREEN}✅ Standard platform with GPU detected${NC}"
    echo -e "${GREEN}   Total system memory: $(echo "scale=1; $TOTAL_MEMORY_MB/1024" | bc)GB${NC}"
    echo -e "${BLUE}   💡 With overcommitment strategy, ComfyUI can burst to use system resources when other apps are idle${NC}"
  fi
  read -p "🎨 Enable ComfyUI for AI image generation? (y/n) [default: y]: " ENABLE_COMFYUI
  ENABLE_COMFYUI=${ENABLE_COMFYUI:-y}
  
  if [[ "$ENABLE_COMFYUI" == "y" || "$ENABLE_COMFYUI" == "Y" ]]; then
    echo "✅ ComfyUI enabled"
    
    # Domain configuration
    echo ""
    echo -e "${BLUE}🌐 ComfyUI Domain Configuration${NC}"
    echo "ComfyUI can be accessed externally or internally only:"
    echo "  • External: Specify your real domain for HTTPS access via ingress"
    echo "  • Internal: Leave empty for Kubernetes DNS access only"
    echo "  • Internal DNS: lair-comfyui.lair.svc.cluster.local:80"
    echo ""
    
    # LAN domain configuration
    if [[ "$ENABLE_LAN_ACCESS" == "true" ]]; then
      echo -e "${BLUE}🏠 LAN Domain Configuration${NC}"
      read -p "🌐 ComfyUI LAN subdomain [default: images] (leave empty for internal-only access): " COMFYUI_SUBDOMAIN_LAN
      COMFYUI_SUBDOMAIN_LAN=${COMFYUI_SUBDOMAIN_LAN:-images}
      
      if [ -n "$COMFYUI_SUBDOMAIN_LAN" ]; then
        COMFYUI_DOMAIN_LAN="$COMFYUI_SUBDOMAIN_LAN.$SYSTEM_HOSTNAME.local"
        echo "✅ ComfyUI LAN will be accessible at: https://$COMFYUI_DOMAIN_LAN"
      else
        COMFYUI_DOMAIN_LAN=""
        echo "ℹ️  ComfyUI LAN: Internal access only via lair-comfyui.lair.svc.cluster.local:80"
      fi
      echo ""
    fi
    
    # Public domain configuration
    if [[ "$ENABLE_PUBLIC_ACCESS" == "true" ]]; then
      echo -e "${BLUE}🌍 Public Domain Configuration${NC}"
      read -p "🌐 ComfyUI public domain (leave empty for internal-only access): " COMFYUI_DOMAIN_PUBLIC
      COMFYUI_DOMAIN_PUBLIC=${COMFYUI_DOMAIN_PUBLIC:-}
      
      if [ -n "$COMFYUI_DOMAIN_PUBLIC" ]; then
        echo "✅ ComfyUI public will be accessible at: https://$COMFYUI_DOMAIN_PUBLIC"
      else
        echo "ℹ️  ComfyUI public: Internal access only via lair-comfyui.lair.svc.cluster.local:80"
      fi
      echo ""
    fi
    
    # Set legacy domain for backward compatibility
    if [[ "$ENABLE_PUBLIC_ACCESS" == "true" && -n "$COMFYUI_DOMAIN_PUBLIC" ]]; then
      COMFYUI_DOMAIN="$COMFYUI_DOMAIN_PUBLIC"
    elif [[ "$ENABLE_LAN_ACCESS" == "true" && -n "$COMFYUI_DOMAIN_LAN" ]]; then
      COMFYUI_DOMAIN="$COMFYUI_DOMAIN_LAN"
    else
      COMFYUI_DOMAIN=""
    fi
    
    # Storage configuration
    ask_storage_gb "ComfyUI models and outputs" "15" "COMFYUI_STORAGE_SIZE"
    echo "✅ Storage: $COMFYUI_STORAGE_SIZE"
    
    # Image configuration
    echo ""
    echo -e "${BLUE}🖼️  ComfyUI Image Configuration${NC}"
    
    if [ "$IS_JETSON" = "y" ] || [ "$IS_JETSON" = "Y" ]; then
      echo "Jetson platform detected - using optimized image"
      COMFYUI_IMAGE="dustynv/comfyui:r36.4.3"
      echo "✅ Auto-selected Jetson-optimized image: $COMFYUI_IMAGE"
      # Reset additional variables for Jetson
      COMFYUI_LOW_VRAM=""
      COMFYUI_MODELS_DOWNLOAD=""
    else
      echo "Standard x86/x64 platform with GPU detected"
      echo -e "${GREEN}🚀 GPU detected: Using mmartial/comfyui-nvidia-docker optimized images${NC}"
      echo ""
      echo "Available ComfyUI CUDA versions (mmartial/comfyui-nvidia-docker):"
      echo "  1) ubuntu22_cuda12.3.2-latest - CUDA 12.3.2 on Ubuntu 22"
      echo "  2) ubuntu22_cuda12.4.1-latest - CUDA 12.4.1 on Ubuntu 22"
      echo "  3) ubuntu24_cuda12.5.1-latest - CUDA 12.5.1 on Ubuntu 24 (latest up to 20250320)"
      echo "  4) ubuntu24_cuda12.6.3-latest - CUDA 12.6.3 on Ubuntu 24 (recommended for GTX 10xx)"
      echo "  5) ubuntu24_cuda12.8-latest - CUDA 12.8 on Ubuntu 24 (minimum for Blackwell/RTX 50xx)"
      echo "  6) ubuntu24_cuda12.9-latest - CUDA 12.9 on Ubuntu 24"
      echo "  7) ubuntu24_cuda13.0-latest - CUDA 13.0 on Ubuntu 24 (untested)"
      echo ""
      echo -e "${BLUE}💡 Recommendations:${NC}"
      echo "   • GTX 10xx series: Choose option 4 (CUDA 12.6.3)"
      echo "   • RTX 20xx/30xx series: Choose option 3 or 4"
      echo "   • RTX 40xx series: Choose option 4 or 5"
      echo "   • RTX 50xx (Blackwell): Choose option 5 or higher"
      echo ""
      
      read -p "Select ComfyUI CUDA version [1-7, default: 4]: " image_choice
      image_choice=${image_choice:-4}
      
      case $image_choice in
        1)
          COMFYUI_IMAGE="mmartial/comfyui-nvidia-docker:ubuntu22_cuda12.3.2-latest"
          echo "✅ Selected CUDA 12.3.2 on Ubuntu 22: $COMFYUI_IMAGE"
          ;;
        2)
          COMFYUI_IMAGE="mmartial/comfyui-nvidia-docker:ubuntu22_cuda12.4.1-latest"
          echo "✅ Selected CUDA 12.4.1 on Ubuntu 22: $COMFYUI_IMAGE"
          ;;
        3)
          COMFYUI_IMAGE="mmartial/comfyui-nvidia-docker:ubuntu24_cuda12.5.1-latest"
          echo "✅ Selected CUDA 12.5.1 on Ubuntu 24 (latest up to 20250320): $COMFYUI_IMAGE"
          ;;
        4)
          COMFYUI_IMAGE="mmartial/comfyui-nvidia-docker:ubuntu24_cuda12.6.3-latest"
          echo "✅ Selected CUDA 12.6.3 on Ubuntu 24 (recommended for GTX 10xx): $COMFYUI_IMAGE"
          ;;
        5)
          COMFYUI_IMAGE="mmartial/comfyui-nvidia-docker:ubuntu24_cuda12.8-latest"
          echo "✅ Selected CUDA 12.8 on Ubuntu 24 (minimum for Blackwell/RTX 50xx): $COMFYUI_IMAGE"
          ;;
        6)
          COMFYUI_IMAGE="mmartial/comfyui-nvidia-docker:ubuntu24_cuda12.9-latest"
          echo "✅ Selected CUDA 12.9 on Ubuntu 24: $COMFYUI_IMAGE"
          ;;
        7)
          COMFYUI_IMAGE="mmartial/comfyui-nvidia-docker:ubuntu24_cuda13.0-latest"
          echo "✅ Selected CUDA 13.0 on Ubuntu 24 (untested): $COMFYUI_IMAGE"
          echo -e "${YELLOW}⚠️  Note: CUDA 13.0 is untested - use with caution${NC}"
          ;;
        *)
          COMFYUI_IMAGE="mmartial/comfyui-nvidia-docker:ubuntu24_cuda12.6.3-latest"
          echo "✅ Default selection (CUDA 12.6.3 - GTX 10xx recommended): $COMFYUI_IMAGE"
          ;;
      esac
      
      # Reset additional variables for mmartial images
      COMFYUI_LOW_VRAM=""
      COMFYUI_MODELS_DOWNLOAD=""
      
      # Configuration summary
      echo ""
      echo -e "${BLUE}📋 Configuration Summary:${NC}"
      echo "   🖼️  Selected Image: $COMFYUI_IMAGE"
      echo "   🎮 GPU Support: ✅ Enabled (NVIDIA CUDA)"
      echo "   💾 Storage: $COMFYUI_STORAGE_SIZE"
      echo "   🚀 Platform: $([ "$IS_JETSON" = "y" ] && echo "Jetson" || echo "Standard x86/x64")"
      
      # Performance expectations
      echo ""
      echo -e "${GREEN}⚡ Expected Performance: Excellent (GPU-optimized)${NC}"
      echo "   ⏱️  Typical generation time: 5-30 seconds per image"
      echo "   💾 VRAM: Optimized for modern NVIDIA GPUs"
    fi
    
    COMFYUI_ENABLED=true
    echo "✅ ComfyUI configuration completed"
  else
    echo "❌ ComfyUI disabled"
    COMFYUI_ENABLED=false
    COMFYUI_DOMAIN=""
    COMFYUI_DOMAIN_LAN=""
    COMFYUI_DOMAIN_PUBLIC=""
    COMFYUI_STORAGE_SIZE=""
    COMFYUI_STORAGE_GB=0
  fi
}

# Configure ComfyUI component (non-interactive mode for config files)
configure_comfyui_non_interactive() {
  echo ""
  echo -e "${GREEN}🎨 ComfyUI Configuration${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  if [ "$COMFYUI_ENABLED" = "true" ] || [ "$ENABLE_COMFYUI" = "y" ]; then
    echo "🎨 ComfyUI: Enabled"
    
    # Show configured domains
    if [[ "$ENABLE_LAN_ACCESS" == "true" ]]; then
      if [ -n "$COMFYUI_DOMAIN_LAN" ]; then
        echo "   🏠 LAN Domain: $COMFYUI_DOMAIN_LAN"
      else
        echo "   🏠 LAN Access: Internal only"
      fi
    fi
    if [[ "$ENABLE_PUBLIC_ACCESS" == "true" ]]; then
      if [ -n "$COMFYUI_DOMAIN_PUBLIC" ]; then
        echo "   🌍 Public Domain: $COMFYUI_DOMAIN_PUBLIC"
      else
        echo "   🌍 Public Access: Internal only"
      fi
    fi
    
    echo "   💾 Storage: ${COMFYUI_STORAGE_GB}GB"
    echo "   🎮 GPU: $([ "$HAS_GPU" = "y" ] && echo "Enabled" || echo "Disabled")"
    
    if [ -n "$COMFYUI_IMAGE" ]; then
      echo "   🖼️  Image: $COMFYUI_IMAGE"
      
      # Validate image format and show warnings if invalid
      if [[ ! "$COMFYUI_IMAGE" =~ ^[a-zA-Z0-9._/-]+:[a-zA-Z0-9._-]+$ ]]; then
        echo "   ⚠️  Warning: Image format may be invalid (expected: registry/repo:tag)"
      fi
      
      # Show additional configuration for special images
      if [[ "$COMFYUI_IMAGE" == "dustynv/comfyui"* ]]; then
        echo "   🔧 Configuration: Jetson-optimized"
        echo "   🎯 Target: NVIDIA Jetson platforms"
        echo "   🚀 Version: $(echo "$COMFYUI_IMAGE" | cut -d':' -f2)"
      elif [[ "$COMFYUI_IMAGE" == "mmartial/comfyui-nvidia-docker"* ]]; then
        echo "   🔧 Configuration: mmartial NVIDIA Docker optimized"
        echo "   🎯 Target: NVIDIA GPU systems"
        
        # Extract CUDA version from tag
        tag=$(echo "$COMFYUI_IMAGE" | cut -d':' -f2)
        if [[ "$tag" == *"cuda12.3.2"* ]]; then
          echo "   🚀 CUDA Version: 12.3.2 on Ubuntu 22"
        elif [[ "$tag" == *"cuda12.4.1"* ]]; then
          echo "   🚀 CUDA Version: 12.4.1 on Ubuntu 22"
        elif [[ "$tag" == *"cuda12.5.1"* ]]; then
          echo "   🚀 CUDA Version: 12.5.1 on Ubuntu 24 (latest up to 20250320)"
        elif [[ "$tag" == *"cuda12.6.3"* ]]; then
          echo "   🚀 CUDA Version: 12.6.3 on Ubuntu 24 (recommended for GTX 10xx)"
        elif [[ "$tag" == *"cuda12.8"* ]]; then
          echo "   🚀 CUDA Version: 12.8 on Ubuntu 24 (minimum for Blackwell/RTX 50xx)"
        elif [[ "$tag" == *"cuda12.9"* ]]; then
          echo "   🚀 CUDA Version: 12.9 on Ubuntu 24"
        elif [[ "$tag" == *"cuda13.0"* ]]; then
          echo "   🚀 CUDA Version: 13.0 on Ubuntu 24 (untested)"
          echo "   ⚠️  Warning: CUDA 13.0 is untested"
        else
          echo "   🚀 CUDA Version: Custom/Unknown"
        fi
      fi
      
      # Show additional custom configuration if set
      if [ -n "$COMFYUI_LOW_VRAM" ]; then
        echo "   🔧 Low VRAM Mode: $COMFYUI_LOW_VRAM"
      fi
      
      if [ -n "$COMFYUI_MODELS_DOWNLOAD" ]; then
        echo "   📦 Model Download Preset: $COMFYUI_MODELS_DOWNLOAD"
        case "$COMFYUI_MODELS_DOWNLOAD" in
          "schnell")
            echo "      → Flux Schnell model (space-efficient)"
            ;;
          "gguf")
            echo "      → GGUF quantized models (CPU-optimized)"
            ;;
          *)
            echo "      → Custom model configuration"
            ;;
        esac
      fi
      
      # Show GPU compatibility status
      echo "   🎮 GPU Status: ✅ GPU acceleration enabled"
    else
      # This should never happen with the new logic since we only allow Jetson or GPU systems
      echo "   🖼️  Image: Auto-selected based on platform"
      echo "   🎮 GPU Status: ✅ GPU acceleration enabled"
    fi
    
    COMFYUI_ENABLED=true
  else
    echo "❌ ComfyUI: Disabled"
    COMFYUI_ENABLED=false
    COMFYUI_STORAGE_SIZE=""
    COMFYUI_STORAGE_GB=0
  fi
  
  echo "✅ ComfyUI configuration completed"
} 
