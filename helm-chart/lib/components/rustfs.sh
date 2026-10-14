#!/bin/bash

# ============================================================================
# RUSTFS.SH - RustFS Component Configuration
# ============================================================================

# Configure RustFS component (interactive mode)
configure_rustfs() {
  echo ""
  echo -e "${GREEN}🗄️  RustFS Configuration${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "RustFS provides S3-compatible object storage for file management"
  echo ""
  
  # Ask if user wants to enable RustFS
  read -p "🗄️  Enable RustFS object storage? (y/n) [default: y]: " ENABLE_RUSTFS
  ENABLE_RUSTFS=${ENABLE_RUSTFS:-y}
  
  if [[ "$ENABLE_RUSTFS" == "y" || "$ENABLE_RUSTFS" == "Y" ]]; then
    echo "✅ RustFS enabled"
    echo ""
    echo -e "${BLUE}📦 RustFS Integration${NC}"
    echo "When RustFS is enabled, OpenWebUI will automatically use it for file storage:"
    echo "  • Document uploads and RAG files will be stored in RustFS"
    echo "  • Automatic S3 bucket creation: 'openwebui-storage'"
    echo "  • Scalable object storage instead of local filesystem"
    echo "  • Better performance for large files and concurrent access"
    echo ""
    
    # Domain configuration
    echo ""
    echo -e "${BLUE}🌐 RustFS Domain Configuration${NC}"
    echo "RustFS can be accessed externally or internally only:"
    echo "  • External: Specify your real domain for web console HTTPS access"
    echo "  • Internal: Leave empty for Kubernetes DNS access only (recommended)"
    echo "  • Internal Console: lair-rustfs.lair.svc.cluster.local:80"
    echo "  • Internal S3 API: lair-rustfs.lair.svc.cluster.local:9000"
    echo ""
    
    # LAN domain configuration
    if [[ "$ENABLE_LAN_ACCESS" == "true" ]]; then
      echo -e "${BLUE}🏠 LAN Domain Configuration${NC}"
      read -p "🌐 RustFS LAN subdomain [default: storage] (leave empty for internal-only access): " RUSTFS_SUBDOMAIN_LAN
      RUSTFS_SUBDOMAIN_LAN=${RUSTFS_SUBDOMAIN_LAN:-storage}
      
      if [ -n "$RUSTFS_SUBDOMAIN_LAN" ]; then
        RUSTFS_DOMAIN_LAN="$RUSTFS_SUBDOMAIN_LAN.$SYSTEM_HOSTNAME.local"
        echo "✅ RustFS LAN will be accessible at: https://$RUSTFS_DOMAIN_LAN"
      else
        RUSTFS_DOMAIN_LAN=""
        echo "ℹ️  RustFS LAN: Internal access only via lair-rustfs.lair.svc.cluster.local"
      fi
      echo ""
    fi
    
    # Public domain configuration
    if [[ "$ENABLE_PUBLIC_ACCESS" == "true" ]]; then
      echo -e "${BLUE}🌍 Public Domain Configuration${NC}"
      read -p "🌐 RustFS public domain (leave empty for internal-only access): " RUSTFS_DOMAIN_PUBLIC
      RUSTFS_DOMAIN_PUBLIC=${RUSTFS_DOMAIN_PUBLIC:-}
      
      if [ -n "$RUSTFS_DOMAIN_PUBLIC" ]; then
        echo "✅ RustFS public will be accessible at: https://$RUSTFS_DOMAIN_PUBLIC"
      else
        echo "ℹ️  RustFS public: Internal access only via lair-rustfs.lair.svc.cluster.local"
      fi
      echo ""
    fi
    
    # Set legacy domain for backward compatibility
    if [[ "$ENABLE_PUBLIC_ACCESS" == "true" && -n "$RUSTFS_DOMAIN_PUBLIC" ]]; then
      RUSTFS_DOMAIN="$RUSTFS_DOMAIN_PUBLIC"
    elif [[ "$ENABLE_LAN_ACCESS" == "true" && -n "$RUSTFS_DOMAIN_LAN" ]]; then
      RUSTFS_DOMAIN="$RUSTFS_DOMAIN_LAN"
    else
      RUSTFS_DOMAIN=""
    fi
    
    # Storage configuration
    ask_storage_gb "RustFS object storage" "20" "RUSTFS_STORAGE_SIZE"
    echo "✅ Storage: $RUSTFS_STORAGE_SIZE"
    
    # Root credentials configuration
    echo ""
    echo -e "${BLUE}🔑 RustFS Root User Configuration${NC}"
    echo "⚠️  Root credentials provide complete administrative AND S3 API access"
    echo "⚠️  These same credentials are used for console access and S3 API operations"
    echo "⚠️  NEVER use default credentials in production environments"
    echo ""
    read -p "🔑 Root username [default: rustfsadmin]: " RUSTFS_ROOT_USER
    RUSTFS_ROOT_USER=${RUSTFS_ROOT_USER:-rustfsadmin}
    
    while true; do
      read -s -p "🔑 Root password [default: rustfsadmin] (min 8 chars, hidden): " RUSTFS_ROOT_PASSWORD
      echo ""
      RUSTFS_ROOT_PASSWORD=${RUSTFS_ROOT_PASSWORD:-rustfsadmin}
      
      if [ ${#RUSTFS_ROOT_PASSWORD} -ge 8 ]; then
        break
      else
        echo -e "${RED}❌ Errore: La password deve contenere almeno 8 caratteri. Riprova.${NC}"
      fi
    done
    
    # Show security warning for default credentials
    if [[ "$RUSTFS_ROOT_USER" == "rustfsadmin" && "$RUSTFS_ROOT_PASSWORD" == "rustfsadmin" ]]; then
      echo -e "${RED}⚠️  WARNING: Using default root credentials!${NC}"
      echo -e "${RED}   This is NOT recommended for production environments${NC}"
      echo -e "${RED}   Please use strong, unique credentials for security${NC}"
    else
      echo "✅ Custom root credentials configured"
    fi
    
    RUSTFS_ENABLED=true
    echo "✅ RustFS configuration completed"
  else
    echo "❌ RustFS disabled"
    RUSTFS_ENABLED=false
    RUSTFS_DOMAIN=""
    RUSTFS_DOMAIN_LAN=""
    RUSTFS_DOMAIN_PUBLIC=""
    RUSTFS_STORAGE_SIZE=""
    RUSTFS_STORAGE_GB=0
  fi
}

# Configure RustFS component (non-interactive mode for config files)
configure_rustfs_non_interactive() {
  echo ""
  echo -e "${GREEN}🗄️  RustFS Configuration${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  if [ "$RUSTFS_ENABLED" = "true" ] || [ "$ENABLE_RUSTFS" = "y" ]; then
    echo "🗄️  RustFS: Enabled"
    echo "   📦 OpenWebUI Integration: Automatic S3 storage backend"
    echo "   📦 Bucket: openwebui-storage (auto-created)"
    
    # Show configured domains
    if [[ "$ENABLE_LAN_ACCESS" == "true" ]]; then
      if [ -n "$RUSTFS_DOMAIN_LAN" ]; then
        echo "   🏠 LAN Domain: $RUSTFS_DOMAIN_LAN"
      else
        echo "   🏠 LAN Access: Internal only"
      fi
    fi
    if [[ "$ENABLE_PUBLIC_ACCESS" == "true" ]]; then
      if [ -n "$RUSTFS_DOMAIN_PUBLIC" ]; then
        echo "   🌍 Public Domain: $RUSTFS_DOMAIN_PUBLIC"
      else
        echo "   🌍 Public Access: Internal only"
      fi
    fi
    
    echo "   💾 Storage: ${RUSTFS_STORAGE_GB}GB"
    echo "   🔑 Root User: $RUSTFS_ROOT_USER"
    echo "   🔑 S3 API Credentials: $RUSTFS_ACCESS_KEY / $RUSTFS_SECRET_KEY"
    
    # Show security warning for default root credentials
    if [[ "$RUSTFS_ROOT_USER" == "rustfsadmin" && "$RUSTFS_ROOT_PASSWORD" == "rustfsadmin" ]]; then
      echo -e "${RED}   ⚠️  WARNING: Using default root credentials (not recommended for production)${NC}"
    fi
    RUSTFS_ENABLED=true
  else
    echo "❌ RustFS: Disabled"
    RUSTFS_ENABLED=false
    RUSTFS_STORAGE_SIZE=""
    RUSTFS_STORAGE_GB=0
  fi
  
  echo "✅ RustFS configuration completed"
} 
