#!/usr/bin/env bash

run_preflight_checks() {
    info "Running pre-startup checks..."

    # region Basic internet connectivity check
    if ! ping -c 1 -W 3 google.com &>/dev/null && ! ping -c 1 -W 3 8.8.8.8 &>/dev/null; then
        err "No internet connection detected. Check your network and DNS."
        exit 1
    else
        ok "Basic internet connectivity verified."
    fi
    # endregion Basic internet connectivity check

    # region Time synchronization check (NTP)
    if command -v timedatectl &>/dev/null; then
        NTP_STATUS=$(timedatectl status 2>/dev/null)
        if echo "$NTP_STATUS" | grep -q "NTP service: active"; then
            if echo "$NTP_STATUS" | grep -q "System clock synchronized: yes"; then
                ok "System clock is synchronized via NTP."
            else
                warn "NTP is active but system clock is NOT synchronized. This could cause issues."
            fi
        else
            warn "NTP service is not active. System clock might not be accurate."
        fi
    else
        warn "timedatectl not found. Unable to verify NTP status."
    fi
    # endregion Time synchronization check (NTP)

    # region kubectl check
    if ! command -v kubectl &> /dev/null; then
        err "kubectl not found. Make sure it's installed and in your PATH."
        exit 1
    else
        ok "kubectl found."
    fi
    # endregion kubectl check

    # region Cluster connection check
    if ! kubectl cluster-info &> /dev/null; then
        err "Unable to connect to Kubernetes cluster. Check your kubeconfig configuration."
        exit 1
    else
        ok "Kubernetes cluster connection verified."
    fi
    # endregion Cluster connection check
}