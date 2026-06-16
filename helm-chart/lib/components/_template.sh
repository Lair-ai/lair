#!/bin/bash

# ============================================================================
# _TEMPLATE.SH - Component Template for New Components
# ============================================================================
# 
# This template shows how to create a new standalone component.
# Copy this file and rename it to your component name (e.g., grafana.sh)
# 
# To add a new component:
# 1. Copy this file to components/yourcomponent.sh
# 2. Update the component name and configuration
# 3. Add the source and function call to component-config.sh
# 4. Add the domain configuration to the YAML template
# 
# ============================================================================

# Configure YOURCOMPONENT component (interactive mode)
configure_yourcomponent() {
  echo ""
  echo -e "${GREEN}🔧 YourComponent Configuration${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "YourComponent provides [description of what it does] (optional/always enabled)"
  echo ""
  
  # Ask if user wants to enable this component (if it's optional)
  read -p "🔧 Enable YourComponent? (y/n) [default: y]: " ENABLE_YOURCOMPONENT
  ENABLE_YOURCOMPONENT=${ENABLE_YOURCOMPONENT:-y}
  
  if [[ "$ENABLE_YOURCOMPONENT" == "y" || "$ENABLE_YOURCOMPONENT" == "Y" ]]; then
    echo "✅ YourComponent enabled"
    
    # LAN domain configuration (uses new hostname + subdomain logic)
    if [[ "$ENABLE_LAN_ACCESS" == "true" ]]; then
      echo -e "${BLUE}🏠 LAN Domain Configuration${NC}"
      read -p "🌐 YourComponent LAN subdomain [default: yourcomponent] (leave empty for internal-only access): " YOURCOMPONENT_SUBDOMAIN_LAN
      YOURCOMPONENT_SUBDOMAIN_LAN=${YOURCOMPONENT_SUBDOMAIN_LAN:-yourcomponent}
      
      if [ -n "$YOURCOMPONENT_SUBDOMAIN_LAN" ]; then
        YOURCOMPONENT_DOMAIN_LAN="$YOURCOMPONENT_SUBDOMAIN_LAN.$SYSTEM_HOSTNAME.local"
        echo "✅ YourComponent LAN will be accessible at: https://$YOURCOMPONENT_DOMAIN_LAN"
      else
        YOURCOMPONENT_DOMAIN_LAN=""
        echo "ℹ️  YourComponent LAN: Internal access only via lair-yourcomponent.lair.svc.cluster.local:80"
      fi
      echo ""
    fi
    
    # Public domain configuration
    if [[ "$ENABLE_PUBLIC_ACCESS" == "true" ]]; then
      echo -e "${BLUE}🌍 Public Domain Configuration${NC}"
      read -p "🌐 YourComponent public domain [default: yourcomponent.example.com]: " YOURCOMPONENT_DOMAIN_PUBLIC
      YOURCOMPONENT_DOMAIN_PUBLIC=${YOURCOMPONENT_DOMAIN_PUBLIC:-yourcomponent.example.com}
      echo "✅ Public Domain: $YOURCOMPONENT_DOMAIN_PUBLIC"
      echo ""
    fi
    
    # Set legacy domain for backward compatibility
    if [[ "$ENABLE_PUBLIC_ACCESS" == "true" ]]; then
      YOURCOMPONENT_DOMAIN="$YOURCOMPONENT_DOMAIN_PUBLIC"
    else
      YOURCOMPONENT_DOMAIN="$YOURCOMPONENT_DOMAIN_LAN"
    fi
    
    # Storage configuration (use cross-component helper function)
    ask_storage_gb "YourComponent data" "10" "YOURCOMPONENT_STORAGE_SIZE"
    echo "✅ Storage: $YOURCOMPONENT_STORAGE_SIZE"
    
    # Component-specific configuration
    echo ""
    echo -e "${BLUE}⚙️  YourComponent Specific Configuration${NC}"
    read -p "🔧 Custom setting [default: defaultvalue]: " YOURCOMPONENT_CUSTOM_SETTING
    YOURCOMPONENT_CUSTOM_SETTING=${YOURCOMPONENT_CUSTOM_SETTING:-defaultvalue}
    echo "✅ Custom setting: $YOURCOMPONENT_CUSTOM_SETTING"
    
    YOURCOMPONENT_ENABLED=true
    echo "✅ YourComponent configuration completed"
  else
    echo "❌ YourComponent disabled"
    YOURCOMPONENT_ENABLED=false
    YOURCOMPONENT_DOMAIN=""
  fi
}

# Configure YourComponent component (non-interactive mode for config files)
configure_yourcomponent_non_interactive() {
  echo ""
  echo -e "${GREEN}🔧 YourComponent Configuration${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  if [[ "$YOURCOMPONENT_ENABLED" == true ]]; then
    echo "🔧 YourComponent: Enabled"
    
    # Show configured domains
    if [[ "$ENABLE_LAN_ACCESS" == "true" && -n "$YOURCOMPONENT_DOMAIN_LAN" ]]; then
      echo "   🏠 LAN Domain: $YOURCOMPONENT_DOMAIN_LAN"
    fi
    if [[ "$ENABLE_PUBLIC_ACCESS" == "true" && -n "$YOURCOMPONENT_DOMAIN_PUBLIC" ]]; then
      echo "   🌍 Public Domain: $YOURCOMPONENT_DOMAIN_PUBLIC"
    fi
    
    echo "   💾 Storage: ${YOURCOMPONENT_STORAGE_GB}GB"
    echo "   ⚙️  Custom setting: $YOURCOMPONENT_CUSTOM_SETTING"
  else
    echo "🔧 YourComponent: Disabled"
  fi
  
  echo "✅ YourComponent configuration loaded"
}

# Component-specific helper functions (if needed)
configure_yourcomponent_advanced_settings() {
  echo "Configure advanced settings for YourComponent..."
  # Add any complex configuration logic here
} 