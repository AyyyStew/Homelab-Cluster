#!/usr/bin/env bash
set -euo pipefail

# Bootstrap script — runs once to install ArgoCD and Sealed Secrets.
# After this, all cluster state is managed via git through ArgoCD.
#
# Pre-requisites:
#   1. kubeseal CLI installed (yay -S kubeseal)
#   2. kubectl pointing at the cluster
#   3. Sealed secrets generated and committed (see seal-secrets.sh)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

helm repo add argo https://argoproj.github.io/argo-helm
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm repo update

# Pre-create namespaces that need privileged pod security before ArgoCD deploys into them
for ns in longhorn-system metallb-system monitoring; do
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
  kubectl label namespace "$ns" \
    pod-security.kubernetes.io/enforce=privileged \
    pod-security.kubernetes.io/warn=privileged \
    pod-security.kubernetes.io/audit=privileged \
    --overwrite
done

# Install Sealed Secrets controller first so secrets can be decrypted when ArgoCD syncs
echo "==> Installing Sealed Secrets..."
helm upgrade --install sealed-secrets sealed-secrets/sealed-secrets \
  --namespace kube-system \
  --wait

# Install ArgoCD
echo "==> Installing ArgoCD..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --version 9.4.17 \
  --values "$SCRIPT_DIR/argocd/values.yaml" \
  --wait

# Hand off to ArgoCD — it deploys everything else from git
echo "==> Applying root app..."
kubectl apply -f "$SCRIPT_DIR/apps/root.yaml"

echo ""
echo "ArgoCD initial admin password:"
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d
echo ""
echo "ArgoCD is now managing the cluster. Watch sync progress at https://argocd.ayyystew.com"
