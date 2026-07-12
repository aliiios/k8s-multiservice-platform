#!/usr/bin/env bash
set -euo pipefail

NAMESPACE=platform

echo "Creating postgres-credentials Secret..."
echo "You will be prompted for a password (not echoed, not stored in shell history)."

read -srp "Postgres password: " PG_PASSWORD
echo

kubectl create secret generic postgres-credentials \
  --namespace="$NAMESPACE" \
  --from-literal=username=platform_user \
  --from-literal=password="$PG_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Done."
