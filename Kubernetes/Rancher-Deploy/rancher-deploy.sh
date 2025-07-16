#!/usr/bin/env bash
set -euo pipefail

###############################
# Prompt for Rancher hostname #
###############################
read -p "Enter Rancher hostname [rancher.my.org]: " RANCHER_HOSTNAME
RANCHER_HOSTNAME=${RANCHER_HOSTNAME:-rancher.my.org}
echo "→ Using Rancher hostname: ${RANCHER_HOSTNAME}"

#################################
# 1) Install Helm CLI           #
#################################
if ! command -v helm &> /dev/null; then
  echo "🔧 Installing Helm via official script…"
  curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
  chmod +x get_helm.sh
  ./get_helm.sh
  rm get_helm.sh
else
  echo "✅ Helm already installed"
fi

#################################
# 2) Add Rancher Helm repo      #
#################################
helm repo add rancher-latest https://releases.rancher.com/server-charts/latest
helm repo update

#################################
# 3) Create cattle-system ns    #
#################################
kubectl create namespace cattle-system --dry-run=client -o yaml | kubectl apply -f -

#################################
# 4) Install cert-manager       #
#################################
# Apply CRDs
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.2/cert-manager.crds.yaml
# Add repo & install chart
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.18.2

# Wait for cert-manager to be ready
kubectl rollout status deployment cert-manager -n cert-manager
kubectl rollout status deployment cert-manager-webhook -n cert-manager
kubectl rollout status deployment cert-manager-cainjector -n cert-manager

#################################
# 5) Install Rancher            #
#################################
helm install rancher rancher-latest/rancher \
  --namespace cattle-system \
  --set hostname=${RANCHER_HOSTNAME} \
  --set bootstrapPassword=admin

# Wait for Rancher to be ready
kubectl -n cattle-system rollout status deploy/rancher

#################################
# 6) Expose Rancher via LB     #
#################################
kubectl expose deployment rancher \
  --name=rancher-lb \
  --port=443 \
  --type=LoadBalancer \
  --namespace=cattle-system

#################################
# 7) Confirm External IP        #
#################################
kubectl get svc rancher-lb -n cattle-system

#################################
# 8) Browse to Rancher UI       #
#################################
echo "→ Rancher should be reachable at:"
echo "   https://${RANCHER_HOSTNAME}"
echo "   or via LoadBalancer IP above (self‑signed cert, add browser exception)"
echo "→ Default admin password: admin (change after first login)"