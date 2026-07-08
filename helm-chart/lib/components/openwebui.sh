#!/bin/bash

# ============================================================================
# OPENWEBUI.SH - OpenWebUI Component Configuration
# ============================================================================

# Configure OpenWebUI component (interactive mode)
configure_openwebui() {
  echo ""
  echo -e "${GREEN}📱 OpenWebUI Configuration${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "OpenWebUI is the main web interface for AI model interaction (always enabled)"
  echo ""
  
  # LAN domain configuration
  if [[ "$ENABLE_LAN_ACCESS" == "true" ]]; then
    echo -e "${BLUE}🏠 LAN Domain Configuration${NC}"
    read -p "🌐 OpenWebUI LAN subdomain [default: ai]: " OPENWEBUI_SUBDOMAIN_LAN
    OPENWEBUI_SUBDOMAIN_LAN=${OPENWEBUI_SUBDOMAIN_LAN:-ai}
    OPENWEBUI_DOMAIN_LAN="$OPENWEBUI_SUBDOMAIN_LAN.$SYSTEM_HOSTNAME.local"
    echo "✅ LAN Domain: $OPENWEBUI_DOMAIN_LAN"
    echo ""
  fi
  
  # Public domain configuration
  if [[ "$ENABLE_PUBLIC_ACCESS" == "true" ]]; then
    echo -e "${BLUE}🌍 Public Domain Configuration${NC}"
    read -p "🌐 OpenWebUI public domain [default: ai.example.com]: " OPENWEBUI_DOMAIN_PUBLIC
    OPENWEBUI_DOMAIN_PUBLIC=${OPENWEBUI_DOMAIN_PUBLIC:-ai.example.com}
    echo "✅ Public Domain: $OPENWEBUI_DOMAIN_PUBLIC"
    echo ""
  fi
  
  # Set legacy domain for backward compatibility
  if [[ "$ENABLE_PUBLIC_ACCESS" == "true" ]]; then
    OPENWEBUI_DOMAIN="$OPENWEBUI_DOMAIN_PUBLIC"
  else
    OPENWEBUI_DOMAIN="$OPENWEBUI_DOMAIN_LAN"
  fi
  
  # Storage configuration
  ask_storage_gb "OpenWebUI data" "10" "OPENWEBUI_STORAGE_SIZE"
  echo "✅ Storage: $OPENWEBUI_STORAGE_SIZE"
  
  # SSO Configuration
  configure_openwebui_sso
  
  echo "✅ OpenWebUI configuration completed"
}

# Configure OpenWebUI component (non-interactive mode for config files)
configure_openwebui_non_interactive() {
  echo ""
  echo -e "${GREEN}📱 OpenWebUI Configuration${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📱 OpenWebUI: Always enabled"
  
  # Show configured domains
  if [[ "$ENABLE_LAN_ACCESS" == "true" ]]; then
    echo "   🏠 LAN Domain: $OPENWEBUI_DOMAIN_LAN"
  fi
  if [[ "$ENABLE_PUBLIC_ACCESS" == "true" ]]; then
    echo "   🌍 Public Domain: $OPENWEBUI_DOMAIN_PUBLIC"
  fi
  
  echo "   💾 Storage: ${OPENWEBUI_STORAGE_GB}GB"
  
  # Show SSO configuration if enabled
  if [[ "$ENABLE_OPENWEBUI_SSO" == "y" || "$ENABLE_OPENWEBUI_SSO" == "Y" ]]; then
    echo "   🔐 SSO: Enabled ($OPENWEBUI_SSO_PROVIDER)"
    case "$OPENWEBUI_SSO_PROVIDER" in
      "google")
        echo "   👤 Google OAuth configured"
        ;;
      "microsoft")
        echo "   👤 Microsoft OAuth configured"
        ;;
      "github")
        echo "   👤 GitHub OAuth configured"
        ;;
      "oidc")
        echo "   👤 OIDC Provider: $OPENWEBUI_OAUTH_PROVIDER_NAME"
        ;;
      "trusted-header")
        echo "   👤 Trusted Header: $OPENWEBUI_TRUSTED_EMAIL_HEADER"
        ;;
    esac
  else
    echo "   🔐 SSO: Disabled (local authentication)"
  fi
  
  echo "✅ OpenWebUI configuration completed"
}

# Configure OpenWebUI SSO settings
configure_openwebui_sso() {
  echo ""
  echo -e "${BLUE}🔐 OpenWebUI SSO Configuration${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  # Check if public access is enabled - required for OAuth
  if [[ "$ENABLE_PUBLIC_ACCESS" != "true" ]]; then
    echo "⚠️  SSO authentication requires public access to be enabled"
    echo "   OAuth providers need a publicly accessible callback URL"
    echo "   Current configuration: Public access is disabled"
    echo ""
    echo "🔐 SSO disabled - using local authentication only"
    ENABLE_OPENWEBUI_SSO="n"
    return
  fi
  
  echo "SSO allows users to authenticate with external providers:"
  echo "  • Google OAuth2"
  echo "  • Microsoft OAuth2"
  echo "  • GitHub OAuth2"
  echo "  • Generic OIDC providers"
  echo "  • Trusted header authentication (for reverse proxies)"
  echo ""
  echo "ℹ️  OAuth callback URLs will use your public domain: $OPENWEBUI_DOMAIN_PUBLIC"
  echo ""
  
  read -p "🔐 Enable SSO authentication? (y/n) [default: n]: " ENABLE_OPENWEBUI_SSO
  ENABLE_OPENWEBUI_SSO=${ENABLE_OPENWEBUI_SSO:-n}
  
  if [[ "$ENABLE_OPENWEBUI_SSO" == "y" || "$ENABLE_OPENWEBUI_SSO" == "Y" ]]; then
    echo ""
    echo "Available SSO providers:"
    echo "  1) Google OAuth2"
    echo "  2) Microsoft OAuth2"
    echo "  3) GitHub OAuth2"
    echo "  4) Generic OIDC"
    echo "  5) Trusted Header (for reverse proxies)"
    echo ""
    
    read -p "Choose SSO provider [1-5]: " sso_choice
    
    case $sso_choice in
      1)
        configure_google_oauth
        ;;
      2)
        configure_microsoft_oauth
        ;;
      3)
        configure_github_oauth
        ;;
      4)
        configure_oidc_oauth
        ;;
      5)
        configure_trusted_header
        ;;
      *)
        echo "Invalid choice. Disabling SSO."
        ENABLE_OPENWEBUI_SSO="n"
        ;;
    esac
    
    if [[ "$ENABLE_OPENWEBUI_SSO" == "y" || "$ENABLE_OPENWEBUI_SSO" == "Y" ]]; then
      # Configure general OAuth settings
      echo ""
      echo -e "${BLUE}🔧 General OAuth Settings${NC}"
      read -p "Allow account creation via OAuth? (y/n) [default: y]: " ENABLE_OPENWEBUI_OAUTH_SIGNUP
      ENABLE_OPENWEBUI_OAUTH_SIGNUP=${ENABLE_OPENWEBUI_OAUTH_SIGNUP:-y}
      
      read -p "Merge accounts by email? (y/n) [default: n]: " ENABLE_OPENWEBUI_OAUTH_MERGE_ACCOUNTS
      ENABLE_OPENWEBUI_OAUTH_MERGE_ACCOUNTS=${ENABLE_OPENWEBUI_OAUTH_MERGE_ACCOUNTS:-n}
      
      read -p "Update profile picture on login? (y/n) [default: y]: " ENABLE_OPENWEBUI_OAUTH_UPDATE_PICTURE
      ENABLE_OPENWEBUI_OAUTH_UPDATE_PICTURE=${ENABLE_OPENWEBUI_OAUTH_UPDATE_PICTURE:-y}
      
      echo ""
      echo "✅ SSO Configuration Summary:"
      echo "   🔐 Provider: $OPENWEBUI_SSO_PROVIDER"
      echo "   👤 Account Creation: $ENABLE_OPENWEBUI_OAUTH_SIGNUP"
      echo "   📧 Merge by Email: $ENABLE_OPENWEBUI_OAUTH_MERGE_ACCOUNTS"
      echo "   🖼️  Update Pictures: $ENABLE_OPENWEBUI_OAUTH_UPDATE_PICTURE"
    fi
  else
    echo "🔐 SSO disabled - using local authentication"
  fi
}

# Configure Google OAuth
configure_google_oauth() {
  OPENWEBUI_SSO_PROVIDER="google"
  echo ""
  echo -e "${BLUE}🔧 Google OAuth Configuration${NC}"
  
  # Auto-generate redirect URI
  OPENWEBUI_GOOGLE_REDIRECT_URI="https://$OPENWEBUI_DOMAIN_PUBLIC/oauth/google/callback"
  
  echo "To configure Google OAuth, you need to:"
  echo "  1. Go to Google Cloud Console (https://console.cloud.google.com)"
  echo "  2. Create OAuth 2.0 credentials for a web application"
  echo "  3. Add this redirect URI: $OPENWEBUI_GOOGLE_REDIRECT_URI"
  echo ""
  
  read -p "📱 Google Client ID: " OPENWEBUI_GOOGLE_CLIENT_ID
  read -s -p "🔑 Google Client Secret (hidden): " OPENWEBUI_GOOGLE_CLIENT_SECRET
  echo ""
  
  if [[ -z "$OPENWEBUI_GOOGLE_CLIENT_ID" || -z "$OPENWEBUI_GOOGLE_CLIENT_SECRET" ]]; then
    echo "❌ Google OAuth configuration incomplete. Disabling SSO."
    ENABLE_OPENWEBUI_SSO="n"
  else
    echo "✅ Google OAuth configured"
    echo "   🔗 Redirect URI: $OPENWEBUI_GOOGLE_REDIRECT_URI"
  fi
}

# Configure Microsoft OAuth
configure_microsoft_oauth() {
  OPENWEBUI_SSO_PROVIDER="microsoft"
  echo ""
  echo -e "${BLUE}🔧 Microsoft OAuth Configuration${NC}"
  
  # Auto-generate redirect URI
  OPENWEBUI_MICROSOFT_REDIRECT_URI="https://$OPENWEBUI_DOMAIN_PUBLIC/oauth/microsoft/callback"
  
  echo "To configure Microsoft OAuth, you need to:"
  echo "  1. Go to Azure Portal (https://portal.azure.com)"
  echo "  2. Create an App Registration"
  echo "  3. Add this redirect URI: $OPENWEBUI_MICROSOFT_REDIRECT_URI"
  echo ""
  
  read -p "📱 Microsoft Client ID: " OPENWEBUI_MICROSOFT_CLIENT_ID
  read -s -p "🔑 Microsoft Client Secret (hidden): " OPENWEBUI_MICROSOFT_CLIENT_SECRET
  echo ""
  read -p "🏢 Microsoft Tenant ID (use '9188040d-6c67-4c5b-b112-36a304b66dad' for personal accounts): " OPENWEBUI_MICROSOFT_CLIENT_TENANT_ID
  
  if [[ -z "$OPENWEBUI_MICROSOFT_CLIENT_ID" || -z "$OPENWEBUI_MICROSOFT_CLIENT_SECRET" || -z "$OPENWEBUI_MICROSOFT_CLIENT_TENANT_ID" ]]; then
    echo "❌ Microsoft OAuth configuration incomplete. Disabling SSO."
    ENABLE_OPENWEBUI_SSO="n"
  else
    echo "✅ Microsoft OAuth configured"
    echo "   🔗 Redirect URI: $OPENWEBUI_MICROSOFT_REDIRECT_URI"
  fi
}

# Configure GitHub OAuth
configure_github_oauth() {
  OPENWEBUI_SSO_PROVIDER="github"
  echo ""
  echo -e "${BLUE}🔧 GitHub OAuth Configuration${NC}"
  
  # Auto-generate redirect URI
  OPENWEBUI_GITHUB_REDIRECT_URI="https://$OPENWEBUI_DOMAIN_PUBLIC/oauth/github/callback"
  
  echo "To configure GitHub OAuth, you need to:"
  echo "  1. Go to GitHub Settings > Developer settings > OAuth Apps"
  echo "  2. Create a new OAuth App"
  echo "  3. Set Authorization callback URL: $OPENWEBUI_GITHUB_REDIRECT_URI"
  echo ""
  
  read -p "📱 GitHub Client ID: " OPENWEBUI_GITHUB_CLIENT_ID
  read -s -p "🔑 GitHub Client Secret (hidden): " OPENWEBUI_GITHUB_CLIENT_SECRET
  echo ""
  
  if [[ -z "$OPENWEBUI_GITHUB_CLIENT_ID" || -z "$OPENWEBUI_GITHUB_CLIENT_SECRET" ]]; then
    echo "❌ GitHub OAuth configuration incomplete. Disabling SSO."
    ENABLE_OPENWEBUI_SSO="n"
  else
    echo "✅ GitHub OAuth configured"
    echo "   🔗 Redirect URI: $OPENWEBUI_GITHUB_REDIRECT_URI"
  fi
}

# Configure Generic OIDC
configure_oidc_oauth() {
  OPENWEBUI_SSO_PROVIDER="oidc"
  echo ""
  echo -e "${BLUE}🔧 Generic OIDC Configuration${NC}"
  # Auto-generate redirect URI
  OPENWEBUI_OPENID_REDIRECT_URI="https://$OPENWEBUI_DOMAIN_PUBLIC/oauth/oidc/callback"
  
  echo "To configure OIDC, you need:"
  echo "  1. OIDC provider's well-known configuration URL"
  echo "  2. Client ID and Secret from your OIDC provider"
  echo "  3. Redirect URI: $OPENWEBUI_OPENID_REDIRECT_URI"
  echo ""
  
  read -p "📱 OIDC Client ID: " OPENWEBUI_OAUTH_CLIENT_ID
  read -s -p "🔑 OIDC Client Secret (hidden): " OPENWEBUI_OAUTH_CLIENT_SECRET
  echo ""
  read -p "🌐 OIDC Provider URL (e.g., https://accounts.google.com/.well-known/openid-configuration): " OPENWEBUI_OPENID_PROVIDER_URL
  read -p "📛 Provider Display Name [default: SSO]: " OPENWEBUI_OAUTH_PROVIDER_NAME
  OPENWEBUI_OAUTH_PROVIDER_NAME=${OPENWEBUI_OAUTH_PROVIDER_NAME:-SSO}
  read -p "🔧 OAuth Scopes [default: openid email profile]: " OPENWEBUI_OAUTH_SCOPES
  OPENWEBUI_OAUTH_SCOPES=${OPENWEBUI_OAUTH_SCOPES:-"openid email profile"}
  
  if [[ -z "$OPENWEBUI_OAUTH_CLIENT_ID" || -z "$OPENWEBUI_OAUTH_CLIENT_SECRET" || -z "$OPENWEBUI_OPENID_PROVIDER_URL" ]]; then
    echo "❌ OIDC configuration incomplete. Disabling SSO."
    ENABLE_OPENWEBUI_SSO="n"
  else
    echo "✅ OIDC configured"
    echo "   🔗 Provider: $OPENWEBUI_OAUTH_PROVIDER_NAME"
    echo "   🔗 Redirect URI: $OPENWEBUI_OPENID_REDIRECT_URI"
  fi
}

# Configure Trusted Header Authentication
configure_trusted_header() {
  OPENWEBUI_SSO_PROVIDER="trusted-header"
  echo ""
  echo -e "${BLUE}🔧 Trusted Header Configuration${NC}"
  echo "⚠️  WARNING: This is for reverse proxy authentication only!"
  echo "⚠️  Ensure only your authenticating proxy can access OpenWebUI!"
  echo "⚠️  This method works with your public domain: $OPENWEBUI_DOMAIN_PUBLIC"
  echo "⚠️  Configure your reverse proxy to add authentication headers!"
  echo ""
  echo "Common trusted header configurations:"
  echo "  • Tailscale: Tailscale-User-Login"
  echo "  • Cloudflare Access: Cf-Access-Authenticated-User-Email"
  echo "  • oauth2-proxy: X-Forwarded-Email"
  echo "  • Authentik: X-Forwarded-Email"
  echo ""
  
  read -p "📧 Email Header Name (e.g., X-Forwarded-Email): " OPENWEBUI_TRUSTED_EMAIL_HEADER
  read -p "👤 Name Header Name (optional, e.g., X-Forwarded-User): " OPENWEBUI_TRUSTED_NAME_HEADER
  
  if [[ -z "$OPENWEBUI_TRUSTED_EMAIL_HEADER" ]]; then
    echo "❌ Trusted header configuration incomplete. Disabling SSO."
    ENABLE_OPENWEBUI_SSO="n"
  else
    echo "✅ Trusted header configured"
    echo "   📧 Email Header: $OPENWEBUI_TRUSTED_EMAIL_HEADER"
    if [[ -n "$OPENWEBUI_TRUSTED_NAME_HEADER" ]]; then
      echo "   👤 Name Header: $OPENWEBUI_TRUSTED_NAME_HEADER"
    fi
    echo ""
    echo -e "${RED}⚠️  SECURITY WARNING:${NC}"
    echo "   Make sure to configure your reverse proxy properly!"
    echo "   Users can authenticate as anyone if misconfigured!"
  fi
} 