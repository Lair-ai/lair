# 🧩 Component Architecture Documentation

This directory contains **standalone, modular components** for the Lair platform. Each component is self-contained and can be easily added, modified, or removed without affecting others.

## 🏗️ Architecture Overview

### **Cross-Component Functions** (`../component-config.sh`)
- `detect_system_hostname()` - Automatic hostname detection for LAN domains
- `configure_access_mode_and_email()` - LAN/Public access modes configuration  
- `configure_all_components()` - Component orchestration
- `show_resource_summary()` - Resource allocation display

### **Component-Specific Functions** (this directory)
Each `component.sh` file contains:
- `configure_COMPONENT()` - Interactive configuration
- `configure_COMPONENT_non_interactive()` - Config file mode
- Component-specific helper functions

## 📁 Current Components

| Component | File | Description |
|-----------|------|-------------|
| **OpenWebUI** | `openwebui.sh` | Main AI chat interface (always enabled) |
| **Ollama** | `ollama.sh` | Local AI model server (always enabled) |
| **N8N** | `n8n.sh` | Workflow automation platform (always enabled) |
| **ComfyUI** | `comfyui.sh` | AI image generation interface (optional) |
| **MinIO** | `minio.sh` | S3-compatible object storage (optional) |
| **PostgreSQL** | `postgresql.sh` | Primary database (always enabled) |
| **Redis** | `redis.sh` | Cache and message broker (always enabled) |

## ✨ Key Features

### **🏠 Automatic LAN Domain Generation**
- **Hostname Detection**: Automatically detects system hostname
- **Subdomain Input**: Users specify only the subdomain (e.g., `ai`, `n8n`)
- **Full Domain Creation**: Automatically builds `subdomain.hostname.local`

  **Example:**
  ```bash
🏠 System hostname detected: myserver
🌐 OpenWebUI LAN subdomain [default: ai]: ai
  ✅ LAN Domain: ai.myserver.local
  ```

### **🎯 Default Subdomains**
- **OpenWebUI**: `ai` → `ai.hostname.local`
- **N8N**: `n8n` → `n8n.hostname.local`
- **ComfyUI**: `images` → `images.hostname.local`
- **MinIO**: `storage` → `storage.hostname.local`
- **Ollama**: Optional (internal-only by default)

### **🔧 Cross-Component Integration**
- Uses `ask_storage_gb()` helper from `../helpers.sh`
- Accesses global variables (`ENABLE_LAN_ACCESS`, `SYSTEM_HOSTNAME`, etc.)
- Supports both interactive and non-interactive modes

## 🚀 Adding New Components

### **1. Copy Template**
```bash
cp _template.sh mynewcomponent.sh
```

### **2. Update Component Details**
```bash
# Update all occurrences of:
YOURCOMPONENT → MYNEWCOMPONENT
yourcomponent → mynewcomponent
YourComponent → MyNewComponent
```

### **3. Add to Orchestrator**
Edit `../component-config.sh`:

```bash
# Add to both interactive and non-interactive functions:
source "${lib_dir}/components/mynewcomponent.sh"

# Add function calls:
configure_mynewcomponent
configure_mynewcomponent_non_interactive
```

### **4. Update Configuration Template**
Add to `../../lair-config-template.yaml`:

```yaml
domains:
  lan:
    mynewcomponent: "mynewcomponent.lair.local"
  public:
    mynewcomponent: "mynewcomponent.example.com"

components:
  mynewcomponent:
    enabled: true
    # component-specific settings
```

### **5. Test Integration**
```bash
# Test interactive mode
./setup.sh

# Test config file mode  
./setup.sh --config test-config.yaml
```

## 🎨 Component Template Structure

See `_template.sh` for the complete template. Key sections:

```bash
# 1. Interactive configuration function
configure_yourcomponent() {
  # Domain configuration with new hostname logic
  # Storage configuration using shared helpers
  # Component-specific settings
}

# 2. Non-interactive configuration function  
configure_yourcomponent_non_interactive() {
  # Display loaded configuration
  # Show computed domains and settings
}

# 3. Component-specific helpers (optional)
configure_yourcomponent_advanced_settings() {
  # Complex configuration logic
}
```

## 🔄 Migration from Old Structure

The refactoring maintains **100% backward compatibility**:
- ✅ Existing config files continue to work
- ✅ All function names preserved
- ✅ Same configuration output format
- ✅ Hostname detection automatically adapts domains

## 🎯 Benefits

### **For Developers**
- **Modularity**: Each component is standalone
- **Maintainability**: Easy to modify individual components
- **Extensibility**: Simple to add new components
- **Testing**: Can test components in isolation

### **For Users**
- **Simplicity**: Only specify subdomains for LAN access
- **Consistency**: Uniform domain pattern across all components
- **Flexibility**: Still customize subdomains as needed
- **Compatibility**: Existing configurations continue working

## 📝 Best Practices

### **Component Development**
1. **Keep it standalone**: Don't depend on other components
2. **Use global helpers**: Leverage `ask_storage_gb()`, etc.
3. **Support both modes**: Interactive and non-interactive
4. **Follow naming conventions**: Consistent variable names
5. **Document thoroughly**: Clear descriptions and defaults

### **Domain Configuration**
1. **Use hostname logic**: Always build LAN domains with `$SYSTEM_HOSTNAME`
2. **Provide sensible defaults**: Short, memorable subdomains
3. **Allow customization**: Users can override defaults
4. **Support internal-only**: Empty domain for internal access

### **Error Handling**
1. **Validate inputs**: Check for required variables
2. **Provide fallbacks**: Graceful degradation
3. **Clear messages**: Helpful user feedback
4. **Maintain state**: Don't leave partial configurations 
