# 1. Aggiungi (o aggiorna) il repository
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update


# 2. Installa la release (namespace "prometheus")
helm upgrade --install prometheus \
  prometheus-community/kube-prometheus-stack \
  --namespace prometheus --create-namespace


# 3. export POD_NAME
export POD_NAME=$(kubectl --namespace prometheus get pod -l "app.kubernetes.io/name=grafana,app.kubernetes.io/instance=prometheus" -oname)


# 4. PF
kubectl --namespace prometheus port-forward $POD_NAME 3000