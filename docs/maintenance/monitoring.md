# 📊 System Monitoring Guide

> **Complete guide to monitoring, health checks, and observability for Lair deployments**

This guide covers comprehensive monitoring strategies for Lair infrastructure, from basic health checks to advanced observability with metrics, logs, and alerting.

---

## 🎯 Overview

Effective monitoring is crucial for maintaining a healthy Lair deployment. This guide provides tools and procedures for monitoring all aspects of your AI infrastructure, from cluster health to application performance.

### 🏗️ **Monitoring Architecture**
```
┌─────────────────────────────────────────────────────────────────┐
│                    📊 OBSERVABILITY LAYER                       │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │    Metrics      │  │      Logs       │  │     Traces      │  │
│  │  (Prometheus)   │  │   (Fluentd)     │  │    (Jaeger)     │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                                │
┌─────────────────────────────────────────────────────────────────┐
│                    📈 VISUALIZATION LAYER                        │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │    Grafana      │  │   Dashboards    │  │     Alerts      │  │
│  │ (Dashboards)    │  │  (Custom Views) │  │ (Notifications) │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                                │
┌─────────────────────────────────────────────────────────────────┐
│                     🔍 MONITORING TARGETS                        │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │   Cluster       │  │  Applications   │  │ Infrastructure  │  │
│  │ (K8s Metrics)   │  │ (App Metrics)   │  │ (Node Metrics)  │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### 📋 **Monitoring Levels**

| Level | Scope | Tools | Frequency | Purpose |
|-------|-------|-------|-----------|---------|
| **Infrastructure** | Nodes, Network, Storage | kubectl, htop, iostat | Real-time | Resource utilization |
| **Cluster** | Pods, Services, Ingress | kubectl, k9s | Real-time | Kubernetes health |
| **Applications** | OpenWebUI, N8N, Ollama | App logs, metrics | Real-time | Application performance |
| **Business** | User activity, AI usage | Custom metrics | Hourly/Daily | Business insights |

---

## 🔧 Built-in Monitoring Tools

### 📊 **Kubernetes Native Monitoring**

#### **kubectl Commands for Monitoring**
```bash
# Cluster overview
kubectl cluster-info
kubectl get nodes -o wide
kubectl get pods -A --field-selector=status.phase!=Running

# Resource usage
kubectl top nodes
kubectl top pods -A
kubectl top pods -n lair

# Component status
kubectl get componentstatuses
kubectl get events -A --sort-by='.lastTimestamp' | tail -20

# Storage monitoring
kubectl get pv
kubectl get pvc -A
kubectl describe pvc -n lair
```

#### **Real-time Monitoring Scripts**
```bash
# Create comprehensive monitoring script
./misc/monitoring/lair-monitor.sh
```

#### **Automated Health Checks**
```bash
# Create health check script
./misc/monitoring/lair-health-check.sh
```

### 📱 **K9s - Terminal UI for Kubernetes**

#### **Installation**
```bash
# Install k9s for interactive monitoring
curl -sS https://webinstall.dev/k9s | bash

# Or using package manager
# Ubuntu/Debian
sudo apt install k9s

# macOS
brew install k9s
```

#### **K9s Usage**
```bash
# Start k9s
k9s

# Key shortcuts in k9s:
# :pods           - View pods
# :svc            - View services  
# :ing            - View ingress
# :pvc            - View persistent volume claims
# :events         - View events
# :logs           - View logs
# Ctrl+A          - Show all namespaces
# /               - Filter resources
# d               - Describe resource
# l               - View logs
# e               - Edit resource
```

---

## 📈 Application-Specific Monitoring

### 🤖 **OpenWebUI Monitoring**

#### **Health Endpoints**
```bash
# Check OpenWebUI health
kubectl exec -n lair deployment/lair-openwebui -- curl -f http://localhost:8080/health

# Monitor OpenWebUI logs
kubectl logs -n lair deployment/lair-openwebui -f

# Check OpenWebUI metrics (if available)
kubectl exec -n lair deployment/lair-openwebui -- curl http://localhost:8080/metrics
```

#### **OpenWebUI Performance Monitoring**
```bash
# Monitor OpenWebUI resource usage
kubectl top pod -n lair -l app=openwebui

# Check OpenWebUI database connections
kubectl exec -n lair deployment/lair-openwebui -- netstat -an | grep 5432

# Monitor document processing
kubectl logs -n lair deployment/lair-openwebui | grep -i "upload\|process\|tika"
```

### 🧠 **Ollama Monitoring**

#### **Ollama API Monitoring**
```bash
# Check Ollama API health
kubectl exec -n lair statefulset/lair-ollama -- curl -f http://localhost:11434/api/tags

# Monitor model loading
kubectl logs -n lair statefulset/lair-ollama | grep -i "load\|model"

# Check GPU usage (if available)
kubectl exec -n lair statefulset/lair-ollama -- nvidia-smi

# Monitor Ollama performance
kubectl exec -n lair statefulset/lair-ollama -- curl http://localhost:11434/api/ps
```

#### **Model Performance Monitoring**
```bash
# Create Ollama monitoring script
cat > /usr/local/bin/lair-ollama-monitor.sh << 'EOF'
#!/bin/bash

echo "=== OLLAMA MONITORING ==="
echo "Timestamp: $(date)"
echo

# Check running models
echo "=== RUNNING MODELS ==="
kubectl exec -n lair statefulset/lair-ollama -- curl -s http://localhost:11434/api/ps | jq '.'
echo

# Check available models
echo "=== AVAILABLE MODELS ==="
kubectl exec -n lair statefulset/lair-ollama -- curl -s http://localhost:11434/api/tags | jq '.models[] | {name: .name, size: .size}'
echo

# Check resource usage
echo "=== RESOURCE USAGE ==="
kubectl top pod -n lair -l app=ollama
echo

# Check GPU usage (if available)
if kubectl exec -n lair statefulset/lair-ollama -- nvidia-smi >/dev/null 2>&1; then
    echo "=== GPU USAGE ==="
    kubectl exec -n lair statefulset/lair-ollama -- nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits
fi
EOF

chmod +x /usr/local/bin/lair-ollama-monitor.sh
```

### ⚡ **N8N Monitoring**

#### **N8N Health Monitoring**
```bash
# Check N8N health
kubectl exec -n lair deployment/lair-n8n -- curl -f http://localhost:5678/healthz

# Monitor N8N workflows
kubectl logs -n lair deployment/lair-n8n | grep -i "workflow\|execution"

# Check N8N worker status
kubectl logs -n lair deployment/lair-n8n-worker | grep -i "worker\|job"

# Monitor N8N database connections
kubectl exec -n lair deployment/lair-n8n -- netstat -an | grep 5432
```

#### **Workflow Execution Monitoring**
```bash
# Create N8N monitoring script
cat > /usr/local/bin/lair-n8n-monitor.sh << 'EOF'
#!/bin/bash

echo "=== N8N MONITORING ==="
echo "Timestamp: $(date)"
echo

# Check N8N pods
echo "=== N8N PODS STATUS ==="
kubectl get pods -n lair -l app=n8n -o wide
echo

# Check recent workflow executions (via database)
echo "=== RECENT EXECUTIONS ==="
kubectl exec -n lair statefulset/lair-postgresql -- psql -U n8n -d n8n -c "SELECT id, workflow_id, mode, started_at, finished_at, data FROM execution_entity ORDER BY started_at DESC LIMIT 10;" 2>/dev/null || echo "Database query failed"
echo

# Check N8N resource usage
echo "=== RESOURCE USAGE ==="
kubectl top pod -n lair -l app=n8n
echo

# Check Redis queue status
echo "=== REDIS QUEUE STATUS ==="
kubectl exec -n lair deployment/lair-redis -- redis-cli info replication
EOF

chmod +x /usr/local/bin/lair-n8n-monitor.sh
```

### 🗄️ **Database Monitoring**

#### **PostgreSQL Monitoring**
```bash
# Check PostgreSQL health
kubectl exec -n lair statefulset/lair-postgresql -- pg_isready -U postgres

# Monitor database connections
kubectl exec -n lair statefulset/lair-postgresql -- psql -U postgres -c "SELECT count(*) as active_connections FROM pg_stat_activity WHERE state = 'active';"

# Check database sizes
kubectl exec -n lair statefulset/lair-postgresql -- psql -U postgres -c "SELECT datname, pg_size_pretty(pg_database_size(datname)) as size FROM pg_database;"

# Monitor slow queries
kubectl exec -n lair statefulset/lair-postgresql -- psql -U postgres -c "SELECT query, calls, total_time, mean_time FROM pg_stat_statements ORDER BY mean_time DESC LIMIT 10;" 2>/dev/null || echo "pg_stat_statements not available"
```

#### **Redis Monitoring**
```bash
# Check Redis health
kubectl exec -n lair deployment/lair-redis -- redis-cli ping

# Monitor Redis info
kubectl exec -n lair deployment/lair-redis -- redis-cli info server
kubectl exec -n lair deployment/lair-redis -- redis-cli info memory
kubectl exec -n lair deployment/lair-redis -- redis-cli info stats

# Check Redis key statistics
kubectl exec -n lair deployment/lair-redis -- redis-cli --scan --pattern "*" | wc -l
```

---

## 🔍 Log Management

### 📝 **Centralized Logging Strategy**

#### **Log Collection with kubectl**
```bash
# Collect logs from all Lair components
kubectl logs -n lair deployment/lair-openwebui --tail=100 > openwebui.log
kubectl logs -n lair statefulset/lair-ollama --tail=100 > ollama.log
kubectl logs -n lair deployment/lair-n8n --tail=100 > n8n.log
kubectl logs -n lair statefulset/lair-postgresql --tail=100 > postgresql.log

# Follow logs in real-time
kubectl logs -n lair deployment/lair-openwebui -f
```

#### **Log Aggregation Script**
```bash
# Create log aggregation script
cat > /usr/local/bin/lair-logs.sh << 'EOF'
#!/bin/bash

LOG_DIR="/var/log/lair"
DATE=$(date +%Y%m%d_%H%M%S)

mkdir -p "$LOG_DIR"

echo "Collecting Lair logs at $DATE..."

# Collect application logs
kubectl logs -n lair deployment/lair-openwebui --tail=1000 > "$LOG_DIR/openwebui-$DATE.log"
kubectl logs -n lair statefulset/lair-ollama --tail=1000 > "$LOG_DIR/ollama-$DATE.log"
kubectl logs -n lair deployment/lair-n8n --tail=1000 > "$LOG_DIR/n8n-$DATE.log"
kubectl logs -n lair deployment/lair-n8n-worker --tail=1000 > "$LOG_DIR/n8n-worker-$DATE.log"
kubectl logs -n lair statefulset/lair-postgresql --tail=1000 > "$LOG_DIR/postgresql-$DATE.log"
kubectl logs -n lair deployment/lair-redis --tail=1000 > "$LOG_DIR/redis-$DATE.log"

# Collect infrastructure logs
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller --tail=1000 > "$LOG_DIR/ingress-$DATE.log"
kubectl logs -n longhorn-system daemonset/longhorn-manager --tail=1000 > "$LOG_DIR/longhorn-$DATE.log" 2>/dev/null
kubectl logs -n cert-manager deployment/cert-manager --tail=1000 > "$LOG_DIR/cert-manager-$DATE.log"

# Collect system events
kubectl get events -A --sort-by='.lastTimestamp' > "$LOG_DIR/events-$DATE.log"

# Compress logs
tar -czf "$LOG_DIR/lair-logs-$DATE.tar.gz" -C "$LOG_DIR" *.log
rm "$LOG_DIR"/*.log

echo "Logs collected: $LOG_DIR/lair-logs-$DATE.tar.gz"

# Cleanup old logs (keep 7 days)
find "$LOG_DIR" -name "lair-logs-*.tar.gz" -mtime +7 -delete
EOF

chmod +x /usr/local/bin/lair-logs.sh
```

### 🔍 **Log Analysis Tools**

#### **Log Parsing and Analysis**
```bash
# Search for errors across all logs
kubectl logs -n lair --all-containers=true --since=1h | grep -i error

# Monitor specific patterns
kubectl logs -n lair deployment/lair-openwebui -f | grep -E "(ERROR|WARN|FAIL)"

# Analyze performance patterns
kubectl logs -n lair statefulset/lair-ollama | grep -E "load|inference|model" | tail -20
```

#### **Log Rotation Configuration**
```bash
# Configure logrotate for collected logs
cat > /etc/logrotate.d/lair << 'EOF'
/var/log/lair/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
}
EOF
```

---

## 🚨 Alerting & Notifications

### 📧 **Basic Alerting System**

#### **Health Check Alerting**
```bash
# Create alerting script
cat > /usr/local/bin/lair-alerts.sh << 'EOF'
#!/bin/bash

ALERT_EMAIL="admin@example.com"
WEBHOOK_URL=""  # Slack/Discord webhook URL

send_alert() {
    local severity=$1
    local message=$2
    local timestamp=$(date)
    
    # Email alert
    if [ ! -z "$ALERT_EMAIL" ]; then
        echo "[$severity] $message - $timestamp" | mail -s "Lair Alert: $severity" "$ALERT_EMAIL"
    fi
    
    # Webhook alert (Slack/Discord)
    if [ ! -z "$WEBHOOK_URL" ]; then
        curl -X POST -H 'Content-type: application/json' \
            --data "{\"text\":\"🚨 Lair Alert [$severity]: $message - $timestamp\"}" \
            "$WEBHOOK_URL"
    fi
    
    # Log alert
    echo "$(date): [$severity] $message" >> /var/log/lair-alerts.log
}

# Run health check and alert on issues
/usr/local/bin/lair-health-check.sh
HEALTH_EXIT_CODE=$?

case $HEALTH_EXIT_CODE in
    1)
        send_alert "WARNING" "Lair system health check detected warnings"
        ;;
    2)
        send_alert "CRITICAL" "Lair system health check detected critical issues"
        ;;
esac

# Check specific conditions
# High resource usage
CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | awk -F'%' '{print $1}')
if (( $(echo "$CPU_USAGE > 90" | bc -l) )); then
    send_alert "WARNING" "High CPU usage: ${CPU_USAGE}%"
fi

# Check application availability
if ! kubectl exec -n lair deployment/lair-openwebui -- curl -f http://localhost:8080/health >/dev/null 2>&1; then
    send_alert "CRITICAL" "OpenWebUI health check failed"
fi

if ! kubectl exec -n lair statefulset/lair-ollama -- curl -f http://localhost:11434/api/tags >/dev/null 2>&1; then
    send_alert "CRITICAL" "Ollama API health check failed"
fi
EOF

chmod +x /usr/local/bin/lair-alerts.sh
```

#### **Schedule Monitoring and Alerts**
```bash
# Add to crontab for regular monitoring
crontab -e

# Add these lines:
# Health check every 5 minutes
*/5 * * * * /usr/local/bin/lair-health-check.sh >/dev/null 2>&1

# Alert check every 10 minutes
*/10 * * * * /usr/local/bin/lair-alerts.sh >/dev/null 2>&1

# Daily system report
0 8 * * * /usr/local/bin/lair-monitor.sh | mail -s "Daily Lair Report" admin@example.com

# Weekly log collection
0 2 * * 0 /usr/local/bin/lair-logs.sh >/dev/null 2>&1
```

### 📱 **Advanced Alerting Integration**

#### **Slack Integration**
```bash
# Slack webhook configuration
SLACK_WEBHOOK="https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK"

send_slack_alert() {
    local severity=$1
    local message=$2
    local color=""
    
    case $severity in
        "CRITICAL") color="danger" ;;
        "WARNING") color="warning" ;;
        "INFO") color="good" ;;
    esac
    
    curl -X POST -H 'Content-type: application/json' \
        --data "{
            \"attachments\": [{
                \"color\": \"$color\",
                \"title\": \"Lair Alert: $severity\",
                \"text\": \"$message\",
                \"footer\": \"Lair Monitoring\",
                \"ts\": $(date +%s)
            }]
        }" \
        "$SLACK_WEBHOOK"
}
```

#### **Discord Integration**
```bash
# Discord webhook configuration
DISCORD_WEBHOOK="https://discord.com/api/webhooks/YOUR/DISCORD/WEBHOOK"

send_discord_alert() {
    local severity=$1
    local message=$2
    local color=""
    
    case $severity in
        "CRITICAL") color=15158332 ;;  # Red
        "WARNING") color=16776960 ;;   # Yellow
        "INFO") color=65280 ;;         # Green
    esac
    
    curl -X POST -H 'Content-type: application/json' \
        --data "{
            \"embeds\": [{
                \"title\": \"Lair Alert: $severity\",
                \"description\": \"$message\",
                \"color\": $color,
                \"footer\": {
                    \"text\": \"Lair Monitoring\"
                },
                \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%S.000Z)\"
            }]
        }" \
        "$DISCORD_WEBHOOK"
}
```

---

## 📊 Performance Monitoring

### 🚀 **Resource Usage Monitoring**

#### **Continuous Resource Monitoring**
```bash
# Create resource monitoring script
./misc/monitoring/lair-resource-monitor.sh 
```

#### **Performance Benchmarking**
```bash
# Create performance benchmark script
cat > /usr/local/bin/lair-benchmark.sh << 'EOF'
#!/bin/bash

echo "=== LAIR PERFORMANCE BENCHMARK ==="
echo "Started: $(date)"
echo

# Test Ollama API response time
echo "=== OLLAMA API BENCHMARK ==="
time kubectl exec -n lair statefulset/lair-ollama -- curl -s http://localhost:11434/api/tags >/dev/null
echo

# Test OpenWebUI response time
echo "=== OPENWEBUI BENCHMARK ==="
time kubectl exec -n lair deployment/lair-openwebui -- curl -s http://localhost:8080/health >/dev/null
echo

# Test database performance
echo "=== DATABASE BENCHMARK ==="
time kubectl exec -n lair statefulset/lair-postgresql -- psql -U postgres -c "SELECT count(*) FROM pg_stat_activity;" >/dev/null 2>&1
echo

# Test storage I/O
echo "=== STORAGE I/O BENCHMARK ==="
kubectl exec -n lair deployment/lair-openwebui -- dd if=/dev/zero of=/tmp/test bs=1M count=100 2>&1 | grep copied
kubectl exec -n lair deployment/lair-openwebui -- rm /tmp/test
echo

echo "Benchmark completed: $(date)"
EOF

chmod +x /usr/local/bin/lair-benchmark.sh
```

---

## 🔧 Monitoring Best Practices

### 📊 **Monitoring Strategy**
- **Layered Monitoring**: Monitor infrastructure, platform, and applications
- **Proactive Alerting**: Set up alerts before issues become critical
- **Baseline Establishment**: Establish performance baselines for comparison
- **Regular Reviews**: Regularly review and update monitoring configurations

### 🚨 **Alerting Best Practices**
- **Alert Fatigue Prevention**: Avoid too many low-priority alerts
- **Escalation Procedures**: Define clear escalation paths for different severities
- **Documentation**: Document all alerts and their resolution procedures
- **Testing**: Regularly test alerting mechanisms

### 📈 **Performance Optimization**
- **Resource Right-sizing**: Continuously optimize resource allocation
- **Capacity Planning**: Monitor trends for capacity planning
- **Bottleneck Identification**: Identify and address performance bottlenecks
- **Regular Benchmarking**: Establish regular performance benchmarking

---

## 🔍 Troubleshooting Monitoring Issues

### 🚨 **Common Monitoring Problems**

#### **Metrics Server Not Available**
```bash
# Install metrics server if missing
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Check metrics server status
kubectl get pods -n kube-system -l k8s-app=metrics-server
```

#### **High Resource Usage Alerts**
```bash
# Identify resource-heavy pods
kubectl top pods -A --sort-by=cpu
kubectl top pods -A --sort-by=memory

# Check resource limits and requests
kubectl describe pod -n lair <pod-name> | grep -A 5 -B 5 resources
```

#### **Log Collection Issues**
```bash
# Check log retention settings
kubectl describe pod -n lair <pod-name> | grep -i log

# Increase log retention if needed
kubectl patch deployment <deployment-name> -n lair -p '{"spec":{"template":{"spec":{"containers":[{"name":"<container-name>","args":["--log-level=info","--log-retention=7d"]}]}}}}'
```

---

**🎯 Ready to optimize your monitoring?** Continue with [Update Procedures](updates.md) or explore [Platform-Specific Troubleshooting](../troubleshooting/platform-specific.md)!
