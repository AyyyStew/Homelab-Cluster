#!/usr/bin/env bash
set -euo pipefail

# Run this after a cluster rebuild to re-seal secrets and commit them.
# Requires: kubeseal CLI, kubectl pointing at the cluster, .env filled in.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "$SCRIPT_DIR/.env" ]]; then
  set -a; source "$SCRIPT_DIR/.env"; set +a
fi

for var in CF_API_TOKEN GRAFANA_PASSWORD; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: $var is not set in .env"
    exit 1
  fi
done

echo "==> Sealing Cloudflare API token..."
kubectl create secret generic cloudflare-api-token \
  --namespace cert-manager \
  --from-literal=api-token="$CF_API_TOKEN" \
  --dry-run=client -o yaml \
  | kubeseal --format yaml --controller-name sealed-secrets --controller-namespace kube-system \
  > "$SCRIPT_DIR/secrets/cloudflare-api-token.yaml"

echo "==> Sealing Grafana admin secret..."
kubectl create secret generic grafana-admin-secret \
  --namespace monitoring \
  --from-literal=admin-user=admin \
  --from-literal=admin-password="$GRAFANA_PASSWORD" \
  --dry-run=client -o yaml \
  | kubeseal --format yaml --controller-name sealed-secrets --controller-namespace kube-system \
  > "$SCRIPT_DIR/secrets/grafana-admin-secret.yaml"

echo ""
echo "Done. Commit the updated files in kubernetes/secrets/ to git."
echo "ArgoCD will apply them automatically on next sync."
