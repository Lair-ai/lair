#!/usr/bin/env bash

# region 10) Detect interface and local IP
info "Detecting default interface and local IP..."

# A function to check if a string is empty or contains only spaces
is_empty() {
  local var="$1"
  [[ -z "${var// /}" ]]
}

# A function to check if a string represents a valid interface
is_valid_interface() {
  local if_name="$1"
  [ -e "/sys/class/net/$if_name" ]
}

# Attempt 1: Use ip route to find the default interface
IFACE=""
# DEFAULT_ROUTE_OUTPUT=$(ip route 2>/dev/null | grep -m1 '^default')
DEFAULT_ROUTE_OUTPUT=$(ip route get 8.8.8.8 | head -n1)
if ! is_empty "$DEFAULT_ROUTE_OUTPUT"; then
  # Extract the part after "dev " and before the next space
  IFACE=$(echo "$DEFAULT_ROUTE_OUTPUT" | sed -n 's/.*dev \([^ ]*\).*/\1/p')
  debug "Default interface found via route: $IFACE"
fi

# Attempt 2: If we still don't have a valid interface, try with 'ip -o link show up'
if is_empty "$IFACE" || ! is_valid_interface "$IFACE"; then
  debug "Default interface '$IFACE' not valid or not found. Trying to detect an 'up' non-loopback interface."
  
  # Use a temporary variable for the candidate from this method
  IFACE_FROM_IP_LINK=""
  # Get the full line of the first "up" non-loopback interface.
  # (cmd1 | cmd2 || true) ensures the command substitution itself doesn't cause an exit if set -e is on
  # and the pipeline fails (e.g. grep finds nothing).
  TEMP_IFACE_LINE=$( (ip -o link show up 2>/dev/null | grep -v 'lo:' | head -n 1) || true )

  if [ -n "$TEMP_IFACE_LINE" ]; then
    # Attempt to parse the interface name
    CANDIDATE=$(echo "$TEMP_IFACE_LINE" | awk -F': ' '{print $2}')
    if [ -n "$CANDIDATE" ] && is_valid_interface "$CANDIDATE"; then
      # Successfully found and validated a candidate
      IFACE_FROM_IP_LINK="$CANDIDATE"
      warn "Interface '$IFACE_FROM_IP_LINK' detected as 'up' and valid via 'ip -o link show up', using this one."
      IFACE="$IFACE_FROM_IP_LINK" # Set the main IFACE
    elif [ -n "$CANDIDATE" ]; then
      # Candidate found but not valid (e.g., /sys/class/net/CANDIDATE doesn't exist)
      debug "Candidate interface '$CANDIDATE' from 'ip -o link show up' is not valid."
    else
      # awk couldn't parse the interface name from TEMP_IFACE_LINE
      debug "Could not extract interface name from: '$TEMP_IFACE_LINE'"
    fi
  else
    # The pipeline (ip -o link show up | grep ...) found no suitable interface
    debug "No 'up' non-loopback interface found via 'ip -o link show up'."
  fi

  # Final fallback if IFACE is still empty or invalid after Attempt 1 and this Attempt 2
  if is_empty "$IFACE" || ! is_valid_interface "$IFACE"; then
    warn "No valid network interface found after all attempts. Using 'eth0' as final fallback."
    IFACE="eth0"
  fi
fi

# Get the IP from the detected IFACE with a simpler and more direct method
debug "Looking for IP for interface $IFACE"
LOC_CIDR=""

# First try with ip addr
IP_ADDR_OUTPUT=$(ip -4 addr show dev "$IFACE" 2>/dev/null || echo "")
if ! is_empty "$IP_ADDR_OUTPUT"; then
  # Extract the CIDR with grep and sed
  LOC_CIDR=$(echo "$IP_ADDR_OUTPUT" | grep -oE 'inet [0-9.]+/[0-9]+' | sed 's/inet //' | head -n1)
fi

# If we still don't have an IP, try with ifconfig
if is_empty "$LOC_CIDR"; then
  debug "ip addr produced no results, trying with ifconfig"
  if command -v ifconfig >/dev/null 2>&1; then
    IFCONFIG_OUTPUT=$(ifconfig "$IFACE" 2>/dev/null || echo "")
    if ! is_empty "$IFCONFIG_OUTPUT"; then
      # Extract IP and netmask
      IP_ADDR=$(echo "$IFCONFIG_OUTPUT" | grep -oE 'inet [0-9.]+' | sed 's/inet //' | head -n1)
      NETMASK=$(echo "$IFCONFIG_OUTPUT" | grep -oE 'netmask [0-9.]+' | sed 's/netmask //' | head -n1)
      
      if ! is_empty "$IP_ADDR" && ! is_empty "$NETMASK"; then
        # Convert the netmask to CIDR
        # Simplified method - for most networks we'll use /24
        LOC_CIDR="$IP_ADDR/24"
      fi
    fi
  fi
fi

# If we still don't have an IP, last chance: hostname -I
if is_empty "$LOC_CIDR"; then
  debug "Final attempt: using hostname -I"
  HOST_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "")
  if ! is_empty "$HOST_IP"; then
    LOC_CIDR="$HOST_IP/24"
  fi
fi

# Final fallback if we still don't have an IP
if is_empty "$LOC_CIDR"; then
  warn "Unable to get IP for interface $IFACE, using default"
  LOC_CIDR="192.168.1.10/24"
  BASE_NET="192.168.1"; PREFIX="24"
elif [[ $LOC_CIDR =~ ^([0-9]+\.[0-9]+\.[0-9]+)\.([0-9]+)/([0-9]+)$ ]]; then
  # Extract IP components
  BASE_NET="${BASH_REMATCH[1]}"; HOST_PART="${BASH_REMATCH[2]}"; PREFIX="${BASH_REMATCH[3]}"
  ok "Interface $IFACE: $LOC_CIDR (${BASE_NET}.${HOST_PART}/${PREFIX})"
else
  warn "Unrecognized IP format: $LOC_CIDR, using default 192.168.1.0/24"
  BASE_NET="192.168.1"; PREFIX="24"
fi

# Print complete information for diagnostics
debug "===== NETWORK DIAGNOSTICS ====="
debug "Interface: $IFACE"
debug "IP CIDR: $LOC_CIDR"
debug "Base Network: $BASE_NET"
debug "Network Prefix: $PREFIX"
debug "==============================="

# right after block 7)
INTERACTIVE=false; [ -t 0 ] && INTERACTIVE=true
# endregion 10) Detect interface and local IP
