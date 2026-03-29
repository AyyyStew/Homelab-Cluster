#!/usr/bin/env bash
set -euo pipefail

# Bootstrap script — runs once to install ArgoCD and Sealed Secrets.
# After this, run seal-secrets.sh then apply-root.sh to hand off to GitOps.
#
# Pre-requisites:
#   1. kubeseal CLI installed (yay -S kubeseal)
#   2. kubectl pointing at the cluster

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

# Install Sealed Secrets controller — must exist before sealing secrets
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

echo ""
echo "ArgoCD and Sealed Secrets are ready."
echo "Next: run 'task seal-secrets' then 'task gitops-handoff'"
