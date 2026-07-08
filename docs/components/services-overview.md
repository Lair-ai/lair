# 🧩 Lair Applications Overview

> **Complete guide to all applications and services in the Lair ecosystem**

Lair deploys a comprehensive suite of applications that work together to provide a complete AI infrastructure and process automation platform. Each component serves a specific purpose while integrating seamlessly with others.

---

## 🎯 Application Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    🌐 USER INTERFACES                           │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐ │
│  │   OpenWebUI     │  │      N8N        │  │    ComfyUI      │ │
│  │  (AI Chat)      │  │  (Automation)   │  │ (AI Images)     │ │
│  │ Port: 8080      │  │  Port: 5678     │  │ Port: 8188      │ │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                                │
┌─────────────────────────────────────────────────────────────────┐
│                   🤖 AI & PROCESSING                            │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐ │
│  │     Ollama      │  │      Tika       │  │     MinIO       │ │
│  │   (LLM API)     │  │ (Doc Parser)    │  │  (S3 Storage)   │ │
│  │ Port: 11434     │  │ Port: 9998      │  │ Port: 9000/9001 │ │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                                │
┌─────────────────────────────────────────────────────────────────┐
│                   💾 DATA LAYER                                │
│  ┌─────────────────┐  ┌─────────────────┐                     │
│  │   PostgreSQL    │  │      Redis      │                     │
│  │   (Database)    │  │ (Cache/Queue)   │                     │
│  │ Port: 5432      │  │ Port: 6379      │                     │
│  └─────────────────┘  └─────────────────┘                     │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🎨 User Interface Applications

### 🤖 **OpenWebUI** - AI Chat Interface
> **Private ChatGPT-like interface with advanced RAG capabilities**

**Purpose**: Primary user interface for AI interactions
- **🧠 AI Chat**: Natural language conversations with local LLMs
- **📚 RAG (Retrieval Augmented Generation)**: Upload documents for context-aware responses
- **🔍 Web Search**: Integration with search engines for real-time information
- **👥 Multi-User**: User management with roles and permissions
- **🔌 Plugin System**: Extensible with custom plugins and integrations

**Key Features**:
- **Document Processing**: PDF, DOCX, TXT upload with Tika integration
- **Image Analysis**: OCR and image understanding capabilities
- **Code Generation**: Programming assistance with syntax highlighting
- **Model Management**: Switch between different LLMs dynamically
- **Conversation History**: Persistent chat history with search
- **API Integration**: RESTful API for custom integrations

**Default Access**:
- **LAN**: `https://ai.hostname.local`
- **Public**: `https://ai.example.com`
- **Internal**: `lair-openwebui.lair.svc.cluster.local:8080`

**Configuration Highlights**:
```yaml
openWebUI:
  # RAG Configuration with Tika
  rag:
    contentExtractionEngine: "tika"
    enableHybridSearch: true
    chunkSize: 1000
    chunkOverlap: 200
    topK: 5
    pdfExtractImages: true
  
  # Audio Configuration
  audio:
    whisperModel: "turbo"
    sttEngine: "whisper"
    ttsEngine: "openai"
  
  # Authentication
  auth:
    enableSignup: true
    defaultUserRole: "pending"
```

---

### ⚡ **N8N** - Workflow Automation Platform
> **Visual workflow automation with 400+ integrations**

**Purpose**: Business process automation and API orchestration
- **🔄 Visual Workflows**: Drag-and-drop workflow designer
- **🔌 400+ Integrations**: Connect to APIs, databases, cloud services
- **⚡ Event-Driven**: Trigger workflows from webhooks, schedules, file changes
- **🔀 Data Processing**: Transform, filter, and route data between systems
- **👥 Multi-Tenant**: Separate workflows per user/team

**Key Features**:
- **AI Integration**: Connect OpenWebUI and Ollama for automated AI workflows
- **Database Operations**: Direct PostgreSQL integration for data workflows
- **File Processing**: Automated document processing with Tika
- **API Orchestration**: Chain multiple API calls with error handling
- **Scheduling**: Cron-based and interval scheduling
- **Monitoring**: Workflow execution history and error tracking

**Default Access**:
- **LAN**: `https://n8n.hostname.local`
- **Public**: `https://n8n.example.com`
- **Internal**: `lair-n8n.lair.svc.cluster.local:5678`

**Architecture**:
```yaml
n8n:
  # Main N8N instance
  replicas: 1
  
  # Worker configuration for queue processing
  worker:
    enabled: true
    replicas: 2  # Automatically calculated based on resources
    
  # Database integration
  database:
    type: postgresdb  # Uses shared PostgreSQL instance
    
  # Queue system
  queue:
    backend: redis  # Uses shared Redis instance
```

---

### 🎨 **ComfyUI** - AI Image Generation
> **Advanced AI image generation with node-based workflows**

**Purpose**: AI-powered image generation and manipulation
- **🎨 Image Generation**: Text-to-image, image-to-image workflows
- **🔧 Node-Based**: Visual programming for complex AI pipelines
- **🤖 Model Support**: Stable Diffusion, ControlNet, LoRA models
- **⚡ GPU Acceleration**: Optimized for NVIDIA GPUs and Tegra
- **📁 Model Management**: Automatic model downloading and caching

**Key Features**:
- **Workflow Templates**: Pre-built workflows for common tasks
- **Custom Models**: Support for custom trained models
- **Batch Processing**: Generate multiple images efficiently
- **API Integration**: RESTful API for programmatic access
- **Memory Optimization**: Efficient VRAM usage with model offloading

**Default Access**:
- **LAN**: `https://images.hostname.local`
- **Public**: `https://images.example.com`
- **Internal**: `lair-comfyui.lair.svc.cluster.local:8188`

**Platform Optimization**:
```yaml
comfyUI:
  enabled: false  # Disabled by default, enabled based on resources
  gpuEnabled: true  # Auto-detected
  
  # Jetson-specific optimization
  image:
    repository: dustynv/comfyui  # ARM64 optimized image
    tag: r36.3.0
    
  # Memory optimization
  lowVram: true  # For memory-constrained environments
```

---

## 🤖 AI & Processing Services

### 🧠 **Ollama** - Local LLM Serving Platform
> **High-performance local LLM serving with GPU acceleration**

**Purpose**: Serve large language models locally with optimal performance
- **🚀 High Performance**: Optimized inference engine for local deployment
- **🎯 Model Management**: Easy model installation and switching
- **⚡ GPU Acceleration**: NVIDIA GPU and Tegra support
- **🔌 OpenAI-Compatible API**: Drop-in replacement for OpenAI API
- **📊 Resource Management**: Intelligent memory and compute allocation

**Supported Models**:
- **General Purpose**: Llama 3.1, Llama 3.2, Mistral, Gemma
- **Code Generation**: CodeLlama, DeepSeek Coder, Starcoder
- **Specialized**: Phi-3, Qwen, Vicuna, Orca
- **Multimodal**: LLaVA (vision + language)

**Default Access**:
- **Internal API**: `lair-ollama.lair.svc.cluster.local:11434`
- **Public API**: `https://api.example.com` (if configured)

**Performance Configuration**:
```yaml
ollama:
  gpuEnabled: true  # Auto-detected
  vramPercentage: 80  # GPU memory allocation
  
  performances:
    numParallel: 2  # Concurrent requests
    maxQueue: 256   # Request queue size
    keepAlive: 300  # Model keep-alive time
    maxLoadedModels: 1  # Memory optimization
    kvCacheType: "q8_0"  # Memory-efficient caching
```

---

### 📄 **Tika** - Document Processing Engine
> **Apache Tika for comprehensive document text extraction**

**Purpose**: Extract text and metadata from various document formats
- **📁 Format Support**: PDF, DOCX, XLSX, PPTX, HTML, RTF, and 1000+ formats
- **🔍 OCR Integration**: Tesseract OCR for image-based text extraction
- **📊 Metadata Extraction**: Author, creation date, document properties
- **🌐 Language Detection**: Automatic language identification
- **⚡ High Performance**: Optimized for batch processing

**Integration Points**:
- **OpenWebUI RAG**: Primary document processor for knowledge base
- **N8N Workflows**: Automated document processing pipelines
- **API Access**: RESTful API for custom integrations

**Default Access**:
- **Internal API**: `lair-tika.lair.svc.cluster.local:9998`

**Configuration**:
```yaml
tika:
  image:
    tag: latest-full  # Includes OCR support with Tesseract
  
  resources:
    limits:
      memory: 1Gi
      cpu: 500m
```

---

### 💾 **MinIO** - S3-Compatible Object Storage
> **High-performance object storage with S3 API compatibility**

**Purpose**: Scalable object storage for files, models, and data
- **🔌 S3 API**: Full Amazon S3 API compatibility
- **🌐 Web Console**: Browser-based management interface
- **🔐 Access Control**: Bucket policies and user management
- **📊 Monitoring**: Built-in metrics and health monitoring
- **⚡ High Performance**: Optimized for throughput and latency

**Use Cases**:
- **Model Storage**: AI model files and checkpoints
- **Document Storage**: RAG document repository
- **Backup Storage**: Application data backups
- **Media Storage**: Images, videos, and multimedia content
- **Data Lake**: Structured and unstructured data storage

**Default Access**:
- **LAN Console**: `https://storage.hostname.local`
- **Public Console**: `https://storage.example.com`
- **S3 API**: `lair-minio.lair.svc.cluster.local:9000`
- **Console**: `lair-minio.lair.svc.cluster.local:9001`

**Configuration**:
```yaml
minio:
  enabled: true  # Enabled by default
  
  # Administrative credentials
  rootUser: minioadmin
  rootPassword: minioadmin
  
  # S3 API credentials
  accessKey: minio
  secretKey: minio123
  
  storage:
    size: 20Gi  # Automatically calculated
```

---

## 💾 Data Layer Services

### 🗄️ **PostgreSQL** - Primary Database
> **Robust relational database with pgvector for AI embeddings**

**Purpose**: Primary data storage for all applications
- **🧠 pgvector Extension**: Vector embeddings for AI/ML workloads
- **🔒 ACID Compliance**: Reliable transactional data storage
- **📊 Performance**: Optimized for concurrent access
- **🔄 Replication**: Built-in backup and recovery capabilities
- **🔌 Multi-App**: Shared by N8N, OpenWebUI, and other services

**Database Structure**:
```sql
-- N8N workflow data
n8n_db
├── executions        -- Workflow execution history
├── workflows         -- Workflow definitions
├── credentials       -- Encrypted API credentials
└── settings          -- System configuration

-- OpenWebUI data  
openwebui_db
├── users            -- User accounts and profiles
├── chats            -- Conversation history
├── documents        -- RAG document metadata
├── embeddings       -- Vector embeddings (pgvector)
└── models           -- Model configurations
```

**Default Access**:
- **Internal**: `lair-postgresql.lair.svc.cluster.local:5432`

**Configuration**:
```yaml
postgres:
  image:
    repository: ankane/pgvector  # PostgreSQL with vector extension
    tag: v0.5.1

  # Password is stored in Kubernetes Secret n8n-postgres-secret.
  user: n8n
  database: n8n
  
  persistence:
    size: 5Gi  # Automatically calculated
```

---

### ⚡ **Redis** - Cache & Queue System
> **High-performance in-memory data structure store**

**Purpose**: Caching, session storage, and message queuing
- **⚡ High Performance**: In-memory operations with microsecond latency
- **🔄 Queue System**: Message queuing for N8N workers
- **💾 Session Storage**: User session management
- **📊 Caching**: Application data caching for performance
- **🔒 Persistence**: Optional data persistence to disk

**Use Cases**:
- **N8N Queue**: Workflow execution queue management
- **OpenWebUI Cache**: Chat history and model response caching
- **Session Management**: User authentication sessions
- **Rate Limiting**: API rate limiting and throttling

**Default Access**:
- **Internal**: `lair-redis.lair.svc.cluster.local:6379`

**Configuration**:
```yaml
redis:
  image:
    repository: redis
    tag: 7.4.3
    
  persistence:
    enabled: true
    size: 5Gi
    
  resources:
    limits:
      memory: 512Mi
      cpu: 500m
```

---

## 🔗 Application Integration

### 🌐 **Service Communication**
```
OpenWebUI ←→ Ollama (LLM API calls)
    ↓
OpenWebUI ←→ Tika (document processing)
    ↓
OpenWebUI ←→ PostgreSQL (user data, embeddings)
    ↓
N8N ←→ All Services (workflow automation)
    ↓
N8N ←→ Redis (queue management)
    ↓
All Apps ←→ MinIO (file storage)
```

### 🔌 **API Integration Points**

#### **OpenWebUI → Ollama**
```bash
# LLM API calls
POST http://lair-ollama:11434/api/generate
{
  "model": "llama3.1",
  "prompt": "User question here",
  "stream": true
}
```

#### **OpenWebUI → Tika**
```bash
# Document processing
PUT http://lair-tika:9998/tika
Content-Type: application/pdf
[PDF file content]

# Response: Extracted text
```

#### **N8N → All Services**
```javascript
// N8N workflow nodes can connect to:
- HTTP Request: Any service API
- PostgreSQL: Direct database operations
- Redis: Cache and queue operations
- Webhook: Trigger workflows from external systems
```

### 📊 **Data Flow Examples**

#### **RAG Document Processing**
```
1. User uploads PDF to OpenWebUI
2. OpenWebUI → Tika: Extract text from PDF
3. OpenWebUI → Ollama: Generate embeddings
4. OpenWebUI → PostgreSQL: Store text + embeddings
5. User asks question
6. OpenWebUI → PostgreSQL: Search similar embeddings
7. OpenWebUI → Ollama: Generate response with context
```

#### **Automated Workflow**
```
1. N8N webhook receives data
2. N8N → Tika: Process attached documents
3. N8N → Ollama: Analyze content with AI
4. N8N → PostgreSQL: Store results
5. N8N → MinIO: Archive processed files
6. N8N → External API: Send notifications
```

---

## 🔧 Resource Management

### 📊 **Resource Allocation Strategy**

| Application | CPU % | Memory % | Storage Priority | GPU Usage |
|-------------|-------|----------|------------------|-----------|
| **Ollama** | 35% | 35% | High (models) | Primary |
| **OpenWebUI** | 25% | 25% | Medium (docs) | Optional |
| **ComfyUI** | 20% | 20% | Medium (models) | Primary |
| **N8N + Workers** | 10% | 15% | Low (workflows) | None |
| **PostgreSQL** | 5% | 5% | High (data) | None |
| **Redis** | 3% | 3% | Low (cache) | None |
| **MinIO** | 7% | 7% | High (objects) | None |
| **Tika** | 2% | 2% | None | None |

### 🎯 **Performance Optimization**

#### **Memory Management**
```yaml
# Overcommitment strategy with burst limits
requests: 50% of limits  # Guaranteed resources
limits: 3-6x requests   # Burst capacity when available

# Example: OpenWebUI
resources:
  requests: { memory: 1Gi, cpu: 500m }   # Guaranteed
  limits: { memory: 4Gi, cpu: 2000m }    # Burst up to 4x
```

#### **Storage Optimization**
```yaml
# Platform-specific storage classes
standard: longhorn      # Distributed, replicated
jetson: hostpath       # Local, optimized for SD cards

# Automatic sizing based on available storage
total_storage * 0.8 = usable_storage
usable_storage * allocation_% = component_storage
```

#### **GPU Allocation**
```yaml
# Automatic GPU detection and allocation
ollama:
  gpuEnabled: true      # Primary GPU user
  vramPercentage: 60    # 60% of VRAM

comfyUI:
  gpuEnabled: true      # Secondary GPU user  
  vramPercentage: 30    # 30% of VRAM (when enabled)

# 10% VRAM reserved for system
```

---

## 🔍 Monitoring & Health Checks

### 📊 **Built-in Health Monitoring**

#### **Application Health**
```bash
# Check all application pods
kubectl get pods -n lair

# Check application logs
kubectl logs -n lair deployment/lair-openwebui
kubectl logs -n lair statefulset/lair-ollama
kubectl logs -n lair deployment/lair-n8n
```

#### **Service Connectivity**
```bash
# Test internal service connectivity
kubectl exec -it deployment/lair-openwebui -n lair -- curl lair-ollama:11434/api/tags
kubectl exec -it deployment/lair-n8n -n lair -- curl lair-redis:6379

# Test external access
curl -k https://ai.hostname.local
curl -k https://n8n.hostname.local
```

#### **Resource Usage**
```bash
# Check resource consumption
kubectl top pods -n lair
kubectl top nodes

# Check storage usage
kubectl get pvc -n lair
df -h  # On cluster nodes
```

### 🚨 **Health Indicators**

#### **Application Status**
- **🟢 Healthy**: All pods Running, services responding
- **🟡 Degraded**: Some pods restarting, high resource usage
- **🔴 Critical**: Pods failing, services unreachable
- **⚫ Unknown**: Monitoring unavailable

#### **Performance Metrics**
- **Response Time**: API response latency
- **Resource Usage**: CPU, memory, storage utilization
- **Error Rate**: Application error frequency
- **Throughput**: Requests per second

---

## 🔄 Next Steps

### 📚 **Learn More About Each Component**
- **[OpenWebUI Configuration](applications/openwebui.md)** - Detailed OpenWebUI setup and usage
- **[N8N Workflows](applications/n8n.md)** - Automation and workflow creation
- **[Ollama Models](applications/ollama.md)** - LLM management and optimization
- **[ComfyUI Setup](applications/comfyui.md)** - AI image generation workflows

### 🔧 **Configuration & Management**
- **[Resource Management](../configuration/storage-resources.md)** - Optimize resource allocation
- **[Access Configuration](../configuration/network-access.md)** - Set up LAN and public access
- **[Certificate Management](../configuration/security-certificates.md)** - Configure HTTPS

### 🔍 **Troubleshooting**
- **[Application Issues](../troubleshooting/common-issues.md)** - Common application problems
- **[Performance Tuning](../troubleshooting/debugging.md)** - Optimize performance

---

**🎯 Ready to dive deeper?** Explore individual application guides or check the [Configuration Documentation](../configuration/advanced-configuration.md)!
