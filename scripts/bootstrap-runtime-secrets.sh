#!/usr/bin/env bash
set -euo pipefail

# Run on the instructor EC2 host after EKS and the eventpass namespace exist.
# The RDS password stays on this host and is written directly to a Kubernetes Secret.
SECRET_ARN="${1:?Usage: $0 <RDS master secret ARN>}"
NAMESPACE="${NAMESPACE:-eventpass}"

kubectl get namespace "$NAMESPACE" >/dev/null
secret_json="$(aws secretsmanager get-secret-value \
  --secret-id "$SECRET_ARN" --query SecretString --output text)"
db_user="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["username"])' <<< "$secret_json")"
db_password="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["password"])' <<< "$secret_json")"
unset secret_json

umask 077
db_env="$(mktemp)"
app_env="$(mktemp)"
cleanup() {
  rm -f "$db_env" "$app_env"
  unset db_password admin_password confirm_password secret_key
}
trap cleanup EXIT

printf 'password=%s\n' "$db_password" > "$db_env"
unset db_password

while true; do
  read -r -s -p 'Choose a temporary organizer password: ' admin_password
  printf '\n'
  read -r -s -p 'Confirm organizer password: ' confirm_password
  printf '\n'
  if [[ -n "$admin_password" && "$admin_password" == "$confirm_password" ]]; then
    break
  fi
  echo 'Passwords did not match or were empty; try again.'
done
unset confirm_password
secret_key="$(openssl rand -hex 32)"
printf 'admin-password=%s\nsecret-key=%s\n' "$admin_password" "$secret_key" > "$app_env"
unset admin_password secret_key

kubectl create secret generic eventpass-db -n "$NAMESPACE" \
  --from-env-file="$db_env" --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic eventpass-app -n "$NAMESPACE" \
  --from-env-file="$app_env" --dry-run=client -o yaml | kubectl apply -f -
echo 'Runtime secrets are ready in the eventpass namespace.'
