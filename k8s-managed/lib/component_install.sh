#!/usr/bin/env bash

run_component_install() {
    info "Installing additional components..."

    # Setup Helm at OS level if necessary
    setup_helm_os || {
        err "Helm setup failed. Unable to continue."
        exit 1
    }

    # Longhorn installation
    info "Installing Longhorn for persistent storage..."
    if helm repo add longhorn https://charts.longhorn.io && helm repo update; then
        if run_cmd "helm install longhorn longhorn/longhorn --namespace longhorn-system --create-namespace --version 1.12.1 --set defaultSettings.allowVolumeCreationWithDegradedAvailability=true --set persistence.defaultClassReplicaCount=1 --set defaultSettings.defaultReplicaCount=1 --set storageClass.allowVolumeExpansion=true --set defaultSettings.guaranteedInstanceManagerCPU=12 --set longhornManager.resources.limits.memory=1000Mi --set longhornManager.resources.requests.memory=256Mi"; then
            ok "Longhorn installed successfully. Waiting for pods to be ready..."
            run_cmd "kubectl -n longhorn-system rollout status deploy/longhorn-driver-deployer"
            ok "Longhorn is ready."
            
            # Optimize storage reservation
            optimize_longhorn_storage
        else
            err "Longhorn installation failed."
        fi
    else
        err "Failed to add Longhorn Helm repository."
    fi

    # NGINX Ingress Controller installation
    info "Installing NGINX Ingress Controller..."
    if helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx && helm repo update; then
        if run_cmd "helm install ingress-nginx ingress-nginx/ingress-nginx --namespace ingress-nginx --create-namespace"; then
            ok "NGINX Ingress Controller installed successfully. Waiting for pods to be ready..."
            run_cmd "kubectl -n ingress-nginx rollout status deploy/ingress-nginx-controller"
            ok "NGINX Ingress Controller is ready."
            
            # Creating 'public' ingress class for MicroK8s compatibility
            info "Creating 'public' ingress class for MicroK8s compatibility..."
            if run_cmd "kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: public
spec:
  controller: k8s.io/ingress-nginx
EOF"; then
                ok "Ingress class 'public' created successfully."
            else
                err "Failed to create ingress class 'public'."
            fi
        else
            err "NGINX Ingress Controller installation failed."
        fi
    else
        err "Failed to add NGINX Ingress Helm repository."
    fi

    # Cert-Manager installation
    info "Installing Cert-Manager..."
    if helm repo add jetstack https://charts.jetstack.io && helm repo update; then
        if run_cmd "helm install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace --version v1.12.0 --set installCRDs=true"; then
            ok "Cert-Manager installed successfully. Waiting for pods to be ready..."
            run_cmd "kubectl -n cert-manager rollout status deploy/cert-manager-webhook"
            ok "Cert-Manager is ready."
        else
            err "Cert-Manager installation failed."
        fi
    else
        err "Failed to add Jetstack Helm repository."
    fi

    ok "Component installation completed."

    # Install Velero (if enabled)
    install_velero
}
