#!/bin/bash

# ============================================================================
# REDIS.SH - Redis Component Configuration
# ============================================================================

# Configure Redis component (interactive mode)
configure_redis() {
  echo ""
  echo -e "${GREEN}⚡ Redis Configuration${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Redis provides in-memory caching and message brokering for N8N (always enabled)"
  echo ""
  
  # Storage configuration
  ask_storage_gb "Redis cache" "5" "REDIS_STORAGE_SIZE"
  echo "✅ Storage: $REDIS_STORAGE_SIZE"
  
  echo "✅ Redis configuration completed"
}

# Configure Redis component (non-interactive mode for config files)
configure_redis_non_interactive() {
  echo ""
  echo -e "${GREEN}⚡ Redis Configuration${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "⚡ Redis: Always enabled"
  echo "   💾 Storage: ${REDIS_STORAGE_GB}GB"
  echo "✅ Redis configuration completed"
} 