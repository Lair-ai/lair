#!/bin/bash

# ============================================================================
# COMPONENT-CONFIG.SH - Component Configuration Orchestrator
# ============================================================================
#
# This file contains ONLY cross-component configuration and orchestration.
# Individual component configurations are in separate files under lib/components/
#
# MODULAR ARCHITECTURE:
# 
# 🏗️  CROSS-COMPONENT FUNCTIONS (this file):
#   - detect_system_hostname()         → Automatic hostname detection for LAN domains
#   - configure_access_mode_and_email() → LAN/Public access modes configuration
#   - configure_all_components()       → Component orchestration
#   - show_resource_summary()          → Resource allocation display
#
# 🧩 COMPONENT-SPECIFIC FUNCTIONS (lib/components/*.sh):
#   - configure_COMPONENT()            → Interactive configuration
#   - configure_COMPONENT_non_interactive() → Config file mode
#   - component-specific helpers       → Custom logic per component
#
# 📁 ADDING NEW COMPONENTS:
#   1. Copy lib/components/_template.sh to lib/components/newcomponent.sh
#   2. Update component names and configuration logic
#   3. Add source + function call to configure_all_components() below
#   4. Add domain configuration to lair-config-template.yaml
#   5. Test with both interactive and config file modes
#
# ============================================================================

# Detect system hostname for LAN domain generation
detect_system_hostname() {
  local detected_hostname=$(hostname | sed 's/\.local$//')  # Remove .local if present
  if [ -z "$detected_hostname" ]; then
    detected_hostname="lair"  # Fallback hostname
  fi
  
  echo "🏠 System hostname auto-detected: $detected_hostname"
  echo "   This will be used for LAN domains: subdomain.$detected_hostname.local"
  echo ""
  
  # Validate hostname format
  validate_hostname() {
    local hostname="$1"
    # Check if hostname contains only valid characters (letters, numbers, hyphens)
    if [[ ! "$hostname" =~ ^[a-zA-Z0-9-]+$ ]]; then
      return 1
    fi
    # Check if hostname doesn't start or end with hyphen
    if [[ "$hostname" =~ ^- ]] || [[ "$hostname" =~ -$ ]]; then
      return 1
    fi
    # Check reasonable length
    if [ ${#hostname} -gt 63 ] || [ ${#hostname} -lt 1 ]; then
      return 1
    fi
    return 0
  }
  
  # Ask for confirmation or customization
  echo "Examples of good LAN hostnames:"
  echo "  • lair → subdomain.lair.local"
  echo "  • myserver → subdomain.myserver.local"
  echo "  • ai-lab → subdomain.ai-lab.local"
  echo ""
  
  while true; do
    read -p "🏠 LAN hostname for .local domains [default: $detected_hostname]: " user_hostname
    user_hostname=${user_hostname:-$detected_hostname}
    
    # Convert to lowercase and remove any .local suffix if user added it
    user_hostname=$(echo "$user_hostname" | tr '[:upper:]' '[:lower:]' | sed 's/\.local$//')
    
    if validate_hostname "$user_hostname"; then
      SYSTEM_HOSTNAME="$user_hostname"
      echo "✅ LAN hostname confirmed: $SYSTEM_HOSTNAME"
      echo "   LAN domains will be: subdomain.$SYSTEM_HOSTNAME.local"
      break
    else
      echo "❌ Invalid hostname format. Please use only letters, numbers, and hyphens."
      echo "   Examples: lair, myserver, ai-lab"
      echo ""
    fi
  done
}

# Detect system hostname for non-interactive mode
detect_system_hostname_non_interactive() {
  # Try to use configured hostname first, fall back to detection
  if [ -n "$SYSTEM_HOSTNAME" ]; then
    echo "🏠 System hostname from config: $SYSTEM_HOSTNAME"
  else
    SYSTEM_HOSTNAME=$(hostname | sed 's/\.local$//')  # Remove .local if present
    if [ -z "$SYSTEM_HOSTNAME" ]; then
      SYSTEM_HOSTNAME="lair"  # Fallback hostname
    fi
    echo "🏠 System hostname auto-detected: $SYSTEM_HOSTNAME"
  fi
  echo "   LAN domains will be: subdomain.$SYSTEM_HOSTNAME.local"
}

# Configure access modes - supports both LAN and Public access simultaneously
configure_access_mode_and_email() {
  echo ""
  echo -e "${GREEN}🌐 Access Mode & Certificate Configuration${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  echo "Lair can be configured for multiple access modes simultaneously:"
  echo "  • 🏠 LAN: Local network access with .local domains (no Let's Encrypt)"
  echo "  • 🌍 Public: Internet access with public domains (Let's Encrypt enabled)"
  echo ""
  
  # Configure LAN access
  echo -e "${BLUE}🏠 LAN Access Configuration${NC}"
  echo "Configure local network access with .local domains"
  echo ""
  read -p "Enable LAN access with .local domains? (y/n) [default: y]: " ENABLE_LAN_ACCESS
  ENABLE_LAN_ACCESS=${ENABLE_LAN_ACCESS:-y}
  
  if [[ "$ENABLE_LAN_ACCESS" == "y" || "$ENABLE_LAN_ACCESS" == "Y" ]]; then
    ENABLE_LAN_ACCESS="true"
    echo "✅ LAN access enabled"
    echo "  • Services will be accessible on local network"
    echo "  • Uses .local domains (e.g., chat.myhost.local)"
    echo "  • No Let's Encrypt certificates needed"
    echo ""
    
    # Detect system hostname for LAN domain generation (only if LAN access is enabled)
    detect_system_hostname
    echo ""
    
    # Configure TLS for LAN access
    echo -e "${BLUE}🔐 LAN TLS Configuration${NC}"
    echo "Do you want to enable HTTPS for .local domains using mkcert certificates?"
    echo "  • ✅ Enables: Browser-trusted SSL certificates for .local domains"
    echo "  • ❓ Requires: mkcert installed on client machines"
    echo "  • 🛠️  Setup: Run ./generate-lan-certificates.sh after deployment"
    echo ""
    read -p "Enable HTTPS for LAN domains? (y/n) [default: n]: " ENABLE_LAN_TLS
    ENABLE_LAN_TLS=${ENABLE_LAN_TLS:-n}
    
    if [[ "$ENABLE_LAN_TLS" == "y" || "$ENABLE_LAN_TLS" == "Y" ]]; then
      ENABLE_LAN_TLS="true"
      echo "✅ LAN TLS enabled"
      echo "  • HTTPS will be available for .local domains"
      echo "  • Run ./generate-lan-certificates.sh to create certificates"
      echo "  • Install mkcert on client machines for trusted certificates"
    else
      ENABLE_LAN_TLS="false"
      echo "❌ LAN TLS disabled - using HTTP only"
    fi
    echo ""
  else
    ENABLE_LAN_ACCESS="false"
    ENABLE_LAN_TLS="false"
    echo "❌ LAN access disabled"
    echo ""
  fi
  
  # Configure Public access
  echo -e "${BLUE}🌍 Public Access Configuration${NC}"
  echo "Configure internet access with public domains and Let's Encrypt"
  echo ""
  
  # If LAN access is disabled, automatically enable public access
  if [[ "$ENABLE_LAN_ACCESS" == "false" ]]; then
    echo "✅ Public access automatically enabled (LAN access is disabled)"
    echo "  • Services will be accessible from internet"
    echo "  • Uses public domains (e.g., chat.mycompany.com)"
    echo "  • Let's Encrypt will provide automatic TLS certificates"
    ENABLE_PUBLIC_ACCESS="true"
    echo ""
    
    # Ask for email for Let's Encrypt
    echo -e "${GREEN}📧 Certificate Email Configuration${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    read -p "Email for Let's Encrypt certificates [default: admin@example.com]: " CERT_EMAIL
    CERT_EMAIL=${CERT_EMAIL:-admin@example.com}
    echo "✅ Certificate email: $CERT_EMAIL"
    echo ""
  else
    # LAN access is enabled, ask if user also wants public access
    read -p "Enable public access with internet domains? (y/n) [default: n]: " ENABLE_PUBLIC_ACCESS
    ENABLE_PUBLIC_ACCESS=${ENABLE_PUBLIC_ACCESS:-n}
    
    if [[ "$ENABLE_PUBLIC_ACCESS" == "y" || "$ENABLE_PUBLIC_ACCESS" == "Y" ]]; then
      ENABLE_PUBLIC_ACCESS="true"
      echo "✅ Public access enabled"
      echo "  • Services will be accessible from internet"
      echo "  • Uses public domains (e.g., chat.mycompany.com)"
      echo "  • Let's Encrypt will provide automatic TLS certificates"
      echo ""
      
      # Ask for email for Let's Encrypt
      echo -e "${GREEN}📧 Certificate Email Configuration${NC}"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      read -p "Email for Let's Encrypt certificates [default: admin@example.com]: " CERT_EMAIL
      CERT_EMAIL=${CERT_EMAIL:-admin@example.com}
      echo "✅ Certificate email: $CERT_EMAIL"
      echo ""
    else
      ENABLE_PUBLIC_ACCESS="false"
      echo "❌ Public access disabled"
      echo ""
      # Set default email for LAN mode
      CERT_EMAIL="admin@example.com"
    fi
  fi
  
  # Set legacy ACCESS_MODE for backward compatibility
  if [[ "$ENABLE_PUBLIC_ACCESS" == "true" ]]; then
    ACCESS_MODE="public"
  else
    ACCESS_MODE="lan"
  fi
  
  echo -e "${GREEN}📋 Access Configuration Summary:${NC}"
  echo "  • LAN Access (.local domains): $([ "$ENABLE_LAN_ACCESS" = "true" ] && echo "✅ Enabled" || echo "❌ Disabled")"
  echo "  • Public Access (internet domains): $([ "$ENABLE_PUBLIC_ACCESS" = "true" ] && echo "✅ Enabled" || echo "❌ Disabled")"
  if [[ "$ENABLE_PUBLIC_ACCESS" == "true" ]]; then
    echo "  • Let's Encrypt email: $CERT_EMAIL"
  fi
  echo ""
}
















# Main function to configure all components (interactive mode)
configure_all_components() {
  echo ""
  echo -e "${GREEN}🧩 Component Configuration${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Let's configure each component of your Lair platform:"
  echo ""
  
  # Configure each component individually using standalone component files
  # Use relative paths since we're in the lib/ directory
  local lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  source "${lib_dir}/components/openwebui.sh"
  source "${lib_dir}/components/ollama.sh"
  source "${lib_dir}/components/n8n.sh"
  source "${lib_dir}/components/comfyui.sh"
  source "${lib_dir}/components/minio.sh"
  source "${lib_dir}/components/postgresql.sh"
  source "${lib_dir}/components/redis.sh"
  source "${lib_dir}/components/velero.sh"
  
  configure_openwebui
  configure_ollama
  configure_n8n
  configure_comfyui
  configure_minio
  configure_postgresql
  configure_redis
  configure_velero
  
  # Show resource allocation summary
  show_resource_summary
}

# Main function for non-interactive mode (config files)
configure_all_components_non_interactive() {
  echo ""
  echo -e "${GREEN}🧩 Component Configuration${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Configuration loaded from file. Here's your setup:"
  echo ""
  
  # Configure each component in non-interactive mode using standalone component files
  # Use relative paths since we're in the lib/ directory
  local lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  source "${lib_dir}/components/openwebui.sh"
  source "${lib_dir}/components/ollama.sh"
  source "${lib_dir}/components/n8n.sh"
  source "${lib_dir}/components/comfyui.sh"
  source "${lib_dir}/components/minio.sh"
  source "${lib_dir}/components/postgresql.sh"
  source "${lib_dir}/components/redis.sh"
  source "${lib_dir}/components/velero.sh"
  
  configure_openwebui_non_interactive
  configure_ollama_non_interactive
  configure_n8n_non_interactive
  configure_comfyui_non_interactive
  configure_minio_non_interactive
  configure_postgresql_non_interactive
  configure_redis_non_interactive
  configure_velero_non_interactive
  
  show_resource_summary
}

# Show resource allocation summary
show_resource_summary() {
  echo ""
  echo -e "${GREEN}📊 Resource Allocation Summary${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Automatic resource allocation based on detected system resources:"
  echo "   • Total Available: $K8S_CPU CPU cores, $((K8S_MEMORY_MB/1024)) GB RAM"
  echo "   • OpenWebUI: $(echo "scale=1; $CPU_OPENWEBUI/1000" | bc) CPU, $((MEM_OPENWEBUI/1024)) GB RAM"
  echo "   • Ollama: $(echo "scale=1; $CPU_OLLAMA/1000" | bc) CPU, $((MEM_OLLAMA/1024)) GB RAM"
  echo "   • N8N: $(echo "scale=1; $CPU_N8N/1000" | bc) CPU, $((MEM_N8N/1024)) GB RAM"
  echo "   • N8N Workers (x${N8N_WORKER_REPLICAS}): $(echo "scale=1; $CPU_N8N_WORKER * $N8N_WORKER_REPLICAS/1000" | bc) CPU, $(echo "scale=1; $MEM_N8N_WORKER * $N8N_WORKER_REPLICAS/1024" | bc) GB RAM"
  echo "   • PostgreSQL: $(echo "scale=1; $CPU_POSTGRES/1000" | bc) CPU, $((MEM_POSTGRES/1024)) GB RAM"
  echo "   • Redis: $(echo "scale=1; $CPU_REDIS/1000" | bc) CPU, $((MEM_REDIS/1024)) GB RAM"
  if [[ "$MINIO_ENABLED" == true ]]; then
    echo "   • MinIO: $(echo "scale=1; $CPU_MINIO/1000" | bc) CPU, $((MEM_MINIO/1024)) GB RAM"
  fi
  if [[ "$COMFYUI_ENABLED" == true ]]; then
    echo "   • ComfyUI: $(echo "scale=1; $CPU_COMFYUI/1000" | bc) CPU, $((MEM_COMFYUI/1024)) GB RAM"
  fi
  echo "✅ Resources automatically allocated using optimized percentages"
}

# Non-interactive version for access mode configuration
configure_access_mode_and_email_non_interactive() {
  echo ""
  echo -e "${GREEN}🌐 Access Mode & Certificate Configuration${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  echo -e "${GREEN}📋 Access Configuration Summary:${NC}"
  echo "  • LAN Access (.local domains): $([ "$ENABLE_LAN_ACCESS" = "true" ] && echo "✅ Enabled" || echo "❌ Disabled")"
  if [[ "$ENABLE_LAN_ACCESS" == "true" ]]; then
    echo "  • LAN TLS (HTTPS): $([ "$ENABLE_LAN_TLS" = "true" ] && echo "✅ Enabled" || echo "❌ Disabled")"
    
    # Detect system hostname for LAN domain generation (only if LAN access is enabled)
    detect_system_hostname_non_interactive
    echo ""
  fi
  echo "  • Public Access (internet domains): $([ "$ENABLE_PUBLIC_ACCESS" = "true" ] && echo "✅ Enabled" || echo "❌ Disabled")"
  
  if [[ "$ENABLE_PUBLIC_ACCESS" == "true" ]]; then
    echo "  • Let's Encrypt email: $CERT_EMAIL"
  fi
  
  # Set legacy ACCESS_MODE for backward compatibility
  if [[ "$ENABLE_PUBLIC_ACCESS" == "true" ]]; then
    ACCESS_MODE="public"
  else
    ACCESS_MODE="lan"
  fi
  
  echo "  • Legacy access mode: $ACCESS_MODE"
}

 