# 🤖 OpenWebUI - AI Chat Interface

> **Complete guide to OpenWebUI configuration, features, and usage in Lair**

OpenWebUI is the primary user interface for AI interactions in Lair, providing a ChatGPT-like experience with advanced features like RAG (Retrieval Augmented Generation), document processing, and multi-user management.

---

## 🎯 Overview

OpenWebUI serves as the main entry point for users to interact with AI models through a modern web interface. It integrates seamlessly with Ollama for LLM serving and Tika for document processing.

### ✨ **Key Features**
- **🧠 AI Chat**: Natural language conversations with local LLMs
- **📚 RAG System**: Upload documents for context-aware responses
- **👥 Multi-User**: User management with roles and permissions
- **🔍 Web Search**: Integration with search engines for real-time information
- **🎨 Image Analysis**: OCR and image understanding capabilities
- **💬 Conversation Management**: Persistent chat history with search and organization
- **🔌 Plugin System**: Extensible architecture with custom plugins
- **🎛️ Model Management**: Switch between different LLMs dynamically
- **📱 Responsive Design**: Works on desktop, tablet, and mobile devices

### 🔗 **Integration Points**
- **Ollama**: LLM serving and model management
- **Tika**: Document text extraction and processing
- **PostgreSQL**: User data and conversation storage
- **MinIO**: **Primary file storage backend** (automatic S3 storage when MinIO is enabled)

---

## 🚀 Getting Started

> **✨ Note**: When MinIO is enabled during Lair installation, **OpenWebUI automatically uses it as the storage backend** instead of local filesystem. This provides better scalability, performance, and no size limitations for file uploads and RAG documents.

### 🌐 **Accessing OpenWebUI**

#### **Default Access URLs**
```bash
# LAN Access (.local domains)
https://ai.hostname.local

# Public Access (internet domains)
https://ai.example.com

# Internal Kubernetes Access
http://lair-openwebui.lair.svc.cluster.local:8080
```

#### **First-Time Setup**
1. **Navigate to OpenWebUI URL**
2. **Create Admin Account**: First user becomes administrator
3. **Configure Models**: Add Ollama models for AI conversations
4. **Upload Documents**: Add knowledge base documents for RAG
5. **Invite Users**: Create additional user accounts

### 👤 **User Management**

#### **Admin Account Creation**
```bash
# First user registration automatically becomes admin
# Navigate to: https://ai.hostname.local
# Click "Sign up" and create your account
```

#### **User Roles**
- **Admin**: Full system access, user management, model configuration
- **User**: Standard chat access, document upload, personal settings
- **Pending**: New users awaiting admin approval (if signup disabled)

#### **User Configuration**
```yaml
# In values-config.yaml
openWebUI:
  auth:
    enableSignup: true          # Allow new user registration
    defaultUserRole: "pending"  # New users need admin approval
    userPermissions:
      chatDeletion: true        # Allow users to delete their chats
```

---

## 🧠 AI Chat Features

### 💬 **Basic Chat Interface**

#### **Starting Conversations**
1. **Select Model**: Choose from available Ollama models
2. **Type Message**: Enter your question or prompt
3. **Send**: Click send or press Enter
4. **Stream Response**: Watch AI response generate in real-time

#### **Chat Management**
```bash
# Features available in chat interface:
- 💾 Save conversations with custom titles
- 🔍 Search chat history
- 📁 Organize chats in folders
- 🗑️ Delete individual messages or entire chats
- 📤 Export conversations (JSON, Markdown)
- 🔗 Share conversations with other users
```

### 🎛️ **Model Management**

#### **Available Models**
OpenWebUI automatically detects models available in Ollama:

```bash
# Check available models via Ollama API
curl http://lair-ollama:11434/api/tags

# Common models in Lair:
- llama3.1:8b      # General purpose, fast
- llama3.1:70b     # High quality, slower
- codellama:13b    # Code generation
- mistral:7b       # Efficient general model
- phi3:mini        # Lightweight model
```

#### **Model Selection**
```bash
# In chat interface:
1. Click model dropdown (top of chat)
2. Select desired model
3. Model loads automatically for next message
4. Different chats can use different models
```

#### **Model Configuration**
```yaml
# Advanced model settings in OpenWebUI
models:
  filterList: ""  # Comma-separated list of allowed models (empty = all)
  
# Example: Restrict to specific models
models:
  filterList: "llama3.1:8b,mistral:7b,codellama:13b"
```

### 🎨 **Advanced Chat Features**

#### **System Prompts**
```bash
# Create custom system prompts:
1. Go to Settings → Prompts
2. Click "Create Prompt"
3. Define system behavior
4. Apply to conversations

# Example system prompt:
"You are a helpful AI assistant specialized in software development. 
Always provide code examples and explain your reasoning step by step."
```

#### **Temperature & Parameters**
```bash
# Adjust model behavior:
- Temperature: 0.1 (focused) to 1.0 (creative)
- Top-p: Nucleus sampling parameter
- Max tokens: Maximum response length
- Repeat penalty: Avoid repetitive responses
```

---

## 📚 RAG (Retrieval Augmented Generation)

### 🎯 **Overview**
RAG allows OpenWebUI to use uploaded documents as context for AI responses, enabling the AI to answer questions based on your specific knowledge base.

### 📄 **Document Processing**

#### **Supported Formats**
```bash
# Supported document types:
- PDF files (.pdf)
- Microsoft Word (.docx, .doc)
- Plain text (.txt)
- Markdown (.md)
- HTML files (.html)
- Rich Text Format (.rtf)
- OpenDocument Text (.odt)
- PowerPoint (.pptx, .ppt)
- Excel (.xlsx, .xls)
```

#### **Upload Process**
```bash
# Document upload workflow:
1. Click 📎 attachment icon in chat
2. Select "Upload Document"
3. Choose file(s) from computer
4. Wait for processing (Tika extraction)
5. Document appears in knowledge base
6. Use #document_name to reference in chat
```

#### **Processing Pipeline**
```
Document Upload → Tika Extraction → Text Chunking → Embedding Generation → Vector Storage
       ↓               ↓              ↓               ↓                ↓
   File Upload → Text Content → 1000 token chunks → AI Embeddings → PostgreSQL (pgvector)
```

### 🔍 **RAG Configuration**

#### **Default Settings**
```yaml
# Optimized RAG configuration in values.yaml
openWebUI:
  rag:
    contentExtractionEngine: "tika"    # Uses Apache Tika
    enableHybridSearch: true           # Combines dense + sparse search
    textSplitter: "token"              # Token-based chunking
    chunkSize: 1000                    # Tokens per chunk
    chunkOverlap: 200                  # Overlap between chunks
    topK: 5                            # Number of relevant chunks
    pdfExtractImages: true             # OCR for images in PDFs
```

#### **Advanced RAG Settings**
```bash
# Access via Settings → Documents → RAG
- Chunk Size: 500-2000 tokens (1000 recommended)
- Chunk Overlap: 100-300 tokens (200 recommended)
- Top K: 3-10 results (5 recommended)
- Similarity Threshold: 0.1-0.9 (0.3 recommended)
- Hybrid Search: Enabled (combines semantic + keyword search)
```

### 💡 **Using RAG in Conversations**

#### **Document References**
```bash
# Reference specific documents in chat:
"Based on the #project_requirements document, what are the key features?"

# Search across all documents:
"What does our documentation say about security requirements?"

# Combine with specific instructions:
"Using the #api_documentation, write a Python example for user authentication"
```

#### **RAG Quality Tips**
```bash
# Best practices for RAG:
1. 📝 Use clear, well-structured documents
2. 🏷️ Give documents descriptive names
3. 📊 Upload related documents together
4. 🔍 Use specific questions for better results
5. 📚 Organize documents by topic/project
```

---

## 🔍 Web Search Integration

### 🌐 **Search Engines**
OpenWebUI can integrate with web search engines for real-time information:

```bash
# Supported search engines:
- DuckDuckGo (privacy-focused)
- Google Search (requires API key)
- Bing Search (requires API key)
- Searx (self-hosted search)
```

### ⚙️ **Search Configuration**
```bash
# Enable web search:
1. Go to Settings → Web Search
2. Select search engine
3. Add API keys (if required)
4. Enable search in conversations

# Usage in chat:
"Search for the latest news about Kubernetes 1.30"
"What's the current weather in New York?"
```

---

## 🎨 Image & Multimodal Features

### 📸 **Image Upload & Analysis**
```bash
# Image processing capabilities:
- 🖼️ Image upload and display
- 🔍 OCR text extraction
- 🧠 Image understanding with multimodal models
- 📊 Chart and diagram analysis
- 🎨 Image generation requests (via ComfyUI integration)
```

### 🤖 **Multimodal Models**
```bash
# Models with vision capabilities:
- llava:7b         # Image understanding
- llava:13b        # Higher quality vision
- bakllava:7b      # Efficient vision model

# Usage:
1. Upload image in chat
2. Select vision-capable model
3. Ask questions about the image
```

---

## 🔊 Audio Features

### 🎤 **Speech-to-Text (STT)**
```yaml
# Audio configuration in values.yaml
openWebUI:
  audio:
    whisperModel: "turbo"    # Whisper model for STT
    vadFilter: true          # Voice activity detection
    autoUpdate: false        # Auto-update models
    sttEngine: "whisper"     # Speech-to-text engine
```

### 🔊 **Text-to-Speech (TTS)**
```yaml
# TTS configuration
openWebUI:
  audio:
    ttsEngine: "openai"      # Text-to-speech engine
    # Options: openai, elevenlabs, edge-tts
```

### 🎵 **Usage**
```bash
# Speech features:
- 🎤 Click microphone to record voice messages
- 🔊 Click speaker icon to hear AI responses
- ⚙️ Configure voice settings in user preferences
- 🌍 Multiple language support
```

---

## 🔌 Plugin System

### 📦 **Available Plugins**
```bash
# Plugin categories:
- 🔍 Search plugins (web search, document search)
- 🧮 Calculation plugins (math, unit conversion)
- 🌐 API integrations (weather, news, social media)
- 🛠️ Development tools (code execution, git integration)
- 📊 Data analysis (CSV processing, chart generation)
```

### ⚙️ **Plugin Management**
```bash
# Plugin configuration:
1. Go to Settings → Plugins
2. Browse available plugins
3. Install desired plugins
4. Configure plugin settings
5. Use plugins in conversations with /command syntax
```

### 🔧 **Custom Plugin Development**
```python
# Example plugin structure:
class WeatherPlugin:
    def __init__(self):
        self.name = "weather"
        self.description = "Get weather information"
    
    def execute(self, location):
        # Plugin logic here
        return f"Weather in {location}: Sunny, 25°C"
```

---

## 🔐 Authentication & Security

### 🔑 **Authentication Methods**

#### **Built-in Authentication**
```yaml
# Default authentication (username/password)
openWebUI:
  auth:
    enabled: true
    secretName: openwebui-auth
    secretKey: "" # Leave empty to automatically generate a random 32-character key
```

#### **Single Sign-On (SSO)**
```yaml
# SSO configuration
openWebUI:
  sso:
    enabled: true
    provider: "google"  # Options: google, microsoft, github, oidc
    enableLoginForm: false      # Hide local login
    enableLocalSignup: false    # Disable local registration
```

#### **SSO Providers**

##### **Google OAuth**
```yaml
openWebUI:
  sso:
    provider: "google"
    google:
      clientId: "your-google-client-id"
      clientSecret: "your-google-client-secret"
      redirectUri: "https://ai.example.com/oauth/google/callback"
```

##### **Microsoft Azure AD**
```yaml
openWebUI:
  sso:
    provider: "microsoft"
    microsoft:
      clientId: "your-azure-client-id"
      clientSecret: "your-azure-client-secret"
      tenantId: "your-tenant-id"
      redirectUri: "https://ai.example.com/oauth/microsoft/callback"
```

##### **GitHub OAuth**
```yaml
openWebUI:
  sso:
    provider: "github"
    github:
      clientId: "your-github-client-id"
      clientSecret: "your-github-client-secret"
```

##### **Generic OIDC**
```yaml
openWebUI:
  sso:
    provider: "oidc"
    oauth:
      clientId: "your-oidc-client-id"
      clientSecret: "your-oidc-client-secret"
      providerName: "Custom SSO"
      scopes: "openid email profile"
      providerUrl: "https://your-oidc-provider.com"
      redirectUri: "https://ai.example.com/oauth/oidc/callback"
```

### 🛡️ **Security Features**
```bash
# Security capabilities:
- 🔐 Encrypted password storage
- 🍪 Secure session management
- 🔒 HTTPS enforcement
- 👥 Role-based access control
- 📝 Audit logging
- 🚫 Rate limiting
- 🛡️ CSRF protection
```

---

## ⚙️ Configuration & Customization

### 🎨 **UI Customization**
```bash
# Customization options:
- 🎨 Theme selection (light/dark/auto)
- 🌍 Language selection (50+ languages)
- 📱 Mobile-responsive design
- 🖼️ Custom branding/logos
- 🎛️ Layout preferences
```

### 📊 **Performance Configuration**
```yaml
# Resource optimization
openWebUI:
  resources:
    limits:
      memory: 4Gi      # Increase for large document processing
      cpu: 2000m       # Increase for concurrent users
    requests:
      memory: 1Gi      # Guaranteed memory
      cpu: 500m        # Guaranteed CPU
```

### 💾 **Storage Configuration**

#### **Storage Backends**
OpenWebUI supports two storage backends:

1. **Local Filesystem** (default when MinIO is disabled)
   - Files stored on persistent volume (PVC)
   - Simple setup, no external dependencies
   - Limited by PVC size

2. **S3/MinIO Storage** (automatic when MinIO is enabled)
   - Scalable object storage
   - Better performance for large files
   - No size limitations (depends on MinIO capacity)
   - **Automatically configured** when MinIO is enabled

#### **Local Filesystem Storage**
```yaml
# Default configuration (when MinIO is disabled)
openWebUI:
  persistence:
    enabled: true
    size: 20Gi                    # Storage size for PVC
    enablePersistentConfig: true  # Persist configuration changes
```

#### **S3/MinIO Storage (Automatic)**
```yaml
# Automatic configuration when MinIO is enabled
minio:
  enabled: true                   # Enable MinIO
  accessKey: "minio"              # S3 access credentials
  secretKey: "minio123"           # S3 secret credentials
  storage:
    size: 50Gi                    # MinIO storage capacity

openWebUI:
  s3:
    enabled: true                 # Auto-enabled when minio.enabled: true
    bucketName: "openwebui-storage"  # S3 bucket name (auto-created)
    region: "us-east-1"           # MinIO default region
    addressingStyle: "path"       # Path-style addressing for MinIO

# Environment variables (automatically configured):
# STORAGE_PROVIDER: "s3"
# S3_ENDPOINT_URL: "http://lair-minio.lair.svc.cluster.local:9000"
# S3_BUCKET_NAME: "openwebui-storage"
# AWS_ACCESS_KEY_ID: "<from MinIO config>"
# AWS_SECRET_ACCESS_KEY: "<from MinIO config>"
```

#### **Storage Migration**
```bash
# Migrate from local filesystem to MinIO:

# 1. Backup current data
kubectl cp lair/lair-openwebui-xxx:/app/backend/data ./openwebui-backup

# 2. Enable MinIO in values-config.yaml
# minio:
#   enabled: true

# 3. Upgrade deployment
helm upgrade --install lair . -n lair -f values-config.yaml
 

# 4. (Optional) Migrate existing files to MinIO
kubectl exec -n lair deployment/lair-openwebui -- mc mirror /app/backend/data minio/openwebui-storage
```

#### **Storage Features**
```bash
# When using MinIO storage:
✅ Automatic bucket creation
✅ Automatic credential configuration
✅ Better concurrent access performance
✅ No PVC size limitations
✅ Centralized backup with MinIO
✅ Version control support
✅ Scalable storage capacity
```

### 🔧 **Advanced Settings**
```yaml
# Advanced OpenWebUI configuration
openWebUI:
  # Base URL configuration
  baseUrl: ""  # Auto-detected if empty
  
  # Admin configuration
  admin:
    email: "admin@example.com"  # Admin notifications
  
  # Model filtering
  models:
    filterList: ""  # Restrict available models
  
  # Feature toggles
  features:
    enableCommunitySharing: true   # Share with community
    enableMessageRating: true     # Rate AI responses
```

---

## 🔍 Monitoring & Troubleshooting

### 📊 **Health Monitoring**
```bash
# Check OpenWebUI status
kubectl get pods -n lair -l app=openwebui

# Check service connectivity
kubectl exec -n lair deployment/lair-openwebui -- curl localhost:8080/health

# View logs
kubectl logs -n lair deployment/lair-openwebui -f
```

### 🚨 **Common Issues**

#### **Login Problems**
```bash
# Issue: Cannot login or create account
# Check authentication configuration
kubectl get secret -n lair openwebui-auth
kubectl describe pod -n lair -l app=openwebui

# Solution: Reset admin password
kubectl exec -n lair deployment/lair-openwebui -- python manage.py reset-admin
```

#### **Model Not Available**
```bash
# Issue: Models not showing in dropdown
# Check Ollama connectivity
kubectl exec -n lair deployment/lair-openwebui -- curl lair-ollama:11434/api/tags

# Check Ollama service
kubectl get services -n lair lair-ollama
kubectl logs -n lair statefulset/lair-ollama
```

#### **Document Upload Fails**
```bash
# Issue: Cannot upload or process documents
# Check Tika connectivity
kubectl exec -n lair deployment/lair-openwebui -- curl lair-tika:9998

# Check storage backend
kubectl exec -n lair deployment/lair-openwebui -- env | grep STORAGE_PROVIDER

# For local filesystem storage:
kubectl get pvc -n lair openwebui-pvc
kubectl exec -n lair deployment/lair-openwebui -- df -h

# For MinIO/S3 storage:
kubectl exec -n lair deployment/lair-openwebui -- curl http://lair-minio:9000
kubectl exec -n lair deployment/lair-minio -- mc ls minio/openwebui-storage
```

#### **MinIO Storage Issues**
```bash
# Issue: Files not uploading to MinIO
# Check S3 configuration
kubectl exec -n lair deployment/lair-openwebui -- env | grep -E "S3_|AWS_"

# Verify MinIO connectivity
kubectl exec -n lair deployment/lair-openwebui -- curl -v http://lair-minio:9000

# Check bucket exists
kubectl exec -n lair deployment/lair-minio -- mc ls minio/ | grep openwebui-storage

# View bucket creation logs
kubectl logs -n lair deployment/lair-openwebui -c minio-bucket-setup

# Recreate bucket manually if needed
kubectl exec -n lair deployment/lair-minio -- mc mb minio/openwebui-storage

# Test S3 credentials
kubectl exec -n lair deployment/lair-minio -- mc alias set test \
  http://localhost:9000 \
  $(kubectl get configmap -n lair services-config -o jsonpath='{.data.MINIO_ACCESS_KEY}') \
  $(kubectl get configmap -n lair services-config -o jsonpath='{.data.MINIO_SECRET_KEY}')
```

#### **Performance Issues**
```bash
# Issue: Slow response times
# Check resource usage
kubectl top pods -n lair -l app=openwebui

# Check database performance
kubectl exec -n lair statefulset/lair-postgresql -- psql -U postgres -c "SELECT * FROM pg_stat_activity;"

# Increase resources if needed
kubectl patch deployment lair-openwebui -n lair -p '{"spec":{"template":{"spec":{"containers":[{"name":"openwebui","resources":{"limits":{"memory":"4Gi","cpu":"2000m"}}}]}}}}'
```

---

## 🔧 API Integration

### 🌐 **OpenWebUI API**
```bash
# API endpoints available:
GET  /api/v1/auths/signin     # User authentication
GET  /api/v1/chats            # List conversations
POST /api/v1/chats            # Create conversation
GET  /api/v1/models           # List available models
POST /api/v1/generate         # Generate AI response
```

### 📝 **API Usage Examples**
```python
# Python example: Create chat completion
import requests

# Authentication
auth_response = requests.post("https://ai.example.com/api/v1/auths/signin", 
    json={"email": "user@example.com", "password": "password"})
token = auth_response.json()["token"]

# Generate response
response = requests.post("https://ai.example.com/api/v1/generate",
    headers={"Authorization": f"Bearer {token}"},
    json={
        "model": "llama3.1:8b",
        "messages": [{"role": "user", "content": "Hello, how are you?"}],
        "stream": False
    })

print(response.json()["message"]["content"])
```

### 🔌 **Integration with N8N**
```javascript
// N8N workflow node example
{
  "nodes": [
    {
      "name": "OpenWebUI Chat",
      "type": "n8n-nodes-base.httpRequest",
      "parameters": {
        "url": "http://lair-openwebui:8080/api/v1/generate",
        "method": "POST",
        "headers": {
          "Authorization": "Bearer {{$node.Auth.json.token}}"
        },
        "body": {
          "model": "llama3.1:8b",
          "messages": [{"role": "user", "content": "{{$json.question}}"}]
        }
      }
    }
  ]
}
```

---

## 🔄 Updates & Maintenance

### 📦 **Version Updates**
```bash
# Check current version
kubectl get deployment lair-openwebui -n lair -o jsonpath='{.spec.template.spec.containers[0].image}'

# Update to latest version
helm upgrade --install lair . -n lair -f values-config.yaml --set openWebUI.image.tag=latest

# Verify update
kubectl rollout status deployment/lair-openwebui -n lair
```

### 🧹 **Maintenance Tasks**
```bash
# Clean up old conversations (if needed)
kubectl exec -n lair deployment/lair-openwebui -- python manage.py cleanup-chats --days 90

# Optimize database
kubectl exec -n lair statefulset/lair-postgresql -- psql -U postgres -d openwebui -c "VACUUM ANALYZE;"

# Clear cache
kubectl exec -n lair deployment/lair-openwebui -- python manage.py clear-cache
```

### 💾 **Backup & Restore**
```bash
# Backup user data and conversations
kubectl exec -n lair statefulset/lair-postgresql -- pg_dump -U postgres openwebui > openwebui-backup.sql

# Backup uploaded documents
kubectl cp lair/lair-openwebui-xxx:/app/backend/data ./openwebui-data-backup

# Restore from backup
kubectl exec -n lair statefulset/lair-postgresql -- psql -U postgres openwebui < openwebui-backup.sql
kubectl cp ./openwebui-data-backup lair/lair-openwebui-xxx:/app/backend/data
```

---

## 🎯 Best Practices

### 👥 **User Management**
- **Create admin account immediately** after deployment
- **Disable public signup** in production environments
- **Use SSO** for enterprise deployments
- **Regular user audit** and cleanup of inactive accounts

### 📚 **Document Management**
- **Organize documents by project/topic**
- **Use descriptive filenames**
- **Regular cleanup** of outdated documents
- **Monitor storage usage** and increase if needed

### 🔒 **Security**
- **Enable HTTPS** for all access modes
- **Use strong authentication** (SSO preferred)
- **Regular security updates**
- **Monitor access logs** for suspicious activity

### 🚀 **Performance**
- **Monitor resource usage** and scale as needed
- **Optimize document chunking** for your use case
- **Use appropriate models** for different tasks
- **Regular database maintenance**

---

**🎯 Ready to explore more?** Check out [N8N Workflow Integration](n8n.md) or [Ollama Model Management](ollama.md)!
