#!/usr/bin/env bash

# region 33.5) Jetson-specific aliases for sudo commands
if $IS_JETSON; then
  info "Jetson system: setting up command aliases for sudo requirements..."
  
  PAR_USER="${SUDO_USER:-$USER}"
  PAR_HOME=$(getent passwd "$PAR_USER" | cut -d: -f6)
  BASHRC_FILE="$PAR_HOME/.bashrc"
  
  # Check if aliases already exist
  if grep -q "# LAIR Jetson Aliases" "$BASHRC_FILE" 2>/dev/null; then
    info "Jetson aliases already configured, skipping..."
  else
    info "Adding Jetson-specific aliases to $BASHRC_FILE..."
    
    # Add aliases to .bashrc
    cat >> "$BASHRC_FILE" << 'EOF'

# LAIR Jetson Aliases - Added by MicroK8s setup
# These aliases are needed on Jetson due to capabilities limitations
alias microk8s='sudo microk8s'
alias kubectl='sudo kubectl'
alias helm='sudo helm'
EOF
    
    run_cmd "chown $PAR_USER:$PAR_USER $BASHRC_FILE" "Setting .bashrc ownership"
    
    # Create helm wrapper (like kubectl wrapper but for helm)
    info "Creating helm wrapper for Jetson compatibility..."
    # Use microk8s helm3 instead of snap helm for better Jetson compatibility
    cat > /usr/local/bin/helm << 'HELM_EOF'
#!/usr/bin/env bash
exec sudo microk8s helm3 "$@"
HELM_EOF
    run_cmd "chmod +x /usr/local/bin/helm" "Setting helm wrapper executable"
    ok "helm wrapper created at /usr/local/bin/helm (using microk8s helm3)"
    
    ok "Jetson aliases configured successfully"
    info "Aliases added:"
    info "  • microk8s → sudo microk8s"
    info "  • kubectl → sudo kubectl (via wrapper)" 
    info "  • helm → sudo helm (via wrapper)"
    info ""
    info "To activate aliases in current session, run:"
    info "  source ~/.bashrc"
    info "Or start a new terminal session"
  fi
else
  info "Non-Jetson system, skipping alias configuration"
fi
# endregion 33.5) Jetson-specific aliases for sudo commands 