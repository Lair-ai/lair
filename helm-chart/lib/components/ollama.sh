#!/bin/bash

# ============================================================================
# OLLAMA.SH - Ollama Component Configuration
# ============================================================================

# Configure Ollama component (interactive mode)
configure_ollama() {
  echo ""
  echo -e "${GREEN}🤖 Ollama Configuration${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Ollama is the local AI model server and management system (always enabled)"
  echo ""
  
  # Domain configuration
  echo -e "${BLUE}🌐 Ollama API Domain Configuration${NC}"
  echo "Ollama can be accessed externally or internally only:"
  echo "  • External: Specify domain for API HTTPS access (⚠️ security implications)"
  echo "  • Internal: Leave empty for Kubernetes DNS access only (recommended)"
  echo "  • Internal DNS: lair-ollama.lair.svc.cluster.local:11434"
  echo ""
  
  # LAN domain configuration - FORCED INTERNAL ONLY
  if [[ "$ENABLE_LAN_ACCESS" == "true" ]]; then
    echo -e "${BLUE}🏠 LAN Domain Configuration${NC}"
    echo "🔒 Ollama is configured for internal-only access for security reasons"
    OLLAMA_DOMAIN_LAN=""
    echo "ℹ️  Ollama LAN API: Internal access only via lair-ollama.lair.svc.cluster.local:11434"
    echo ""
  fi
  
  # Public domain configuration - FORCED INTERNAL ONLY
  if [[ "$ENABLE_PUBLIC_ACCESS" == "true" ]]; then
    echo -e "${BLUE}🌍 Public Domain Configuration${NC}"
    echo "🔒 Ollama is configured for internal-only access for security reasons"
    OLLAMA_DOMAIN_PUBLIC=""
    echo "ℹ️  Ollama public API: Internal access only via lair-ollama.lair.svc.cluster.local:11434"
    echo ""
  fi
  
  # Set legacy domain for backward compatibility
  if [[ "$ENABLE_PUBLIC_ACCESS" == "true" && -n "$OLLAMA_DOMAIN_PUBLIC" ]]; then
    OLLAMA_DOMAIN="$OLLAMA_DOMAIN_PUBLIC"
  elif [[ "$ENABLE_LAN_ACCESS" == "true" && -n "$OLLAMA_DOMAIN_LAN" ]]; then
    OLLAMA_DOMAIN="$OLLAMA_DOMAIN_LAN"
  else
    OLLAMA_DOMAIN=""
  fi
  
  # Storage configuration
  ask_storage_gb "Ollama models" "30" "OLLAMA_STORAGE_SIZE"
  echo "✅ Storage: $OLLAMA_STORAGE_SIZE"
  
  # GPU configuration
  if [[ "$HAS_GPU" == "y" || "$HAS_GPU" == "Y" ]]; then
    echo ""
    echo -e "${BLUE}🎮 GPU Configuration${NC}"
    echo "GPU detected and available for acceleration"
    read -p "🎮 VRAM allocation percentage [default: 80]: " VRAM_PERCENTAGE
    VRAM_PERCENTAGE=${VRAM_PERCENTAGE:-80}
    echo "✅ GPU acceleration enabled with ${VRAM_PERCENTAGE}% VRAM allocation"
    OLLAMA_GPU_ENABLED=true
  else
    echo ""
    echo "ℹ️  GPU: CPU-only mode (no GPU detected or available)"
    OLLAMA_GPU_ENABLED=false
    VRAM_PERCENTAGE=0
  fi
  
  # Image configuration
  echo ""
  echo -e "${BLUE}🖼️  Ollama Image Configuration${NC}"
  
  # Safety check: ensure IS_JETSON is defined
  IS_JETSON=${IS_JETSON:-"n"}
  
  if [ "$IS_JETSON" = "y" ]; then
    echo "Jetson platform detected - using optimized image"
    read -p "🖼️  Custom Ollama image (leave empty for auto-selection): " OLLAMA_IMAGE_INPUT
    OLLAMA_IMAGE=${OLLAMA_IMAGE_INPUT:-}
    if [ -z "$OLLAMA_IMAGE" ]; then
      # Auto-select appropriate Ollama image for Jetson
      OLLAMA_IMAGE="ollama/ollama:latest"  # Standard image that works on Jetson
      echo "✅ Auto-selected Jetson-compatible image: $OLLAMA_IMAGE"
    else
      echo "✅ Using custom image: $OLLAMA_IMAGE"
    fi
  else
    echo "Standard platform - using default image"
    read -p "🖼️  Custom Ollama image (leave empty for default): " OLLAMA_IMAGE_INPUT
    OLLAMA_IMAGE=${OLLAMA_IMAGE_INPUT:-}
    if [ -n "$OLLAMA_IMAGE" ]; then
      echo "✅ Using custom image: $OLLAMA_IMAGE"
    else
      echo "✅ Using default Ollama image"
    fi
  fi
  
  echo "✅ Ollama configuration completed"
}

# Configure Ollama component (non-interactive mode for config files)
configure_ollama_non_interactive() {
  echo ""
  echo -e "${GREEN}🤖 Ollama Configuration${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "🤖 Ollama: Always enabled"
  
  # Show configured domains - FORCE INTERNAL ONLY FOR SECURITY
  if [[ "$ENABLE_LAN_ACCESS" == "true" ]]; then
    if [ -n "$OLLAMA_DOMAIN_LAN" ]; then
      echo "   🏠 LAN Domain: $OLLAMA_DOMAIN_LAN"
    else
      echo "   🏠 LAN Access: Internal only (RECOMMENDED)"
    fi
  fi
  if [[ "$ENABLE_PUBLIC_ACCESS" == "true" ]]; then
    # Force internal only for public access
    OLLAMA_DOMAIN_PUBLIC=""
    echo "   🌍 Public Access: Internal only (FORCED FOR SECURITY)"
  fi
  
  echo "   💾 Storage: ${OLLAMA_STORAGE_GB}GB"
  echo "   🎮 GPU: $([ "$HAS_GPU" = "y" ] && echo "Enabled (${VRAM_PERCENTAGE}% VRAM)" || echo "Disabled")"
  if [ -n "$OLLAMA_IMAGE" ]; then
    echo "   🖼️  Image: $OLLAMA_IMAGE"
  fi
  echo "✅ Ollama configuration completed"
} 