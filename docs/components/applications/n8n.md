# ⚡ N8N - Workflow Automation Platform

> **Complete guide to N8N configuration, workflow automation, and integration in Lair**

N8N is the powerful workflow automation platform in Lair, enabling seamless integration between AI services, external APIs, and business processes. This guide covers installation, configuration, workflow creation, and advanced automation scenarios.

---

## 🎯 Overview

N8N serves as the automation backbone of Lair, connecting AI capabilities with external services and business processes. It provides a visual workflow editor with 400+ integrations and powerful automation capabilities.

### ✨ **Key Features**
- **🎨 Visual Workflow Editor**: Drag-and-drop interface for creating complex automations
- **🔌 400+ Integrations**: Connect to APIs, databases, cloud services, and more
- **🤖 AI Integration**: Native integration with Ollama and OpenWebUI
- **⚡ Queue-Based Execution**: Scalable workflow processing with Redis queues
- **📧 User Management**: Multi-user support with role-based access control
- **🔒 Security**: Encryption, secure credentials, and webhook authentication
- **📊 Monitoring**: Built-in metrics and execution tracking

### 🔗 **Integration Points**
- **Ollama**: Direct AI model integration for intelligent workflows
- **OpenWebUI**: Trigger workflows from chat interactions
- **PostgreSQL**: Persistent workflow and execution storage
- **Redis**: Queue management for scalable execution
- **MinIO**: File storage and processing workflows
- **External APIs**: 400+ pre-built connectors

---

## 🚀 Getting Started

### 🌐 **Accessing N8N**

#### **Web Interface Access**
```bash
# LAN Access (default configuration)
https://n8n.hostname.local

# Public Access (if configured)
https://n8n.example.com

# Internal Access (from within cluster)
http://lair-n8n.lair.svc.cluster.local:5678
```

#### **First-Time Setup**
```bash
# Check N8N status
kubectl get pods -n lair -l app=n8n

# Access N8N interface
# Navigate to your configured domain
# Complete initial setup wizard
```

### 🔧 **Initial Configuration**

#### **User Management Setup**
N8N supports multi-user environments with proper SMTP configuration:

```yaml
# SMTP Configuration (required for user management)
n8n:
  smtp:
    enabled: true
    host: "smtp.gmail.com"
    port: 587
    user: "your-email@gmail.com"
    password: "your-app-password"
    sender: "n8n@yourdomain.com"
    ssl: true
    starttls: true
```

#### **Security Configuration**
```yaml
# Security settings
n8n:
  encryptionKey: "your-32-character-encryption-key"
  extraEnv:
    - name: N8N_SECURE_COOKIE
      value: "false"  # Set to false for .local domains
    - name: N8N_USER_MANAGEMENT_DISABLED
      value: "false"
```

---

## 🔧 Architecture & Deployment

### 🏗️ **N8N Architecture**

#### **Main Components**
```
┌─────────────────────────────────────────────────────────────────┐
│                     🎛️ N8N ARCHITECTURE                         │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │   N8N Main      │  │   N8N Workers   │  │   Redis Queue   │  │
│  │ (Web UI + API)  │  │  (Execution)    │  │   (Bull Queue)  │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                                │
┌─────────────────────────────────────────────────────────────────┐
│                     💾 PERSISTENCE LAYER                        │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │   PostgreSQL    │  │  File Storage   │  │   MinIO S3      │  │
│  │ (Workflows/Data)│  │ (User Files)    │  │ (Large Files)   │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

#### **Deployment Configuration**
```yaml
# N8N Main Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: n8n
  namespace: lair
spec:
  replicas: 1  # Single replica for main instance
  selector:
    matchLabels:
      app: n8n
  template:
    spec:
      securityContext:
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
```

#### **Worker Deployment**
```yaml
# N8N Worker Deployment (scalable)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: n8n-worker
  namespace: lair
spec:
  replicas: 2  # Scalable based on workload
  selector:
    matchLabels:
      app: n8n-worker
  template:
    spec:
      containers:
      - name: n8n-worker
        command: ["n8n", "worker"]
        env:
        - name: N8N_DISABLE_UI
          value: "true"  # Workers don't serve UI
```

### ⚙️ **Configuration Management**

#### **Environment Variables**
```yaml
env:
  # Core Configuration
  - name: NODE_ENV
    value: "production"
  - name: N8N_PORT
    value: "5678"
  - name: N8N_PROTOCOL
    value: "https"  # or "http" for internal
  - name: N8N_HOST
    value: "n8n.example.com"
  
  # Database Configuration
  - name: DB_TYPE
    value: "postgresdb"
  - name: DB_POSTGRESDB_HOST
    value: "lair-postgresql"
  - name: DB_POSTGRESDB_DATABASE
    value: "n8n"
  
  # Queue Configuration
  - name: EXECUTIONS_MODE
    value: "queue"
  - name: QUEUE_BULL_REDIS_HOST
    value: "lair-redis"
  - name: QUEUE_HEALTH_CHECK_ACTIVE
    value: "true"
  
  # Security
  - name: N8N_ENCRYPTION_KEY
    value: "your-encryption-key"
  - name: N8N_USER_MANAGEMENT_DISABLED
    value: "false"
```

#### **Resource Configuration**
```yaml
n8n:
  resources:
    limits:
      memory: "1Gi"
      cpu: "1000m"
    requests:
      memory: "512Mi"
      cpu: "300m"
  
  worker:
    replicas: 2
    resources:
      limits:
        memory: "512Mi"
        cpu: "500m"
      requests:
        memory: "256Mi"
        cpu: "200m"
```

---

## 🎨 Workflow Creation & Management

### 📝 **Creating Your First Workflow**

#### **Basic AI Chat Workflow**
```json
{
  "name": "AI Chat Automation",
  "nodes": [
    {
      "name": "Webhook",
      "type": "n8n-nodes-base.webhook",
      "parameters": {
        "path": "ai-chat",
        "httpMethod": "POST"
      }
    },
    {
      "name": "Ollama",
      "type": "n8n-nodes-base.httpRequest",
      "parameters": {
        "url": "http://lair-ollama/api/generate",
        "method": "POST",
        "body": {
          "model": "llama3.1:8b",
          "prompt": "={{$json.message}}",
          "stream": false
        }
      }
    },
    {
      "name": "Response",
      "type": "n8n-nodes-base.respondToWebhook",
      "parameters": {
        "responseBody": "={{$json.response}}"
      }
    }
  ]
}
```

#### **Document Processing Workflow**
```json
{
  "name": "Document Analysis",
  "nodes": [
    {
      "name": "File Upload",
      "type": "n8n-nodes-base.webhook",
      "parameters": {
        "path": "upload-doc",
        "httpMethod": "POST"
      }
    },
    {
      "name": "Tika Extract",
      "type": "n8n-nodes-base.httpRequest",
      "parameters": {
        "url": "http://lair-tika:9998/tika",
        "method": "PUT",
        "body": "={{$binary.data}}"
      }
    },
    {
      "name": "AI Analysis",
      "type": "n8n-nodes-base.httpRequest",
      "parameters": {
        "url": "http://lair-ollama/api/generate",
        "method": "POST",
        "body": {
          "model": "llama3.1:8b",
          "prompt": "Analyze this document: {{$json.body}}",
          "stream": false
        }
      }
    }
  ]
}
```

### 🔄 **Advanced Workflow Patterns**

#### **Conditional Logic Workflow**
```json
{
  "name": "Smart Content Router",
  "nodes": [
    {
      "name": "Input",
      "type": "n8n-nodes-base.webhook"
    },
    {
      "name": "Content Analysis",
      "type": "n8n-nodes-base.httpRequest",
      "parameters": {
        "url": "http://lair-ollama/api/generate",
        "body": {
          "model": "llama3.1:8b",
          "prompt": "Classify this content type: {{$json.content}}"
        }
      }
    },
    {
      "name": "Route Decision",
      "type": "n8n-nodes-base.if",
      "parameters": {
        "conditions": {
          "string": [
            {
              "value1": "={{$json.response}}",
              "operation": "contains",
              "value2": "technical"
            }
          ]
        }
      }
    },
    {
      "name": "Technical Processing",
      "type": "n8n-nodes-base.httpRequest"
    },
    {
      "name": "General Processing",
      "type": "n8n-nodes-base.httpRequest"
    }
  ]
}
```

#### **Batch Processing Workflow**
```json
{
  "name": "Batch Document Processing",
  "nodes": [
    {
      "name": "File List",
      "type": "n8n-nodes-base.webhook"
    },
    {
      "name": "Split Files",
      "type": "n8n-nodes-base.splitInBatches",
      "parameters": {
        "batchSize": 5
      }
    },
    {
      "name": "Process Batch",
      "type": "n8n-nodes-base.httpRequest",
      "parameters": {
        "url": "http://lair-ollama/api/generate"
      }
    },
    {
      "name": "Merge Results",
      "type": "n8n-nodes-base.merge"
    }
  ]
}
```

---

## 🔌 Integration Scenarios

### 🤖 **AI Integration Patterns**

#### **Ollama Integration**
```javascript
// Custom node for Ollama integration
const ollamaRequest = {
  url: 'http://lair-ollama/api/generate',
  method: 'POST',
  headers: {
    'Content-Type': 'application/json'
  },
  body: {
    model: 'llama3.1:8b',
    prompt: items[0].json.userInput,
    stream: false,
    options: {
      temperature: 0.7,
      top_p: 0.9
    }
  }
};
```

#### **OpenWebUI Integration**
```javascript
// Trigger workflows from OpenWebUI
const webhookUrl = 'https://n8n.example.com/webhook/ai-process';
const payload = {
  message: userMessage,
  context: conversationContext,
  userId: currentUser.id
};

fetch(webhookUrl, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify(payload)
});
```

### 📊 **Business Integration Examples**

#### **CRM Integration Workflow**
```json
{
  "name": "AI-Powered CRM Updates",
  "description": "Analyze customer interactions and update CRM",
  "nodes": [
    {
      "name": "Customer Interaction",
      "type": "n8n-nodes-base.webhook"
    },
    {
      "name": "Sentiment Analysis",
      "type": "n8n-nodes-base.httpRequest",
      "parameters": {
        "url": "http://lair-ollama/api/generate",
        "body": {
          "model": "llama3.1:8b",
          "prompt": "Analyze sentiment and extract key points: {{$json.interaction}}"
        }
      }
    },
    {
      "name": "Update CRM",
      "type": "n8n-nodes-base.salesforce",
      "parameters": {
        "operation": "update",
        "resource": "contact"
      }
    }
  ]
}
```

#### **Email Automation Workflow**
```json
{
  "name": "Smart Email Responses",
  "nodes": [
    {
      "name": "Email Trigger",
      "type": "n8n-nodes-base.emailReadImap"
    },
    {
      "name": "Email Classification",
      "type": "n8n-nodes-base.httpRequest",
      "parameters": {
        "url": "http://lair-ollama/api/generate",
        "body": {
          "model": "llama3.1:8b",
          "prompt": "Classify this email and suggest response: {{$json.text}}"
        }
      }
    },
    {
      "name": "Send Response",
      "type": "n8n-nodes-base.emailSend"
    }
  ]
}
```

---

## 📊 Monitoring & Management

### 🔍 **Workflow Monitoring**

#### **Execution Tracking**
```bash
# Check workflow executions
kubectl exec -n lair deployment/lair-n8n -- curl http://localhost:5678/api/v1/executions

# Monitor active executions
kubectl logs -n lair deployment/lair-n8n -f | grep -i execution

# Check worker status
kubectl logs -n lair deployment/lair-n8n-worker -f
```

#### **Performance Monitoring**
```bash
# N8N metrics endpoint
kubectl exec -n lair deployment/lair-n8n -- curl http://localhost:5678/metrics

# Queue status
kubectl exec -n lair deployment/lair-redis -- redis-cli info replication

# Database connections
kubectl exec -n lair statefulset/lair-postgresql -- psql -U n8n -d n8n -c "SELECT count(*) FROM pg_stat_activity WHERE datname='n8n';"
```

### 📝 **Logging & Debugging**

#### **Log Analysis**
```bash
# N8N main logs
kubectl logs -n lair deployment/lair-n8n | grep -E "(ERROR|WARN|workflow)"

# Worker logs
kubectl logs -n lair deployment/lair-n8n-worker | grep -E "(ERROR|WARN|execution)"

# Webhook logs
kubectl logs -n lair deployment/lair-n8n | grep webhook
```

#### **Debug Mode**
```yaml
# Enable debug logging
n8n:
  extraEnv:
    - name: N8N_LOG_LEVEL
      value: "debug"
    - name: N8N_LOG_OUTPUT
      value: "console"
```

### 🚨 **Health Checks**

#### **Application Health**
```bash
# N8N health check
kubectl exec -n lair deployment/lair-n8n -- curl -f http://localhost:5678/healthz

# Queue health check
kubectl exec -n lair deployment/lair-n8n -- curl -f http://localhost:5679/healthz

# Database connectivity
kubectl exec -n lair deployment/lair-n8n -- curl -f http://localhost:5678/api/v1/workflows
```

#### **Automated Health Monitoring**
```bash
# Create health check script
cat > n8n-health-check.sh << 'EOF'
#!/bin/bash
echo "=== N8N Health Check ==="

# Check main service
if kubectl exec -n lair deployment/lair-n8n -- curl -sf http://localhost:5678/healthz >/dev/null; then
    echo "✅ N8N Main: Healthy"
else
    echo "❌ N8N Main: Unhealthy"
fi

# Check workers
WORKER_COUNT=$(kubectl get pods -n lair -l app=n8n-worker --no-headers | wc -l)
READY_WORKERS=$(kubectl get pods -n lair -l app=n8n-worker --no-headers | grep Running | wc -l)
echo "🔧 Workers: $READY_WORKERS/$WORKER_COUNT ready"

# Check queue
QUEUE_SIZE=$(kubectl exec -n lair deployment/lair-redis -- redis-cli llen bull:n8n:waiting 2>/dev/null || echo "0")
echo "📋 Queue: $QUEUE_SIZE pending executions"
EOF

chmod +x n8n-health-check.sh
```

---

## 🚨 Troubleshooting

### 🔧 **Common Issues**

#### **Workflow Execution Failures**
```bash
# Symptom: Workflows fail to execute
# Check worker status
kubectl get pods -n lair -l app=n8n-worker

# Check Redis connection
kubectl exec -n lair deployment/lair-n8n -- curl http://localhost:5678/api/v1/executions

# Check database connectivity
kubectl exec -n lair deployment/lair-n8n -- nc -z lair-postgresql 5432

# Solution: Restart components
kubectl rollout restart deployment/lair-n8n -n lair
kubectl rollout restart deployment/lair-n8n-worker -n lair
```

#### **Webhook Authentication Issues**
```bash
# Symptom: Webhooks return 401/403 errors
# Check webhook configuration
kubectl logs -n lair deployment/lair-n8n | grep webhook

# Check ingress configuration
kubectl describe ingress -n lair lair-ingress

# Solution: Update webhook URLs
# Update workflows to use correct webhook URLs
# Ensure proper authentication headers
```

#### **Database Connection Problems**
```bash
# Symptom: N8N cannot connect to PostgreSQL
# Check database status
kubectl get pods -n lair -l app=postgresql

# Check connection string
kubectl exec -n lair deployment/lair-n8n -- env | grep DB_

# Test connection
kubectl exec -n lair deployment/lair-n8n -- nc -z lair-postgresql 5432

# Solution: Check credentials and network
kubectl get secret -n lair n8n-postgres-secret -o yaml
```

#### **Performance Issues**
```bash
# Symptom: Slow workflow execution
# Check resource usage
kubectl top pods -n lair -l app=n8n

# Check queue backlog
kubectl exec -n lair deployment/lair-redis -- redis-cli llen bull:n8n:waiting

# Scale workers
kubectl scale deployment lair-n8n-worker -n lair --replicas=4

# Optimize workflow timeouts
kubectl set env deployment/lair-n8n -n lair \
  EXECUTIONS_TIMEOUT=1800 \
  QUEUE_WORKER_TIMEOUT=600
```

### 🔄 **Recovery Procedures**

#### **Workflow Recovery**
```bash
# Export workflows (backup)
kubectl exec -n lair deployment/lair-n8n -- curl http://localhost:5678/api/v1/workflows > workflows-backup.json

# Import workflows (restore)
kubectl cp workflows-backup.json lair/lair-n8n-0:/tmp/
kubectl exec -n lair deployment/lair-n8n -- curl -X POST http://localhost:5678/api/v1/workflows -d @/tmp/workflows-backup.json
```

#### **Database Recovery**
```bash
# Backup N8N database
kubectl exec -n lair statefulset/lair-postgresql -- pg_dump -U n8n n8n > n8n-backup.sql

# Restore N8N database
kubectl exec -i -n lair statefulset/lair-postgresql -- psql -U n8n n8n < n8n-backup.sql
```

---

## 🔧 Advanced Configuration

### 🎛️ **Custom Nodes Development**

#### **Creating Custom Nodes**
```typescript
// Custom Ollama node example
import { INodeType, INodeTypeDescription } from 'n8n-workflow';

export class CustomOllama implements INodeType {
  description: INodeTypeDescription = {
    displayName: 'Custom Ollama',
    name: 'customOllama',
    group: ['ai'],
    version: 1,
    description: 'Custom Ollama integration',
    defaults: {
      name: 'Custom Ollama',
    },
    inputs: ['main'],
    outputs: ['main'],
    properties: [
      {
        displayName: 'Model',
        name: 'model',
        type: 'string',
        default: 'llama3.1:8b',
      },
      {
        displayName: 'Prompt',
        name: 'prompt',
        type: 'string',
        default: '',
      }
    ]
  };
}
```

### 🔌 **API Integration**

#### **REST API Usage**
```bash
# Create workflow via API
curl -X POST https://n8n.example.com/api/v1/workflows \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer your-api-key" \
  -d @workflow.json

# Execute workflow
curl -X POST https://n8n.example.com/api/v1/workflows/1/execute \
  -H "Authorization: Bearer your-api-key"

# Get execution results
curl https://n8n.example.com/api/v1/executions/123 \
  -H "Authorization: Bearer your-api-key"
```

#### **Webhook Security**
```yaml
# Secure webhook configuration
n8n:
  extraEnv:
    - name: N8N_WEBHOOK_TUNNEL_URL
      value: "https://n8n.example.com"
    - name: N8N_WEBHOOK_TIMEOUT
      value: "120"
    - name: N8N_WEBHOOK_WAIT_TIMEOUT
      value: "300"
```

---

## 🎯 Best Practices

### 🚀 **Performance Best Practices**
- **Worker Scaling**: Scale workers based on execution volume
- **Queue Management**: Monitor queue size and processing time
- **Resource Allocation**: Allocate sufficient CPU and memory
- **Database Optimization**: Regular database maintenance and indexing
- **Caching**: Use Redis for temporary data storage

### 🔒 **Security Best Practices**
- **Encryption**: Always use encryption keys for sensitive data
- **Access Control**: Implement proper user roles and permissions
- **Webhook Security**: Use authentication for webhook endpoints
- **Credential Management**: Store credentials securely in N8N vault
- **Network Security**: Restrict network access to necessary services

### 📊 **Operational Best Practices**
- **Monitoring**: Implement comprehensive monitoring and alerting
- **Backup**: Regular workflow and data backups
- **Version Control**: Use workflow versioning and change tracking
- **Documentation**: Document complex workflows and integrations
- **Testing**: Test workflows in staging before production deployment

---

**🎯 Ready to automate your processes?** Continue with [ComfyUI Image Generation](comfyui.md) or explore [MinIO Object Storage](minio.md)!
