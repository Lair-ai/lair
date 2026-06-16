#!/bin/bash

# ============================================================================
# LAIR CONFIGURATION SCRIPT - MODULAR VERSION
# ============================================================================
# Script to create a custom values file for the Lair Helm chart
# This script has been refactored into modular components for better maintainability

set -e

# Verify execution as root
if [ "$(id -u)" -ne 0 ]; then
  echo -e "\e[31m[ERROR]\e[0m This script must be run as root"
  echo -e "\e[33m[HINT]\e[0m  Run: sudo ./setup.sh"
  exit 1
fi

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

# Check if lib directory exists
if [ ! -d "$LIB_DIR" ]; then
    echo "❌ Error: Library directory $LIB_DIR does not exist"
    exit 1
fi

# Source all library modules with error checking
echo "📚 Loading library modules..."

modules=("globals.sh" "helpers.sh" "system-detection.sh" "config-management.sh" "component-config.sh" "yaml-generation.sh" "deployment.sh" "phases.sh")

for module in "${modules[@]}"; do
    module_path="$LIB_DIR/$module"
    if [ -f "$module_path" ]; then
        echo "  ✅ Loading $module"
        source "$module_path"
    else
        echo "  ❌ Error: Module $module not found at $module_path"
        exit 1
    fi
done

# Load all component modules
echo "📦 Loading component modules..."
component_modules=("openwebui.sh" "ollama.sh" "n8n.sh" "comfyui.sh" "minio.sh" "postgresql.sh" "redis.sh")

for component in "${component_modules[@]}"; do
    component_path="$LIB_DIR/components/$component"
    if [ -f "$component_path" ]; then
        echo "  ✅ Loading $component"
        source "$component_path"
    else
        echo "  ❌ Error: Component $component not found at $component_path"
        exit 1
    fi
done

echo "✅ All modules and components loaded successfully"

# ============================================================================
# UPDATE MODE EXECUTION
# ============================================================================

main_update() {
  echo "🔄 UPDATE MODE: Modifying existing configuration"
  echo "════════════════════════════════════════════════════════════════════════════════"
  echo ""
  echo "Configuration file: $CONFIG_FILE_PATH"
  echo ""

  # Initialize YAML parser
  check_yaml_parser

  # Load existing configuration
  if ! load_configuration_from_file "$CONFIG_FILE_PATH"; then
    echo -e "${RED}❌ Failed to load configuration file: $CONFIG_FILE_PATH${NC}"
    exit 1
  fi

  echo -e "${GREEN}✅ Configuration loaded successfully${NC}"
  echo ""

  # Set CONFIG_FILE for generate_complete_yaml_configuration
  # Extract config name from the file path
  local filename=$(basename "$CONFIG_FILE_PATH")
  if [[ "$filename" =~ ^values-(.+)\.yaml$ ]]; then
    CONFIG_NAME="${BASH_REMATCH[1]}"
    CONFIG_FILE="values-${CONFIG_NAME}.yaml"
  else
    # Fallback: use the original filename
    CONFIG_FILE="$CONFIG_FILE_PATH"
    CONFIG_NAME=$(basename "$CONFIG_FILE_PATH" .yaml)
  fi
  
  echo "📝 Will update configuration: $CONFIG_FILE (name: $CONFIG_NAME)"
  echo ""

  # Detect system and commands for context
  detect_commands

  # Show update menu
  while true; do
    echo "════════════════════════════════════════════════════════════════════════════════"
    echo -e "${BLUE}🛠️  CONFIGURATION UPDATE MENU${NC}"
    echo "════════════════════════════════════════════════════════════════════════════════"
    echo ""
    echo "What would you like to update?"
    echo ""
    echo "  1) 🌐 Domains & Access Mode (LAN/Public/Email)"
    echo "  2) 📦 Resource Allocation (CPU/Memory)"
    echo "  3) ⚙️  Component Configuration (All Services)"
    echo "  4) 🚀 Apply Changes and Deploy"
    echo "  5) 💾 Save Configuration Only (No Deploy)"
    echo "  6) ❌ Exit without changes"
    echo ""
    read -p "Select an option (1-6): " update_choice

    case $update_choice in
      1)
        echo ""
        echo -e "${YELLOW}🌐 Updating domains and access configuration...${NC}"
        configure_access_mode_and_email
        ;;
      2)
        echo ""
        echo -e "${YELLOW}📦 Updating resource allocations...${NC}"
        echo "Re-detecting system resources for updated calculations..."
        detect_system_resources
        detect_cluster_storage
        prompt_and_calculate_resource_allocations
        ;;
      3)
        echo ""
        echo -e "${YELLOW}⚙️  Updating component configurations...${NC}"
        configure_all_components
        ;;
      4)
        echo ""
        echo -e "${GREEN}🚀 Applying changes and deploying...${NC}"
        save_and_deploy_configuration
        break
        ;;
      5)
        echo ""
        echo -e "${GREEN}💾 Saving configuration...${NC}"
        save_configuration_only
        break
        ;;
      6)
        echo ""
        echo -e "${YELLOW}❌ Exiting without changes...${NC}"
        echo "No changes were applied."
        exit 0
        ;;
      *)
        echo -e "${RED}❌ Invalid option. Please select 1-6.${NC}"
        ;;
    esac
    echo ""
  done

  echo ""
  echo "════════════════════════════════════════════════════════════════════════════════"
  echo -e "${GREEN}✅ CONFIGURATION UPDATE COMPLETED${NC}"
  echo "════════════════════════════════════════════════════════════════════════════════"
}

# Helper functions for update mode
save_and_deploy_configuration() {
  echo "📋 Generating updated configuration..."
  generate_complete_yaml_configuration
  
  echo ""
  echo -e "${GREEN}✅ Configuration file updated: $CONFIG_FILE${NC}"
  echo ""
  
  # Determine release name from existing deployment
  local existing_releases=$($HELM_CMD ls -n "$NAMESPACE" -q 2>/dev/null)
  if [ -z "$existing_releases" ]; then
    echo -e "${YELLOW}⚠️  No existing Helm release found in namespace '$NAMESPACE'${NC}"
    echo "This might be a new deployment. Consider using the main setup instead."
    read -p "Do you want to proceed with a new installation? (y/n): " proceed_new
    if [[ "$proceed_new" != "y" && "$proceed_new" != "Y" ]]; then
      echo "Update cancelled."
      return 1
    fi
    RELEASE_NAME="lair"
    NEW_INSTALL="y"
  else
    RELEASE_NAME=$(echo "$existing_releases" | head -n 1)
    echo "🔍 Found existing release: $RELEASE_NAME"
    NEW_INSTALL="n"
  fi
  
  echo "🚀 Applying configuration changes..."
  
  # Let user choose which helm to use (only if both are available)
  choose_helm_command
  
  # Set variables that execute_helm_deployment expects
  AUTO_DEPLOY="true"
  
  # Call the standard deployment function with our pre-determined settings
  if [[ "$NEW_INSTALL" == "y" ]]; then
    echo "Installing new Helm release..."
    if ! verify_and_prepare_namespace "$NAMESPACE" "$RELEASE_NAME"; then
      echo "Installation cancelled due to namespace issues."
      return 1
    fi
    run_helm_with_fallback "install" "$RELEASE_NAME" "$NAMESPACE" "$CONFIG_FILE" false
  else
    echo "Upgrading existing Helm release..."
    run_helm_with_fallback "upgrade" "$RELEASE_NAME" "$NAMESPACE" "$CONFIG_FILE" false
  fi
  
  if [ $? -eq 0 ]; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${GREEN}🎉 Configuration update deployed successfully!${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo -e "${BLUE}📊 Monitor the update process:${NC}"
    echo "  • $KUBECTL_CMD get pods -n $NAMESPACE -w"
    echo "  • $KUBECTL_CMD get services -n $NAMESPACE"
    echo "  • $KUBECTL_CMD get ingress -n $NAMESPACE"
    echo ""
    echo -e "${YELLOW}⚠️  Services may restart during update. Allow 2-3 minutes for stabilization.${NC}"
    if [ -n "$OPENWEBUI_DOMAIN_LAN" ] || [ -n "$OPENWEBUI_DOMAIN_PUBLIC" ]; then
      echo -e "${YELLOW}⚠️  Domain/certificate changes may take 5-10 minutes to propagate.${NC}"
    fi
  else
    echo -e "${RED}❌ Update deployment failed${NC}"
    return 1
  fi
}

save_configuration_only() {
  echo "📋 Generating updated configuration..."
  generate_complete_yaml_configuration
  
  echo ""
  echo -e "${GREEN}✅ Configuration saved to: $CONFIG_FILE${NC}"
  echo ""
  
  # Try to detect existing release for command suggestion
  local existing_releases=$($HELM_CMD ls -n "$NAMESPACE" -q 2>/dev/null)
  if [ -n "$existing_releases" ]; then
    local release_name=$(echo "$existing_releases" | head -n 1)
    echo "To deploy the changes to existing release '$release_name', run:"
    echo "  $HELM_CMD upgrade $release_name . -f values.yaml -f $CONFIG_FILE -n $NAMESPACE"
  else
    echo "To deploy this configuration as a new installation, run:"
    echo "  $HELM_CMD install lair . -f values.yaml -f $CONFIG_FILE -n $NAMESPACE --create-namespace"
  fi
  
  echo ""
  echo -e "${BLUE}📝 Note: Always use both base values.yaml and your custom $CONFIG_FILE${NC}"
}



# ============================================================================
# MAIN SCRIPT EXECUTION
# ============================================================================

main() {
  echo ""
  echo "════════════════════════════════════════════════════════════════════════════════"
  echo -e "${BLUE}🚀 LAIR CONFIGURATION SCRIPT - MODULAR VERSION${NC}"
  echo "════════════════════════════════════════════════════════════════════════════════"
  echo ""

  # Handle command line arguments
  check_config_file_parameter "$@"

  # Check if we're in update mode
  if [ "$UPDATE_MODE" = "true" ]; then
    main_update
    return 0
  fi

  echo "This script will help you configure and deploy the Lair platform."
  echo "The script is now modular and organized into different phases:"
  echo ""
  echo "  Phase 1: System Detection & Resource Planning"
  echo "  Phase 2: Platform & Application Configuration"  
  echo "  Phase 3: Infrastructure & Deployment Setup"
  echo "  Phase 4: Configuration Generation & Deployment"
  echo ""

  # Initial setup
  echo -e "${GREEN}🔧 Initial Setup${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  # Load configuration from file if specified
  if [ "$USE_CONFIG_FILE" = "true" ]; then
    echo "📋 Loading configuration from file: $CONFIG_FILE_PATH"
    
    # Initialize YAML parser before loading configuration
    install_yaml_dependencies_if_missing
    check_yaml_parser
    
    if load_configuration_from_file "$CONFIG_FILE_PATH"; then
      echo "✅ Configuration loaded successfully from file"
    else
      echo "❌ Failed to load configuration file. Falling back to interactive mode."
      USE_CONFIG_FILE=false
    fi
  else
    echo "⚙️  Interactive configuration mode"
    
    # Initialize YAML parser for potential file import
    echo "🔍 Debug: Checking for YAML parser..."
    install_yaml_dependencies_if_missing
    if check_yaml_parser; then
      echo "🔍 Debug: YAML parser available, enabling config file import"
      
      # Check if config import should be skipped
      if [ "$SKIP_CONFIG_IMPORT" = "true" ]; then
        echo "🔧 Skipping configuration file import (--interactive mode)"
        USE_CONFIG_FILE=false
      else
        # Handle the return from ask_for_config_file_import explicitly
        if ask_for_config_file_import; then
          if load_configuration_from_file "$CONFIG_FILE_PATH"; then
            USE_CONFIG_FILE=true
            echo "✅ Configuration loaded successfully from file"
          else
            echo "❌ Failed to load configuration file. Continuing with interactive mode."
            USE_CONFIG_FILE=false
          fi
        else
          USE_CONFIG_FILE=false
        fi
      fi
    else
      echo "🔍 Debug: No YAML parser available, skipping config file import"
      echo "ℹ️  No YAML parser found - proceeding with interactive mode"
      USE_CONFIG_FILE=false
    fi
  fi

  detect_commands

  # Execute the main phases
  echo ""
  execute_system_detection_phase
  echo ""
  execute_application_configuration_phase
  echo ""
  execute_infrastructure_setup_phase
  echo ""
  execute_configuration_generation_phase

  echo ""
  echo "════════════════════════════════════════════════════════════════════════════════"
  echo -e "${GREEN}✅ LAIR CONFIGURATION COMPLETED SUCCESSFULLY${NC}"
  echo "════════════════════════════════════════════════════════════════════════════════"
  echo ""
  echo "Your Lair platform has been configured and deployed!"
  echo ""
  echo "Configuration file: $CONFIG_FILE"
  echo "Namespace: $NAMESPACE"
  echo "Platform: $PLATFORM_TYPE"
  echo ""
  echo "════════════════════════════════════════════════════════════════════════════════"
  echo -e "${YELLOW}⚠️  IMPORTANT - ACTION REQUIRED IMMEDIATELY${NC}"
  echo "════════════════════════════════════════════════════════════════════════════════"
  echo ""
  echo -e "${RED}🔐 CREATE ADMIN ACCOUNTS NOW!${NC}"
  echo ""
  echo "You MUST immediately create administrator accounts for:"
  echo ""
  echo -e "  ${YELLOW}1. OpenWebUI${NC} - Access the web interface and create the first admin user"
  echo -e "  ${YELLOW}2. N8N${NC} - Access the web interface and configure the administrator account"
  echo ""
  echo -e "${RED}⚠️  WARNING:${NC} If you don't create these accounts immediately, anyone can"
  echo "   access your applications and configure themselves as administrator!"
  echo ""
  echo "════════════════════════════════════════════════════════════════════════════════"
  echo ""
  
  # Show LAN TLS certificate setup instructions if enabled
  if [[ "$ENABLE_LAN_TLS" == "true" ]]; then
    echo -e "${BLUE}🔐 LAN TLS CERTIFICATE SETUP REQUIRED${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo -e "${YELLOW}⚠️  You enabled HTTPS for .local domains but certificates are not yet generated!${NC}"
    echo ""
    echo -e "${GREEN}📋 To enable trusted HTTPS certificates for your .local domains:${NC}"
    echo ""
    echo "1. Generate certificates using one of these methods:"
    echo ""
    echo -e "   ${BLUE}🌐 Method 1: Remote execution (recommended)${NC}"
    echo "   Run on cluster host for automatic CA distribution:"
    echo -e "   ${YELLOW}./generate-lan-certificates.sh --wildcard $SYSTEM_HOSTNAME.local --remote-host CLUSTER_IP --remote-user USERNAME${NC}"
    echo ""
    echo -e "   ${BLUE}🏠 Method 2: Local execution${NC}"
    echo "   Run locally (requires manual CA distribution):"
    echo -e "   ${YELLOW}./generate-lan-certificates.sh --wildcard $SYSTEM_HOSTNAME.local${NC}"
    echo ""
    echo "2. After certificate generation, upgrade your deployment:"
    echo -e "   ${YELLOW}$HELM_CMD upgrade lair . -f values.yaml -f $CONFIG_FILE${NC}"
    echo ""
    echo "3. Install mkcert CA on client machines for trusted certificates"
    echo "   (the script will provide specific instructions for your OS)"
    echo ""
    echo -e "${GREEN}📖 Your .local domains will be:${NC}"
    if [[ "$ENABLE_LAN_ACCESS" == "true" ]]; then
      echo -e "   • https://chat.$SYSTEM_HOSTNAME.local"
      echo -e "   • https://n8n.$SYSTEM_HOSTNAME.local"
      echo -e "   • https://storage.$SYSTEM_HOSTNAME.local"
    fi
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
  fi
  
  echo "Next steps:"
  echo "  • Check the status of your deployment: $KUBECTL_CMD get pods -n $NAMESPACE"
  echo "  • Monitor the services: $KUBECTL_CMD get services -n $NAMESPACE"
  echo "  • Access your applications using the configured domains"
  echo ""
  echo "For troubleshooting, check the documentation in the docs/ directory."
}

# Show help if requested
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  show_help
  exit 0
fi

# Execute main function
main "$@"