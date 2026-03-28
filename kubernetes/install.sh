#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load .env if it exists, otherwise fall back to environment variables
if [[ -f "$SCRIPT_DIR/.env" ]]; then
  if [[ "$(stat -c '%a' "$SCRIPT_DIR/.env")" != "600" ]]; then
    echo "WARNING: kubernetes/.env permissions are not 600. Run: chmod 600 kubernetes/.env"
  fi
  set -a; source "$SCRIPT_DIR/.env"; set +a
fi

# Validate required vars
for var in CF_API_TOKEN GRAFANA_PASSWORD LETSENCRYPT_EMAIL; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: $var is not set. Copy .env.example to .env and fill it in."
    exit 1
  fi
done

# Add Helm repos
helm repo add longhorn https://charts.longhorn.io
helm repo add metallb https://metallb.github.io/metallb
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add jetstack https://charts.jetstack.io
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# 1. Longhorn
echo "==> Installing Longhorn..."
kubectl create namespace longhorn-system --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace longhorn-system \
  pod-security.kubernetes.io/enforce=privileged \
  pod-security.kubernetes.io/warn=privileged \
  pod-security.kubernetes.io/audit=privileged \
  --overwrite
helm upgrade --install longhorn longhorn/longhorn \
  --namespace longhorn-system \
  --values "$SCRIPT_DIR/longhorn/values.yaml" \
  --wait

# 2. MetalLB
echo "==> Installing MetalLB..."
kubectl create namespace metallb-system --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace metallb-system \
  pod-security.kubernetes.io/enforce=privileged \
  pod-security.kubernetes.io/warn=privileged \
  pod-security.kubernetes.io/audit=privileged \
  --overwrite
helm upgrade --install metallb metallb/metallb \
  --namespace metallb-system \
  --wait
kubectl apply -f "$SCRIPT_DIR/metallb/ippool.yaml"

# 3. ingress-nginx
echo "==> Installing ingress-nginx..."
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --values "$SCRIPT_DIR/ingress-nginx/values.yaml" \
  --wait

# 4. cert-manager
echo "==> Installing cert-manager..."
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --values "$SCRIPT_DIR/cert-manager/values.yaml" \
  --wait

# Create Cloudflare API token secret
kubectl create secret generic cloudflare-api-token \
  --namespace cert-manager \
  --from-literal=api-token="$CF_API_TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -

# Apply ClusterIssuer with email substituted in
envsubst < "$SCRIPT_DIR/cert-manager/clusterissuer.yaml" | kubectl apply -f -

# 5. kube-prometheus-stack
echo "==> Installing kube-prometheus-stack..."
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace monitoring \
  pod-security.kubernetes.io/enforce=privileged \
  pod-security.kubernetes.io/warn=privileged \
  pod-security.kubernetes.io/audit=privileged \
  --overwrite
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values "$SCRIPT_DIR/monitoring/values.yaml" \
  --set grafana.adminPassword="$GRAFANA_PASSWORD" \
  --wait

echo ""
echo "Done! Ingress IP: $(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
echo "Point grafana.ayyystew.com -> that IP in Cloudflare (proxied, orange cloud)"
