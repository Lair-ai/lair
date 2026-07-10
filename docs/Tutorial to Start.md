# 🚀 Practical Tutorial: Installing Lair on Single-Node in Cloud

This tutorial provides a step-by-step practical example for installing the Lair infrastructure on a single machine (Single-Node) on a cloud VPS. We will set up Lair, the AI environment, and workflow automation across two different subdomains:
- `https://demo.<your-domain>`
- `https://n8ndemo.<your-domain>`

> **Note**: By default, the platform will download a lightweight model to use on CPU. Without a GPU, we recommend configuring a remote AI provider (like OVH AI Endpoint) that allows you to use open-source models with GDPR-compliant services, ensuring your data is not used for training.

---

## 📋 Prerequisites

Before starting, make sure you have:
- A **domain name** (e.g., `lair-ai.it`). We will use two second-level domains, for example: `demo.lair-ai.it` for the chat interface and `n8ndemo.lair-ai.it` for the workflow interface.
- An **email address** like `reply@<your-domain>` configured as a sender.
- If you used OVH as your DNS registrar you can create an email address in Web Cloud -> MX Plan -> Email Addresses -> Add an email address.
- (Optional) An **S3 bucket** ready if you want to enable cloud backups. In this tutorial, we will skip the Velero backup activation.

---

## ☁️ Step 1: Buy a New Instance (Cloud VPS)

Purchase a new instance on your preferred datacenter or cloud provider. In this example, we use **OVHCloud** (European cloud provider, GDPR Compliant):

1. **Create an account**: A new account usually gives you some starting credit (e.g., 200€ as of June 2026).
2. **Create Instance**: Navigate to **Public Cloud** -> **New Instance**.
3. **Choose Specifications**: Select a plan like **B3-16** (4 vCore, 16GB RAM, 100GB NVMe) at roughly 0.10€/h or 56€/month. Initially, you pay per hour of use, so you can stop the instance or switch to a longer contract later.
4. **SSH Key**: Follow your provider's guide to use an SSH key for secure access.
5. **Get IP**: Once the instance is ready, you will be assigned a **Public IP address**.

---

## 🌐 Step 2: Configure Domain Names (DNS Records)

You need to point your subdomains to your new server using your domain registrar's DNS settings (e.g., OVH Web Cloud -> Domains).

1. Go to your **DNS Zone** configuration.
2. Add an **A Record**:
   - Host: `demo`
   - Value: `<Your Public IP address>`
3. Add a **CNAME Record**:
   - Host: `n8ndemo`
   - Value: `demo.<your-domain>` (e.g., `demo.lair-ai.it`)

---

## 🖥️ Step 3: Access Your New Instance

Connect to your newly created server via SSH using your terminal:

```bash
ssh ubuntu@demo.<your-domain>
```

---

## 🛠️ Step 4: First Steps and Server Preparation

Update the system packages:

```bash
sudo apt update
sudo apt upgrade -y
```

### (Optional) Fix Netplan (Dual Network Issue & DNS)
On some cloud providers, two networks might be active by default, which can cause routing and internal DNS resolution conflicts (especially on OVHCloud private networks).

For example, if you check the current configuration you can find:

```bash
ip route show
```
```bash
default via X.X.X.1 dev ens3 proto dhcp src X.X.X.254 metric 100
default via 10.1.0.1 dev ens4 proto dhcp src 10.1.1.117 metric 100
...
```
As you can see, both networks have the same metric.

In OVHCloud, `ens3` is the public network and `ens4` is the private network.
Let's fix the netplan configuration by lowering the priority of the private network and explicitly ignoring its DNS servers.

```bash
sudo nano /etc/netplan/99-ens4-metric.yaml
```

Insert the following content and save the file:

```yaml
network:
  version: 2
  ethernets:
    ens4:
      dhcp4: true
      dhcp4-overrides:
        route-metric: 200
        use-dns: false
```

Next, ensure the permissions on this file are strictly locked down (Ubuntu requires this for Netplan):

```bash
sudo chmod 600 /etc/netplan/99-ens4-metric.yaml
```

After saving and fixing permissions, apply the network changes:

```bash
sudo netplan try
sudo netplan apply
```

---

## 🏗️ Step 5: Install Single-Node Cluster (8-10 minutes)

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
- **Access mode? [lan/public] (default: lan):** `public`
- **Enter your public IP or MetalLB range [\<ip address>]:** `<Press Enter>`
- **Enable remote cluster access? [Y/n] (default: Y):** `<Press Enter>`

At the end of the script:
- **Press ENTER to reboot or Ctrl+C to cancel...** `<Press Enter>`

---

## 🚀 Step 6: Install Lair Application (5-10 minutes)

After the reboot, reconnect to your server via SSH:

```bash
ssh ubuntu@demo.<your-domain>
```

First step, check if every pod is running in the just created cluster:
```bash
watch -n 10 kubectl get pods --all-namespaces
```

You should see a table as the following, where you can check the STATUS column:
```bash

NAMESPACE         NAME                                                READY   STATUS    RESTARTS        AGE
cert-manager      cert-manager-cainjector-fd9bf654b-vq8zl             1/1     Running   1 (2m25s ago)   7m27s
cert-manager      cert-manager-ff4b94468-98j4l                        1/1     Running   1 (2m25s ago)   7m27s
cert-manager      cert-manager-webhook-7749797f6-wtkrr                1/1     Running   1 (2m25s ago)   7m27s
ingress           nginx-ingress-microk8s-controller-qrbch             1/1     Running   1 (2m25s ago)   7m27s
kube-system       calico-kube-controllers-5947598c79-pxxd5            1/1     Running   1 (2m25s ago)   9m23s
kube-system       calico-node-g97zz                                   1/1     Running   1 (2m25s ago)   9m23s
kube-system       coredns-79b94494c7-jd6t5                            1/1     Running   1 (2m25s ago)   9m23s
kube-system       metrics-server-7dbd8b5cc9-lz4f4                     1/1     Running   1 (2m25s ago)   5m11s
longhorn-system   csi-attacher-578c8d8874-5c5xb                       1/1     Running   2 (98s ago)     5m36s
longhorn-system   csi-attacher-578c8d8874-fwxjw                       1/1     Running   2 (97s ago)     5m36s
longhorn-system   csi-attacher-578c8d8874-jjcj7                       1/1     Running   2 (98s ago)     5m36s
longhorn-system   csi-provisioner-648dfd9fcf-n9rwp                    1/1     Running   2 (97s ago)     5m36s
longhorn-system   csi-provisioner-648dfd9fcf-p95lq                    1/1     Running   2 (96s ago)     5m35s
longhorn-system   csi-provisioner-648dfd9fcf-przxm                    1/1     Running   2 (98s ago)     5m35s
longhorn-system   csi-resizer-749999f5bf-jlm88                        1/1     Running   2 (96s ago)     5m35s
longhorn-system   csi-resizer-749999f5bf-jx8r5                        1/1     Running   2 (98s ago)     5m35s
longhorn-system   csi-resizer-749999f5bf-z7mnb                        1/1     Running   2 (96s ago)     5m35s
longhorn-system   csi-snapshotter-654587999d-56xc6                    1/1     Running   2 (98s ago)     5m35s
longhorn-system   csi-snapshotter-654587999d-5fhd2                    1/1     Running   2 (97s ago)     5m35s
longhorn-system   csi-snapshotter-654587999d-x5lss                    1/1     Running   2 (97s ago)     5m35s
longhorn-system   engine-image-ei-a4d05f02-fcdrx                      1/1     Running   1 (2m25s ago)   6m8s
longhorn-system   instance-manager-5645c7ab1a0fdf91c031007d54dfb6a1   1/1     Running   0               65s
longhorn-system   longhorn-csi-plugin-hbrdr                           3/3     Running   4 (97s ago)     5m35s
longhorn-system   longhorn-driver-deployer-7579c76c98-5fstz           1/1     Running   1 (2m25s ago)   6m28s
longhorn-system   longhorn-manager-95c5q                              2/2     Running   3 (2m25s ago)   6m28s
longhorn-system   longhorn-ui-674df74d95-bbtkg                        1/1     Running   3 (75s ago)     6m28s
longhorn-system   longhorn-ui-674df74d95-krsxs                        1/1     Running   3 (76s ago)     6m28s
metallb-system    controller-7ffc454778-zr8q4                         1/1     Running   1 (2m25s ago)   7m5s
metallb-system    speaker-cdt4b                                       1/1     Running   1 (2m25s ago)   7m5s
```

When all pods will be ready, exit using ctrl-c.
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
- **Enable LAN access with .local domains? (y/n) [default: y]:** `n`
- **Email for Let's Encrypt certificates:** `hello@<your-domain>`
- **OpenWebUI public domain:** `demo.<your-domain>`
- **OpenWebUI data storage in GB:** `<Press Enter>`
- **Enable SSO authentication? (y/n) [default: n]:** `<Press Enter>`
- **Ollama models storage in GB:** `<Press Enter>`
- **Custom Ollama image (leave empty for default):** `<Press Enter>`
- **N8N public domain:** `n8ndemo.<your-domain>`
- **N8N workflows storage in GB:** `<Press Enter>`
- **Enable SMTP for N8N user management? (y/n) [default: n]:** `y`
- **SMTP Host:** `ssl0.ovh.net` *(or your provider's SMTP)*
- **SMTP Port:** `465`
- **SMTP Username/Email:** `no-reply@<your-domain>`
- **SMTP Password:** `<no-reply email password>`
- **Sender Email:** `<Press Enter>`
- **Use SSL/TLS? (y/n) [default: y]:** `<Press Enter>`
- **Use STARTTLS? (y/n) [default: y]:** `<Press Enter>`
- **Enable MinIO object storage? (y/n) [default: y]:** `<Press Enter>`
- **MinIO public domain (leave empty for internal-only access):** `<Press Enter>`
- **MinIO object storage storage in GB:** `<Press Enter>`
- **Root username:** `<Choose an admin username>`
- **Root password:** `<Choose a strong password>`
- **PostgreSQL database storage in GB:** `<Press Enter>`
- **Redis cache storage in GB:** `<Press Enter>`
- **Enable automatic backups with Velero? (y/n) [default: n]:** `<Press Enter>`

Once finished, exit the setup wizard.

---

## ⏳ Step 7: Monitor Deployment (about 15 minutes)

Wait until all services and pods are successfully running. You can watch the pods spinning up in real-time with the following command:

```bash
watch -n 10 kubectl get all -n lair
```

> ⚠️ **Note**: The system will take a couple of minutes to start. Pods may start, crash, and restart automatically until all dependencies are met and stable. It takes roughly **10-15 minutes** for Ollama to download the lightweight model usable on the CPU.

---

## 🛑 Step 8: VERY IMPORTANT - Initial Setup

Once all pods show the `Running` status, you must immediately secure your instances by creating the admin accounts:

1. **Chat interface**: Visit `https://demo.<your-domain>` in your browser and create your admin account

   **Add an AI provider**
   In OVH Cloud:
   - Choose **Public Cloud**
   - Choose **AI Endpoints** -> **Create a new API Key**

   In your Lair site:
   - Go to **Admin Settings** → **Connections** → **API OpenAI**
   - Choose **Add Connection**
   - Write in the URL field: `https://oai.endpoints.kepler.ai.cloud.ovh.net/v1`
   - Write the API Key you just created in the API Key field

   To show only some models in Chat menu:
   - Go to **Admin Settings** → **Models**
   - Disable models for embedding (as bge..), safeguard (Qwen3Guard), audio (as whisper..), images (as stable diffusion..)

   For image generation you can try this free service:
   - Go to **Admin Settings** → **Images** → **Create Image**
   - Write in Model field: `stable-diffusion-xl-1024-v1-0`
   - Write in Image Size: `1024x1024`
   - Write in Image Generation Engine: `OpenAI`
   - Write in URL field: `https://oai.endpoints.kepler.ai.cloud.ovh.net/v1`
   - Write the API Key you just created in the API Key field

2. **N8N Workflow**: Visit `https://n8ndemo.<your-domain>`.
   - *During the first steps, you may be required to request a free activation key to set up your local N8N instance.*
