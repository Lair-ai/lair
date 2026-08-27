#!/bin/bash

# ============================================================================
# N8N.SH - N8N Component Configuration
# ============================================================================

# Configure N8N component (interactive mode)
configure_n8n() {
  echo ""
  echo -e "${GREEN}🔗 N8N Configuration${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "N8N is the workflow automation and integration platform (always enabled)"
  echo ""
  
  # LAN domain configuration
  if [[ "$ENABLE_LAN_ACCESS" == "true" ]]; then
    echo -e "${BLUE}🏠 LAN Domain Configuration${NC}"
    read -p "🌐 N8N LAN subdomain [default: n8n]: " N8N_SUBDOMAIN_LAN
    N8N_SUBDOMAIN_LAN=${N8N_SUBDOMAIN_LAN:-n8n}
    N8N_DOMAIN_LAN="$N8N_SUBDOMAIN_LAN.$SYSTEM_HOSTNAME.local"
    echo "✅ LAN Domain: $N8N_DOMAIN_LAN"
    echo ""
  fi
  
  # Public domain configuration
  if [[ "$ENABLE_PUBLIC_ACCESS" == "true" ]]; then
    echo -e "${BLUE}🌍 Public Domain Configuration${NC}"
    read -p "🌐 N8N public domain [default: n8n.example.com]: " N8N_DOMAIN_PUBLIC
    N8N_DOMAIN_PUBLIC=${N8N_DOMAIN_PUBLIC:-n8n.example.com}
    echo "✅ Public Domain: $N8N_DOMAIN_PUBLIC"
    echo ""
  fi
  
  # Set legacy domain for backward compatibility
  if [[ "$ENABLE_PUBLIC_ACCESS" == "true" ]]; then
    N8N_DOMAIN="$N8N_DOMAIN_PUBLIC"
  else
    N8N_DOMAIN="$N8N_DOMAIN_LAN"
  fi
  
  # Storage configuration
  ask_storage_gb "N8N workflows" "10" "N8N_STORAGE_SIZE"
  echo "✅ Storage: $N8N_STORAGE_SIZE"
  
  # Encryption key configuration
  echo ""
  echo -e "${BLUE}🔑 N8N Encryption Key Configuration${NC}"
  configure_n8n_key
  
  # Admin user configuration - COMMENTED OUT: Admin functionality doesn't work properly
  # echo ""
  # echo -e "${BLUE}👤 N8N Admin User Configuration${NC}"
  # configure_n8n_admin_user
  
  # SMTP configuration
  echo ""
  echo -e "${BLUE}📧 N8N SMTP Configuration${NC}"
  configure_n8n_smtp
  
  # Show security information for local installations
  if [[ "$ENABLE_LAN_ACCESS" == "true" ]]; then
    echo ""
    echo -e "${BLUE}🔒 N8N Security Configuration for Local Installation${NC}"
    echo "   ✅ N8N_SECURE_COOKIE automatically set to 'false' for .local domains"
    echo "   ⚠️  This is required for N8N to work properly with local HTTPS certificates"
  fi
  
  echo "✅ N8N configuration completed"
}

# Configure N8N component (non-interactive mode for config files)
configure_n8n_non_interactive() {
  echo ""
  echo -e "${GREEN}🔗 N8N Configuration${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "🔗 N8N: Always enabled"
  
  # Show configured domains
  if [[ "$ENABLE_LAN_ACCESS" == "true" ]]; then
    echo "   🏠 LAN Domain: $N8N_DOMAIN_LAN"
  fi
  if [[ "$ENABLE_PUBLIC_ACCESS" == "true" ]]; then
    echo "   🌍 Public Domain: $N8N_DOMAIN_PUBLIC"
  fi
  
  echo "   💾 Storage: ${N8N_STORAGE_GB}GB"
  echo "   🔑 Encryption key: $([ -n "$N8N_KEY" ] && echo "Configured" || echo "Auto-generated")"
  # echo "   👤 Admin User: $([ -n "$N8N_ADMIN_EMAIL" ] && echo "$N8N_ADMIN_EMAIL" || echo "admin@n8n.local")"
  echo "   📧 SMTP: $([ "$ENABLE_N8N_SMTP" = "y" ] && echo "Enabled" || echo "Disabled")"
  
  # N8N encryption key
  if [ -n "$N8N_KEY" ]; then
    echo "   🔑 Using encryption key from config file"
  else
    configure_n8n_key
  fi
  
  # N8N admin user configuration - COMMENTED OUT: Admin functionality doesn't work properly
  # if [ -n "$N8N_ADMIN_EMAIL" ]; then
  #   echo "   👤 Using admin user from config file: $N8N_ADMIN_EMAIL"
  #   # Show security warning for default admin credentials
  #   if [[ "$N8N_ADMIN_EMAIL" == "admin@n8n.local" && "$N8N_ADMIN_PASSWORD" == "n8n123" ]]; then
  #     echo -e "   ${RED}⚠️  WARNING: Using default admin credentials (not recommended for production)${NC}"
  #   fi
  # else
  #   # Set default admin user if not configured
  #   N8N_ADMIN_EMAIL="admin@n8n.local"
  #   N8N_ADMIN_PASSWORD="n8n123"
  #   N8N_ADMIN_FIRST_NAME="Admin"
  #   N8N_ADMIN_LAST_NAME="User"
  #   echo "   👤 Using default admin user: $N8N_ADMIN_EMAIL"
  #   echo -e "   ${RED}⚠️  WARNING: Using default admin credentials (not recommended for production)${NC}"
  # fi
  
  # N8N SMTP configuration
  if [[ "$ENABLE_N8N_SMTP" == "y" || "$ENABLE_N8N_SMTP" == "Y" ]]; then
    echo "   📧 SMTP Configuration:"
    echo "      📧 Host: $N8N_SMTP_HOST:$N8N_SMTP_PORT"
    echo "      👤 User: $N8N_SMTP_USER"
    echo "      📤 Sender: $N8N_SMTP_SENDER"
    echo "      🔒 SSL: $N8N_SMTP_SSL, STARTTLS: $N8N_SMTP_STARTTLS"
  else
    echo "   ⚠️  SMTP disabled - User management features will be limited"
  fi
  
  # Show security information for local installations
  if [[ "$ENABLE_LAN_ACCESS" == "true" ]]; then
    echo "   🔒 Security: N8N_SECURE_COOKIE automatically set to 'false' for .local domains"
  fi
  
  echo "✅ N8N configuration completed"
}

# Configure N8N encryption key
configure_n8n_key() {
  # 1. Check for existing key in the local file
  if [ -f "$N8N_KEY_FILE" ]; then
    EXISTING_N8N_KEY=$(cat "$N8N_KEY_FILE")
    if [ -n "$EXISTING_N8N_KEY" ]; then
      N8N_KEY="$EXISTING_N8N_KEY"
      echo "   🔑 Found and loaded existing local N8N encryption key"
      return
    fi
  fi

  # 2. If cluster is accessible, try to fetch from existing Secret in the namespace
  if [ "$K8S_CLUSTER_ACCESSIBLE" = "true" ] && [ -n "$KUBECTL_CMD" ]; then
    SECRET_KEY_B64=$($KUBECTL_CMD get secret n8n-encryption-secret -n "$NAMESPACE" -o jsonpath='{.data.encryptionKey}' 2>/dev/null)
    if [ -n "$SECRET_KEY_B64" ]; then
      if command -v base64 &>/dev/null; then
        EXISTING_N8N_KEY=$(echo "$SECRET_KEY_B64" | base64 --decode 2>/dev/null || echo "$SECRET_KEY_B64" | base64 -d 2>/dev/null || echo "$SECRET_KEY_B64" | base64 -D 2>/dev/null)
        if [ -n "$EXISTING_N8N_KEY" ]; then
          N8N_KEY="$EXISTING_N8N_KEY"
          echo "$N8N_KEY" > "$N8N_KEY_FILE"
          echo "   🔑 Retrieved existing N8N encryption key from Secret and saved to $N8N_KEY_FILE"
          return
        fi
      fi
    fi
  fi

  # 3. Otherwise, generate a new key. Keep failures explicit because setup.sh
  # runs with errexit enabled and a failed command substitution would be silent.
  N8N_KEY=""
  if command -v openssl &>/dev/null; then
    N8N_KEY=$(openssl rand -hex 16 2>/dev/null) || N8N_KEY=""
  fi
  if [ -z "$N8N_KEY" ]; then
    N8N_KEY=$(tr -dc 'a-zA-Z0-9' </dev/urandom | head -c 32) || N8N_KEY=""
  fi
  if [ -z "$N8N_KEY" ]; then
    echo -e "${RED}❌ Unable to generate the N8N encryption key${NC}" >&2
    return 1
  fi
  echo "   ✅ Generated new N8N encryption key automatically"
  
  # Save key locally for consistency
  if ! printf '%s\n' "$N8N_KEY" > "$N8N_KEY_FILE"; then
    echo -e "${RED}❌ Unable to save the N8N encryption key to $N8N_KEY_FILE${NC}" >&2
    return 1
  fi
}

# Configure N8N SMTP settings
configure_n8n_smtp() {
  echo "📧 SMTP is required for N8N user management features:"
  echo "  • User invitations"
  echo "  • Password reset emails"
  echo "  • Account notifications"
  echo ""
  
  read -p "📧 Enable SMTP for N8N user management? (y/n) [default: n]: " ENABLE_N8N_SMTP
  ENABLE_N8N_SMTP=${ENABLE_N8N_SMTP:-n}
  
  if [[ "$ENABLE_N8N_SMTP" == "y" || "$ENABLE_N8N_SMTP" == "Y" ]]; then
    echo ""
    echo "📧 SMTP Server Configuration:"
    read -p "   📧 SMTP Host (e.g., smtp.gmail.com): " N8N_SMTP_HOST
    read -p "   📧 SMTP Port [default: 587]: " N8N_SMTP_PORT
    N8N_SMTP_PORT=${N8N_SMTP_PORT:-587}
    
    read -p "   👤 SMTP Username/Email: " N8N_SMTP_USER
    read -s -p "   🔒 SMTP Password (hidden): " N8N_SMTP_PASS
    echo ""
    
    read -p "   📤 Sender Email [default: $N8N_SMTP_USER]: " N8N_SMTP_SENDER
    N8N_SMTP_SENDER=${N8N_SMTP_SENDER:-$N8N_SMTP_USER}
    
    echo ""
    echo "🔒 Security Settings:"
    read -p "   🔒 Use SSL/TLS? (y/n) [default: y]: " N8N_SMTP_SSL
    N8N_SMTP_SSL=${N8N_SMTP_SSL:-y}
    
    read -p "   🔒 Use STARTTLS? (y/n) [default: y]: " N8N_SMTP_STARTTLS
    N8N_SMTP_STARTTLS=${N8N_SMTP_STARTTLS:-y}
    
    echo ""
    echo "✅ SMTP Configuration Summary:"
    echo "   📧 Host: $N8N_SMTP_HOST:$N8N_SMTP_PORT"
    echo "   👤 User: $N8N_SMTP_USER"
    echo "   📤 Sender: $N8N_SMTP_SENDER"
    echo "   🔒 SSL: $N8N_SMTP_SSL, STARTTLS: $N8N_SMTP_STARTTLS"
  else
    echo "⚠️  SMTP disabled - N8N user management features will be limited"
    ENABLE_N8N_SMTP="n"
  fi
}

# Configure N8N admin user
configure_n8n_admin_user() {
  echo "👤 Admin user provides full access to N8N workflows and automation:"
  echo "  • Complete workflow management"
  echo "  • User management and permissions"
  echo "  • System configuration access"
  echo ""
  echo "⚠️  NEVER use default credentials in production environments"
  echo ""
  
  read -p "👤 Admin email [default: admin@n8n.local]: " N8N_ADMIN_EMAIL
  N8N_ADMIN_EMAIL=${N8N_ADMIN_EMAIL:-admin@n8n.local}
  
  read -s -p "🔑 Admin password [default: n8n123] (hidden): " N8N_ADMIN_PASSWORD
  echo ""
  N8N_ADMIN_PASSWORD=${N8N_ADMIN_PASSWORD:-n8n123}
  
  read -p "👤 Admin first name [default: Admin]: " N8N_ADMIN_FIRST_NAME
  N8N_ADMIN_FIRST_NAME=${N8N_ADMIN_FIRST_NAME:-Admin}
  
  read -p "👤 Admin last name [default: User]: " N8N_ADMIN_LAST_NAME
  N8N_ADMIN_LAST_NAME=${N8N_ADMIN_LAST_NAME:-User}
  
  echo ""
  echo "✅ Admin User Configuration Summary:"
  echo "   👤 Email: $N8N_ADMIN_EMAIL"
  echo "   👤 Name: $N8N_ADMIN_FIRST_NAME $N8N_ADMIN_LAST_NAME"
  
  # Show security warning for default admin credentials
  if [[ "$N8N_ADMIN_EMAIL" == "admin@n8n.local" && "$N8N_ADMIN_PASSWORD" == "n8n123" ]]; then
    echo -e "   ${RED}⚠️  WARNING: Using default credentials (not recommended for production)${NC}"
  fi
}
