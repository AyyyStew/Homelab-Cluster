#!/usr/bin/env bash
set -euo pipefail

# Applies the ArgoCD root app — hands cluster management to GitOps.
# Run this after seal-secrets.sh has committed sealed secrets to git.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

kubectl apply -f "$SCRIPT_DIR/apps/root.yaml"

echo ""
echo "ArgoCD is now managing the cluster. Watch sync progress at https://argocd.ayyystew.com"
echo ""
echo "ArgoCD initial admin password:"
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d
echo ""
