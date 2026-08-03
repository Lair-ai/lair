
# 🚀 Practical Tutorial: Installing Lair on a PC with GPU in lan mode (Single-Node)

This tutorial provides a step-by-step practical example for installing the Lair infrastructure on a single machine (Single-Node) with a GPU. To use only in lan mode.
For example, we tested it on a AMD Ryzen 5 2600 16GB RAM, 256GB SSD and NVIDIA GeForce RTX 2060 6GB

## 📌 Prerequisites

Pc with Ubuntu 24.04 with Nvidia Driver version 570 or better.

Verify current installation:

```bash
nvidia-smi
```

## 🛠️ Step 1: First Steps and Server Preparation

```bash
sudo apt update
sudo apt upgrade -y
```

## 🏗️ Step 2: Install Single-Node Cluster (8-10 minutes)

Navigate to the Lair directory and run the main setup script to install the Kubernetes cluster.

```bash
git clone https://github.com/Lair-ai/lair.git
cd lair
sudo ./setup.sh
```

Follow the interactive wizard and answer the prompts as follows (press **Enter** to accept the default values where indicated):


- **WHAT WOULD YOU LIKE TO DO:** `1` *(Setup Kubernetes cluster - Step 1)*
- **CLUSTER SETUP OPTIONS:** `2` *(I want to install MicroK8s on this machine)*
- **Do you want to continue? (y/N):** `y`
- **Is this the PRIMARY node or a SECONDARY node? [primary/secondary]:** `primary`
- **Enter cluster name [microk8s-cluster]:** `demo-k8s` *(or your preferred name)*
- **Enable Velero backups? (y/n) [default: y]:** `n`
- **Enter new hostname [demolair]:** `<Press Enter>`
- **Access mode? [lan/public] (default: lan):** `lan`
- **Enter your public IP or MetalLB range [\<ip address>]:** `<Press Enter>`
- **Enable remote cluster access? [Y/n] (default: Y):** `<Press Enter>`

---

## 🚀 Step 3: Install Lair Application (5-10 minutes)

After the reboot, reconnect to your server via SSH:

```bash
ssh ubuntu@<hostname or ip address>
```

Navigate back to the directory and run the setup script again to deploy the application:

```bash
cd lair
sudo ./setup.sh
```

Answer the wizard prompts to configure Lair:



- **WHAT WOULD YOU LIKE TO DO:** `2` *(Deploy Lair application - Step 2)*
- **Do you want to continue? (y/N):** `y`
- **Select configuration file to import [0-2] (default: 0):** `<Press Enter>`
- **How do you prefer to detect available resources?:** `1` *(From local operating system)*
- **Do you want to continue with this resource allocation? (y/n) [default: y]:** `<Press Enter>`
- **Use these detected resources? (y/n) [default: y]:** `<Press Enter>`
- **Configuration name (for filename):** `<a name to identify yaml, such as "demo">`
- **Is this installation for NVIDIA Jetson? (y/n) [default: y]:** `n`
- **Enable LAN access with .local domains? (y/n) [default: y]:** `y`
- **LAN hostname for .local domains [default: \<hostname\>]:** `<Press Enter>`
- **Enable HTTPS for LAN domains? (y/n) [default: n]:** `n`
- **Enable public access with internet domains? (y/n) [default: n]:** `n`
- **OpenWebUI LAN subdomain [default: ai]:** `<Press Enter>`
- **OpenWebUI data storage in GB (recommended: \<x\>GB, available: \<x\>GB) [default: \<x\>]:** `<Press Enter>`
- **Ollama models storage in GB (recommended: \<x\>GB, available: \<x\>GB) [default: \<x\>]:** `<Press Enter>`
- **VRAM allocation percentage [default: 80]:** `<Press Enter>`
- **Custom Ollama image (leave empty for default):** `<Press Enter>`
- **N8N LAN subdomain [default: n8n]:** `<Press Enter>`
- **N8N workflows storage in GB (recommended: \<x\>GB, available: \<x\>GB) [default: \<x\>]:** `<Press Enter>`
- **Enable SMTP for N8N user management? (y/n) [default: n]:** `y`
- **SMTP Host:** `ssl0.ovh.net` *(or your provider's SMTP)*
- **SMTP Port:** `465`
- **SMTP Username/Email:** `no-reply@<your-domain>`
- **SMTP Password:** `<no-reply email password>`
- **Sender Email:** `<Press Enter>`
- **Use SSL/TLS? (y/n) [default: y]:** `<Press Enter>`
- **Use STARTTLS? (y/n) [default: y]:** `<Press Enter>`
- **Enable ComfyUI for AI image generation? (y/n) [default: y]:** `<Press Enter>`
- **ComfyUI LAN subdomain [default: images] (leave empty for internal-only access):** `images`
- **ComfyUI models and outputs storage in GB (recommended: \<x\>GB, available: \<x\>GB) [default: \<x\>]:** `30`
- **ComfyUI image:** automatic selection by GPU family (RTX uses CUDA 12.8; NVIDIA Driver 570+ required)
- **Enable MinIO object storage? (y/n) [default: y]:** `<Press Enter>`
- **MinIO public domain (leave empty for internal-only access):** `<Press Enter>`
- **MinIO object storage storage in GB (recommended: \<x\>GB, available: \<x\>GB) [default: \<x\>]:** `<Press Enter>`
- **Root username:** `<Choose an admin username>`
- **Root password:** `<Choose a strong password>`
- **PostgreSQL database storage in GB (recommended: \<x\>GB, available: \<x\>GB) [default: \<x\>]:** `<Press Enter>`
- **Redis cache storage in GB (recommended: \<x\>GB, available: \<x\>GB) [default: \<x\>]:** `<Press Enter>`
- **Enable automatic backups with Velero? (y/n) [default: n]:** `<Press Enter>`


## 🚀 Step 4: Install Lair Application (5-10 minutes)

At main main of Setup, choose `3` to configure DNS for local network access.

- **WHAT WOULD YOU LIKE TO DO:** `3` *(Configure DNS for local network access)*
- **Do you want to continue? (y/N):** `y`
- **Do you want to proceed? [Y/n]:** `y`
- **Press Enter to test current DNS status...** `<Press Enter>`
- **Ready to install DNS? Press Enter to continue...** `<Press Enter>`
- **Press Enter to test DNS after installation...** `<Press Enter>`
- **Enable network DNS access? [Y/n]:** `y`

Once finished, exit the setup wizard.

To access in lan the application, you can:
1. modify the hosts file on your pc adding a row to point to the ip of the pc

```bash
sudo nano /etc/hosts
```
```bash
192.168.x.x	ai.<hostname>.local n8n.<hostname>.local images.<hostname>.local
```
2. modify the DNS server list of your router/tcp settings adding the address of the pc as DNS server

## ⏳ Step 5: Monitor Deployment (about 15 minutes)

Wait until all services and pods are successfully running. You can watch the pods spinning up in real-time with the following command:

```bash
watch -n 10 kubectl get all -n lair
```

> ⚠️ **Note**: The system will take a couple of minutes to start. Pods may start, crash, and restart automatically until all dependencies are met and stable. It takes roughly **10-15 minutes** for Ollama to download the lightweight model usable on the CPU.

---

## 🛑 Step 6: VERY IMPORTANT - Initial Setup

Once all pods show the `Running` status, you must immediately secure your instances by creating the admin accounts:

1. **Chat interface**: Visit `https://ai.<your-domain>.local` in your browser and create your admin account

   **Add an AI provider**
   In OVH Cloud:
   - Choose **Public Cloud**
   - Choose **AI Endpoints** -> **Create a new API Key**

   In your Lair site:
   - Go to **Admin Settings** → **Connections** → **API OpenAI**
   - Choose **Add Connection**
   - Write in the URL field: `https://oai.endpoints.kepler.ai.cloud.ovh.net/v1`
   - Write the API Key you just created in the API Key field

   For image generation:
   - Go to **Admin Settings** → **Images** → **Create Image**
   - Write in Model field: `stable-diffusion-xl-1024-v1-0`
   - Write in Image Size: `1024x1024`
   - Write in Image Generation Engine: `OpenAI`
   - Write in URL field: `https://oai.endpoints.kepler.ai.cloud.ovh.net/v1`
   - Write the API Key you just created in the API Key field

   [More information on OpenWebUI](https://docs.openwebui.com/getting-started/quick-start)

2. **N8N Workflow**: Visit `https://n8n.<your-domain>.local`.
   - *During the first steps, you may be required to request a free activation key to set up your local N8N instance.*
