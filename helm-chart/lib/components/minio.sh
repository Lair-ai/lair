#!/bin/bash

# ============================================================================
# MINIO.SH - MinIO Component Configuration
# ============================================================================

# Configure MinIO component (interactive mode)
configure_minio() {
  echo ""
  echo -e "${GREEN}🗄️  MinIO Configuration${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "MinIO provides S3-compatible object storage for file management"
  echo ""
  
  # Ask if user wants to enable MinIO
  read -p "🗄️  Enable MinIO object storage? (y/n) [default: y]: " ENABLE_MINIO
  ENABLE_MINIO=${ENABLE_MINIO:-y}
  
  if [[ "$ENABLE_MINIO" == "y" || "$ENABLE_MINIO" == "Y" ]]; then
    echo "✅ MinIO enabled"
    echo ""
    echo -e "${BLUE}📦 MinIO Integration${NC}"
    echo "When MinIO is enabled, OpenWebUI will automatically use it for file storage:"
    echo "  • Document uploads and RAG files will be stored in MinIO"
    echo "  • Automatic S3 bucket creation: 'openwebui-storage'"
    echo "  • Scalable object storage instead of local filesystem"
    echo "  • Better performance for large files and concurrent access"
    echo ""
    
    # Domain configuration
    echo ""
    echo -e "${BLUE}🌐 MinIO Domain Configuration${NC}"
    echo "MinIO can be accessed externally or internally only:"
    echo "  • External: Specify your real domain for web console HTTPS access"
    echo "  • Internal: Leave empty for Kubernetes DNS access only (recommended)"
    echo "  • Internal Console: lair-minio.lair.svc.cluster.local:80"
    echo "  • Internal S3 API: lair-minio.lair.svc.cluster.local:9000"
    echo ""
    
    # LAN domain configuration
    if [[ "$ENABLE_LAN_ACCESS" == "true" ]]; then
      echo -e "${BLUE}🏠 LAN Domain Configuration${NC}"
      read -p "🌐 MinIO LAN subdomain [default: storage] (leave empty for internal-only access): " MINIO_SUBDOMAIN_LAN
      MINIO_SUBDOMAIN_LAN=${MINIO_SUBDOMAIN_LAN:-storage}
      
      if [ -n "$MINIO_SUBDOMAIN_LAN" ]; then
        MINIO_DOMAIN_LAN="$MINIO_SUBDOMAIN_LAN.$SYSTEM_HOSTNAME.local"
        echo "✅ MinIO LAN will be accessible at: https://$MINIO_DOMAIN_LAN"
      else
        MINIO_DOMAIN_LAN=""
        echo "ℹ️  MinIO LAN: Internal access only via lair-minio.lair.svc.cluster.local"
      fi
      echo ""
    fi
    
    # Public domain configuration
    if [[ "$ENABLE_PUBLIC_ACCESS" == "true" ]]; then
      echo -e "${BLUE}🌍 Public Domain Configuration${NC}"
      read -p "🌐 MinIO public domain (leave empty for internal-only access): " MINIO_DOMAIN_PUBLIC
      MINIO_DOMAIN_PUBLIC=${MINIO_DOMAIN_PUBLIC:-}
      
      if [ -n "$MINIO_DOMAIN_PUBLIC" ]; then
        echo "✅ MinIO public will be accessible at: https://$MINIO_DOMAIN_PUBLIC"
      else
        echo "ℹ️  MinIO public: Internal access only via lair-minio.lair.svc.cluster.local"
      fi
      echo ""
    fi
    
    # Set legacy domain for backward compatibility
    if [[ "$ENABLE_PUBLIC_ACCESS" == "true" && -n "$MINIO_DOMAIN_PUBLIC" ]]; then
      MINIO_DOMAIN="$MINIO_DOMAIN_PUBLIC"
    elif [[ "$ENABLE_LAN_ACCESS" == "true" && -n "$MINIO_DOMAIN_LAN" ]]; then
      MINIO_DOMAIN="$MINIO_DOMAIN_LAN"
    else
      MINIO_DOMAIN=""
    fi
    
    # Storage configuration
    ask_storage_gb "MinIO object storage" "20" "MINIO_STORAGE_SIZE"
    echo "✅ Storage: $MINIO_STORAGE_SIZE"
    
    # Root credentials configuration
    echo ""
    echo -e "${BLUE}🔑 MinIO Root User Configuration${NC}"
    echo "⚠️  Root credentials provide complete administrative AND S3 API access"
    echo "⚠️  These same credentials are used for console access and S3 API operations"
    echo "⚠️  NEVER use default credentials in production environments"
    echo ""
    read -p "🔑 Root username [default: minioadmin]: " MINIO_ROOT_USER
    MINIO_ROOT_USER=${MINIO_ROOT_USER:-minioadmin}
    read -p "🔑 Root password [default: minioadmin]: " MINIO_ROOT_PASSWORD
    MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD:-minioadmin}
    
    # Show security warning for default credentials
    if [[ "$MINIO_ROOT_USER" == "minioadmin" && "$MINIO_ROOT_PASSWORD" == "minioadmin" ]]; then
      echo -e "${RED}⚠️  WARNING: Using default root credentials!${NC}"
      echo -e "${RED}   This is NOT recommended for production environments${NC}"
      echo -e "${RED}   Please use strong, unique credentials for security${NC}"
    else
      echo "✅ Custom root credentials configured"
    fi
    
    MINIO_ENABLED=true
    echo "✅ MinIO configuration completed"
  else
    echo "❌ MinIO disabled"
    MINIO_ENABLED=false
    MINIO_DOMAIN=""
    MINIO_DOMAIN_LAN=""
    MINIO_DOMAIN_PUBLIC=""
    MINIO_STORAGE_SIZE=""
    MINIO_STORAGE_GB=0
  fi
}

# Configure MinIO component (non-interactive mode for config files)
configure_minio_non_interactive() {
  echo ""
  echo -e "${GREEN}🗄️  MinIO Configuration${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  if [ "$MINIO_ENABLED" = "true" ] || [ "$ENABLE_MINIO" = "y" ]; then
    echo "🗄️  MinIO: Enabled"
    echo "   📦 OpenWebUI Integration: Automatic S3 storage backend"
    echo "   📦 Bucket: openwebui-storage (auto-created)"
    
    # Show configured domains
    if [[ "$ENABLE_LAN_ACCESS" == "true" ]]; then
      if [ -n "$MINIO_DOMAIN_LAN" ]; then
        echo "   🏠 LAN Domain: $MINIO_DOMAIN_LAN"
      else
        echo "   🏠 LAN Access: Internal only"
      fi
    fi
    if [[ "$ENABLE_PUBLIC_ACCESS" == "true" ]]; then
      if [ -n "$MINIO_DOMAIN_PUBLIC" ]; then
        echo "   🌍 Public Domain: $MINIO_DOMAIN_PUBLIC"
      else
        echo "   🌍 Public Access: Internal only"
      fi
    fi
    
    echo "   💾 Storage: ${MINIO_STORAGE_GB}GB"
    echo "   🔑 Root User: $MINIO_ROOT_USER"
    echo "   🔑 S3 API Credentials: $MINIO_ACCESS_KEY / $MINIO_SECRET_KEY"
    
    # Show security warning for default root credentials
    if [[ "$MINIO_ROOT_USER" == "minioadmin" && "$MINIO_ROOT_PASSWORD" == "minioadmin" ]]; then
      echo -e "${RED}   ⚠️  WARNING: Using default root credentials (not recommended for production)${NC}"
    fi
    MINIO_ENABLED=true
  else
    echo "❌ MinIO: Disabled"
    MINIO_ENABLED=false
    MINIO_STORAGE_SIZE=""
    MINIO_STORAGE_GB=0
  fi
  
  echo "✅ MinIO configuration completed"
} 
