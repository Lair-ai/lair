#!/bin/bash

# ============================================================================
# GENERATE-LAN-CERTIFICATES.SH - mkcert Certificate Generator for LAN domains
# ============================================================================
# Supports both local execution and remote execution via SSH

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="lair"
SECRET_NAME="lair-tls-local"
CERT_DIR="./certificates"
REMOTE_HOST=""
REMOTE_USER=""
REMOTE_SCRIPT_PATH="/tmp/generate-certificates-remote.sh"

echo -e "${BLUE}🔐 Lair LAN Certificate Generator${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to detect kubectl command
detect_kubectl() {
    if command_exists microk8s && microk8s kubectl get nodes &>/dev/null; then
        echo "microk8s kubectl"
    elif command_exists kubectl; then
        echo "kubectl"
    else
        echo ""
    fi
}

# Function to create the remote script
create_remote_script() {
    local domains="$1"
    local wildcard_domain="$2"
    local custom_domains="$3"
    
    cat > /tmp/remote-cert-script.sh << 'EOF'
#!/bin/bash

# Remote certificate generation script
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

CERT_DIR="/tmp/lair-certificates"
mkdir -p "$CERT_DIR"
cd "$CERT_DIR"

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

echo -e "${BLUE}🔍 Checking for mkcert on remote host...${NC}"

# Install mkcert if not present
if ! command_exists mkcert; then
    echo -e "${YELLOW}📦 Installing mkcert on remote host...${NC}"
    
    # Detect OS and install mkcert
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        if command_exists brew; then
            brew install mkcert
        else
            echo -e "${RED}❌ Homebrew not found on macOS. Please install mkcert manually.${NC}"
            exit 1
        fi
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux
        echo -e "${BLUE}📥 Downloading mkcert v1.4.4 for Linux...${NC}"
        curl -JLO "https://dl.filippo.io/mkcert/v1.4.4?for=linux/amd64"
        
        # Verify SHA256 checksum
        EXPECTED_SHA256="6d31c65b03972c6dc4a14ab429f2928300518b26503f58723e532d1b0a3bbb52"
        echo "$EXPECTED_SHA256  mkcert-v1.4.4-linux-amd64" | sha256sum -c -
        if [ $? -ne 0 ]; then
            echo -e "${RED}❌ Checksum verification failed for mkcert!${NC}"
            rm -f mkcert-v1.4.4-linux-amd64
            exit 1
        fi
        echo -e "${GREEN}✅ Checksum verified successfully!${NC}"
        
        chmod +x mkcert-v1.4.4-linux-amd64
        sudo mv mkcert-v1.4.4-linux-amd64 /usr/local/bin/mkcert
        
        if ! command_exists mkcert; then
            echo -e "${RED}❌ Failed to install mkcert${NC}"
            exit 1
        fi
    else
        echo -e "${RED}❌ Unsupported OS for automatic mkcert installation${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}✅ mkcert is available${NC}"

# Install mkcert CA
echo -e "${BLUE}📋 Installing mkcert CA on remote host...${NC}"
mkcert -install

# Generate certificates based on arguments
EOF

    # Add domain-specific logic to the remote script
    if [ -n "$wildcard_domain" ]; then
        cat >> /tmp/remote-cert-script.sh << EOF

echo -e "${BLUE}🔑 Generating wildcard certificate for *.$wildcard_domain${NC}"
mkcert "*.$wildcard_domain" "$wildcard_domain"
CERT_FILE="_wildcard.${wildcard_domain}.pem"
KEY_FILE="_wildcard.${wildcard_domain}-key.pem"
EOF
    elif [ -n "$custom_domains" ]; then
        cat >> /tmp/remote-cert-script.sh << EOF

# Convert comma-separated domains to space-separated
DOMAINS_ARRAY=(${custom_domains//,/ })
echo -e "${BLUE}🔑 Generating certificate for domains: \${DOMAINS_ARRAY[*]}${NC}"
mkcert "\${DOMAINS_ARRAY[@]}"
FIRST_DOMAIN="\${DOMAINS_ARRAY[0]}"
CERT_FILE="\${FIRST_DOMAIN}.pem"
KEY_FILE="\${FIRST_DOMAIN}-key.pem"
EOF
    fi

    # Add verification and CA export logic
    cat >> /tmp/remote-cert-script.sh << 'EOF'

# Check if certificates were generated
if [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
    echo -e "${RED}❌ Certificate generation failed${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Certificates generated successfully${NC}"
echo "  📄 Certificate: $CERT_FILE"
echo "  🔑 Private Key: $KEY_FILE"

# Export CA for distribution
CA_ROOT=$(mkcert -CAROOT)
echo -e "${BLUE}📋 Exporting CA from: $CA_ROOT${NC}"
cp "$CA_ROOT/rootCA.pem" ./rootCA.pem
cp "$CA_ROOT/rootCA-key.pem" ./rootCA-key.pem

echo -e "${GREEN}🎉 Remote certificate generation complete!${NC}"
echo ""
echo -e "${BLUE}📁 Files created:${NC}"
ls -la
EOF

    chmod +x /tmp/remote-cert-script.sh
}

# Function to execute on remote host
execute_remote() {
    local domains="$1"
    local wildcard_domain="$2"
    local custom_domains="$3"
    
    echo -e "${BLUE}🌐 Executing certificate generation on remote host: $REMOTE_USER@$REMOTE_HOST${NC}"
    echo ""
    
    # Create the remote script
    create_remote_script "$domains" "$wildcard_domain" "$custom_domains"
    
    # Copy script to remote host
    echo -e "${BLUE}📤 Copying script to remote host...${NC}"
    scp /tmp/remote-cert-script.sh "$REMOTE_USER@$REMOTE_HOST:$REMOTE_SCRIPT_PATH"
    
    # Execute the script on remote host
    echo -e "${BLUE}🚀 Executing certificate generation on remote host...${NC}"
    ssh "$REMOTE_USER@$REMOTE_HOST" "bash $REMOTE_SCRIPT_PATH"
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Remote certificate generation failed${NC}"
        exit 1
    fi
    
    # Create local certificates directory
    mkdir -p "$CERT_DIR"
    
    # Copy certificates back from remote host
    echo -e "${BLUE}📥 Downloading certificates from remote host...${NC}"
    scp "$REMOTE_USER@$REMOTE_HOST:/tmp/lair-certificates/*" "$CERT_DIR/"
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Failed to download certificates from remote host${NC}"
        exit 1
    fi
    
    # Clean up remote files
    echo -e "${BLUE}🧹 Cleaning up remote files...${NC}"
    ssh "$REMOTE_USER@$REMOTE_HOST" "rm -rf /tmp/lair-certificates $REMOTE_SCRIPT_PATH"
    
    # Clean up local temp files
    rm -f /tmp/remote-cert-script.sh
    
    echo -e "${GREEN}✅ Certificates successfully retrieved from remote host${NC}"
    echo ""
    
    # Set certificate file variables for local processing
    cd "$CERT_DIR"
    if [ -n "$wildcard_domain" ]; then
        CERT_FILE="_wildcard.${wildcard_domain}.pem"
        KEY_FILE="_wildcard.${wildcard_domain}-key.pem"
    else
        DOMAINS_ARRAY=(${custom_domains//,/ })
        FIRST_DOMAIN="${DOMAINS_ARRAY[0]}"
        CERT_FILE="${FIRST_DOMAIN}.pem"
        KEY_FILE="${FIRST_DOMAIN}-key.pem"
    fi
}

# Function to execute locally
execute_local() {
    local domains="$1"
    local wildcard_domain="$2"
    local custom_domains="$3"
    
    # Check if mkcert is installed
    if ! command_exists mkcert; then
        echo -e "${RED}❌ mkcert is not installed${NC}"
        echo ""
        echo -e "${YELLOW}Please install mkcert first:${NC}"
        echo ""
        echo -e "${BLUE}🍎 macOS (Homebrew):${NC}"
        echo "  brew install mkcert"
        echo ""
        echo -e "${BLUE}🐧 Linux (v1.4.4 with checksum verification):${NC}"
        echo "  curl -JLO \"https://dl.filippo.io/mkcert/v1.4.4?for=linux/amd64\""
        echo "  echo \"6d31c65b03972c6dc4a14ab429f2928300518b26503f58723e532d1b0a3bbb52  mkcert-v1.4.4-linux-amd64\" | sha256sum -c -"
        echo "  chmod +x mkcert-v1.4.4-linux-amd64"
        echo "  sudo mv mkcert-v1.4.4-linux-amd64 /usr/local/bin/mkcert"
        echo ""
        echo -e "${BLUE}🪟 Windows:${NC}"
        echo "  choco install mkcert"
        echo ""
        echo -e "${BLUE}📖 More info: https://github.com/FiloSottile/mkcert${NC}"
        exit 1
    fi

    echo -e "${GREEN}✅ mkcert is installed${NC}"
    
    # Install mkcert CA
    echo -e "${BLUE}📋 Installing mkcert CA in local system trust store...${NC}"
    mkcert -install

    # Create certificates directory
    mkdir -p "$CERT_DIR"
    cd "$CERT_DIR"

    # Generate certificates
    if [ -n "$wildcard_domain" ]; then
        echo -e "${BLUE}🔑 Generating wildcard certificate for *.$wildcard_domain${NC}"
        mkcert "*.$wildcard_domain" "$wildcard_domain"
        CERT_FILE="_wildcard.${wildcard_domain}.pem"
        KEY_FILE="_wildcard.${wildcard_domain}-key.pem"
    elif [ -n "$custom_domains" ]; then
        # Convert comma-separated domains to space-separated
        DOMAINS_ARRAY=(${custom_domains//,/ })
        echo -e "${BLUE}🔑 Generating certificate for domains: ${DOMAINS_ARRAY[*]}${NC}"
        mkcert "${DOMAINS_ARRAY[@]}"
        # mkcert generates files based on the first domain
        FIRST_DOMAIN="${DOMAINS_ARRAY[0]}"
        CERT_FILE="${FIRST_DOMAIN}.pem"
        KEY_FILE="${FIRST_DOMAIN}-key.pem"
    fi

    # Check if certificates were generated
    if [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
        echo -e "${RED}❌ Certificate generation failed${NC}"
        exit 1
    fi

    echo -e "${GREEN}✅ Certificates generated successfully${NC}"
    echo "  📄 Certificate: $CERT_FILE"
    echo "  🔑 Private Key: $KEY_FILE"
    echo ""
}

# Parse command line arguments
DOMAINS=""
WILDCARD_DOMAIN=""
CUSTOM_DOMAINS=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --domains)
            CUSTOM_DOMAINS="$2"
            shift 2
            ;;
        --wildcard)
            WILDCARD_DOMAIN="$2"
            shift 2
            ;;
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --secret)
            SECRET_NAME="$2"
            shift 2
            ;;
        --remote-host)
            REMOTE_HOST="$2"
            shift 2
            ;;
        --remote-user)
            REMOTE_USER="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --domains DOMAINS     Comma-separated list of domains (e.g., 'ai.lair.local,n8n.lair.local')"
            echo "  --wildcard DOMAIN     Generate wildcard certificate for domain (e.g., 'lair.local')"
            echo "  --namespace NS        Kubernetes namespace (default: lair)"
            echo "  --secret NAME         Secret name (default: lair-tls-local)"
            echo "  --remote-host HOST    Execute on remote host via SSH"
            echo "  --remote-user USER    SSH user for remote execution (default: current user)"
            echo "  --help                Show this help message"
            echo ""
            echo "Execution Modes:"
            echo "  • Local:  Generates certificates on this machine (requires mkcert installation)"
            echo "  • Remote: Generates certificates on remote host via SSH (installs mkcert automatically)"
            echo ""
            echo "Examples:"
            echo "  $0 --wildcard neura.local"
            echo "  $0 --wildcard neura.local --remote-host 192.168.1.100 --remote-user ubuntu"
            echo "  $0 --domains 'ai.neura.local,n8n.neura.local'"
            exit 0
            ;;
        *)
            echo -e "${RED}❌ Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# Set default remote user if not specified
if [ -n "$REMOTE_HOST" ] && [ -z "$REMOTE_USER" ]; then
    REMOTE_USER=$(whoami)
fi

# Detect kubectl
KUBECTL_CMD=$(detect_kubectl)
if [ -z "$KUBECTL_CMD" ]; then
    echo -e "${RED}❌ kubectl not found${NC}"
    echo "Please install kubectl or ensure microk8s is running"
    exit 1
fi

echo -e "${GREEN}✅ kubectl detected: $KUBECTL_CMD${NC}"

# Default domains if none specified
if [ -z "$CUSTOM_DOMAINS" ] && [ -z "$WILDCARD_DOMAIN" ]; then
    echo -e "${YELLOW}No domains specified, using default wildcard: lair.local${NC}"
    WILDCARD_DOMAIN="lair.local"
fi

# Show execution mode
if [ -n "$REMOTE_HOST" ]; then
    echo -e "${BLUE}🌐 Execution mode: Remote (SSH to $REMOTE_USER@$REMOTE_HOST)${NC}"
    echo -e "${GREEN}✅ This ensures mkcert CA is installed on the cluster host${NC}"
else
    echo -e "${BLUE}🏠 Execution mode: Local${NC}"
    echo -e "${YELLOW}⚠️  Note: mkcert CA will be installed on this machine only${NC}"
fi
echo ""

# Execute certificate generation
if [ -n "$REMOTE_HOST" ]; then
    # Test SSH connection
    echo -e "${BLUE}🔍 Testing SSH connection to $REMOTE_USER@$REMOTE_HOST...${NC}"
    if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "$REMOTE_USER@$REMOTE_HOST" exit 2>/dev/null; then
        echo -e "${RED}❌ Cannot connect to $REMOTE_USER@$REMOTE_HOST${NC}"
        echo "Please ensure:"
        echo "  • SSH key is set up for passwordless authentication"
        echo "  • Remote host is accessible"
        echo "  • User has sudo privileges (for mkcert installation)"
        exit 1
    fi
    echo -e "${GREEN}✅ SSH connection successful${NC}"
    echo ""
    
    execute_remote "$DOMAINS" "$WILDCARD_DOMAIN" "$CUSTOM_DOMAINS"
else
    execute_local "$DOMAINS" "$WILDCARD_DOMAIN" "$CUSTOM_DOMAINS"
fi

# Create Kubernetes secret
echo -e "${BLUE}📦 Creating Kubernetes TLS secret...${NC}"
$KUBECTL_CMD create secret tls "$SECRET_NAME" \
    --cert="$CERT_FILE" \
    --key="$KEY_FILE" \
    --namespace="$NAMESPACE" \
    --dry-run=client -o yaml | $KUBECTL_CMD apply -f -

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ TLS secret '$SECRET_NAME' created successfully in namespace '$NAMESPACE'${NC}"
else
    echo -e "${RED}❌ Failed to create TLS secret${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}🎉 Certificate setup complete!${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e "${BLUE}📋 Next steps:${NC}"
echo ""
echo "1. Enable LAN TLS in your Helm values:"
echo -e "   ${YELLOW}ingress.lan.enableTLS: true${NC}"
echo ""
echo "2. Ensure your DNS resolves .local domains to your cluster IP:"
echo -e "   ${YELLOW}# Add to /etc/hosts on each client machine${NC}"
if [ -n "$WILDCARD_DOMAIN" ]; then
    echo -e "   ${YELLOW}192.168.1.100 ai.$WILDCARD_DOMAIN n8n.$WILDCARD_DOMAIN storage.$WILDCARD_DOMAIN${NC}"
else
    echo -e "   ${YELLOW}192.168.1.100 ${CUSTOM_DOMAINS/,/ }${NC}"
fi
echo ""
echo "3. Deploy/upgrade your Helm chart:"
echo -e "   ${YELLOW}helm upgrade --install lair . -n lair -f your-config.yaml${NC}"
echo ""
echo "4. Access your services with HTTPS:"
if [ -n "$WILDCARD_DOMAIN" ]; then
    echo -e "   ${YELLOW}https://ai.$WILDCARD_DOMAIN${NC}"
    echo -e "   ${YELLOW}https://n8n.$WILDCARD_DOMAIN${NC}"
    echo -e "   ${YELLOW}https://storage.$WILDCARD_DOMAIN${NC}"
else
    for domain in "${DOMAINS_ARRAY[@]}"; do
        echo -e "   ${YELLOW}https://$domain${NC}"
    done
fi
echo ""

# Show CA distribution instructions
echo -e "${GREEN}🔒 Certificate Trust Setup${NC}"
if [ -n "$REMOTE_HOST" ]; then
    echo -e "${GREEN}✅ mkcert CA is installed on the cluster host ($REMOTE_HOST)${NC}"
    echo ""
    echo -e "${BLUE}📋 To enable trusted certificates on client machines:${NC}"
    echo ""
    echo "The CA files are available in the certificates directory:"
    echo -e "   ${YELLOW}$(pwd)/rootCA.pem${NC}"
    echo -e "   ${YELLOW}$(pwd)/rootCA-key.pem${NC}"
    echo ""
    echo "For each client machine that needs trusted certificates:"
    echo ""
    echo -e "${YELLOW}macOS:${NC}"
    echo "  brew install mkcert"
    echo "  mkdir -p ~/.local/share/mkcert"
    echo "  cp rootCA.pem ~/.local/share/mkcert/"
    echo "  cp rootCA-key.pem ~/.local/share/mkcert/"
    echo "  mkcert -install"
    echo ""
    echo -e "${YELLOW}Linux:${NC}"
    echo "  # Install mkcert first, then:"
    echo "  mkdir -p ~/.local/share/mkcert"
    echo "  cp rootCA.pem ~/.local/share/mkcert/"
    echo "  cp rootCA-key.pem ~/.local/share/mkcert/"
    echo "  mkcert -install"
    echo ""
    echo -e "${YELLOW}Windows:${NC}"
    echo "  # Install mkcert first, then copy CA files to %LOCALAPPDATA%\\mkcert"
    echo "  # and run: mkcert -install"
else
    echo -e "${YELLOW}⚠️  mkcert CA is installed only on this machine${NC}"
    echo ""
    echo -e "${BLUE}📋 To enable trusted certificates on other machines:${NC}"
    echo ""
    echo "1. Find your CA root:"
    echo -e "   ${YELLOW}mkcert -CAROOT${NC}"
    echo ""
    echo "2. Copy rootCA.pem and rootCA-key.pem to other machines"
    echo "3. Install mkcert on each machine and run mkcert -install"
fi
echo ""
echo -e "${BLUE}💡 Pro tip: mkcert certificates are valid for 10 years and automatically trusted${NC}"
echo "   by browsers on machines where the mkcert CA is properly installed." 