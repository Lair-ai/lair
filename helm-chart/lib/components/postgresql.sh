#!/bin/bash

# ============================================================================
# POSTGRESQL.SH - PostgreSQL Component Configuration
# ============================================================================

# Configure PostgreSQL component (interactive mode)
configure_postgresql() {
  echo ""
  echo -e "${GREEN}🗄️  PostgreSQL Configuration${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "PostgreSQL is the primary database for N8N workflow storage (always enabled)"
  echo ""
  
  # Storage configuration
  ask_storage_gb "PostgreSQL database" "5" "PG_STORAGE_SIZE"
  echo "✅ Storage: $PG_STORAGE_SIZE"
  
  echo "✅ PostgreSQL configuration completed"
}

# Configure PostgreSQL component (non-interactive mode for config files)
configure_postgresql_non_interactive() {
  echo ""
  echo -e "${GREEN}🗄️  PostgreSQL Configuration${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "🗄️  PostgreSQL: Always enabled"
  echo "   💾 Storage: ${PG_STORAGE_GB}GB"
  echo "✅ PostgreSQL configuration completed"
} 