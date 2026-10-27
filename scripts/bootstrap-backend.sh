#!/usr/bin/env bash
# One-time bootstrap of Terraform remote state in Yandex Cloud:
#   * service account for CI with storage.editor + ydb.editor
#   * versioned, encrypted Object Storage bucket tfstate-<cloud_id>
#   * serverless YDB with DynamoDB-compatible table for state locking
# Idempotent: re-running skips existing resources.
set -Eeuo pipefail

: "${YC_CLOUD_ID:?set YC_CLOUD_ID}"
: "${YC_FOLDER_ID:?set YC_FOLDER_ID (folder for shared infra)}"

BUCKET="tfstate-${YC_CLOUD_ID}"
SA_NAME="terraform-ci"
YDB_NAME="tfstate-lock"
KMS_KEY_NAME="tfstate"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

need() { command -v "$1" >/dev/null || { echo "missing dependency: $1" >&2; exit 1; }; }
need yc; need jq; need aws

yc config set folder-id "$YC_FOLDER_ID" >/dev/null

log "Service account ${SA_NAME}"
if ! yc iam service-account get "$SA_NAME" >/dev/null 2>&1; then
  yc iam service-account create --name "$SA_NAME" --description "Terraform in GitLab CI"
fi
SA_ID="$(yc iam service-account get "$SA_NAME" --format json | jq -r .id)"

for role in storage.editor ydb.editor kms.keys.encrypterDecrypter; do
  yc resource-manager folder add-access-binding "$YC_FOLDER_ID" \
    --role "$role" --subject "serviceAccount:${SA_ID}" >/dev/null 2>&1 || true
done

log "KMS key ${KMS_KEY_NAME}"
if ! yc kms symmetric-key get "$KMS_KEY_NAME" >/dev/null 2>&1; then
  yc kms symmetric-key create --name "$KMS_KEY_NAME" --default-algorithm aes-256 --rotation-period 8760h
fi
KMS_KEY_ID="$(yc kms symmetric-key get "$KMS_KEY_NAME" --format json | jq -r .id)"

log "Bucket ${BUCKET}"
if ! yc storage bucket get "$BUCKET" >/dev/null 2>&1; then
  yc storage bucket create --name "$BUCKET" --default-storage-class standard
fi
yc storage bucket update --name "$BUCKET" --versioning versioning-enabled >/dev/null
yc storage bucket update --name "$BUCKET" \
  --encryption "key-id=${KMS_KEY_ID}" >/dev/null

log "Serverless YDB ${YDB_NAME}"
if ! yc ydb database get "$YDB_NAME" >/dev/null 2>&1; then
  yc ydb database create --name "$YDB_NAME" --serverless
fi
DOCAPI="$(yc ydb database get "$YDB_NAME" --format json | jq -r .document_api_endpoint)"

log "Static key for S3/DynamoDB API"
KEY_JSON="$(yc iam access-key create --service-account-id "$SA_ID" --format json)"
export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
AWS_ACCESS_KEY_ID="$(jq -r .access_key.key_id <<<"$KEY_JSON")"
AWS_SECRET_ACCESS_KEY="$(jq -r .secret <<<"$KEY_JSON")"

log "Lock table"
if ! aws dynamodb describe-table --endpoint-url "$DOCAPI" --region ru-central1 --table-name tfstate-lock >/dev/null 2>&1; then
  aws dynamodb create-table --endpoint-url "$DOCAPI" --region ru-central1 \
    --table-name tfstate-lock \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH >/dev/null
fi

OUT="$(mktemp -t tfstate-ci-vars.XXXXXX)"
chmod 600 "$OUT"
cat > "$OUT" <<EOF
AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
TF_STATE_LOCK_ENDPOINT=${DOCAPI}
EOF

log "Done. CI variables written to ${OUT} (mode 600)."
log "Add them as masked/protected GitLab CI variables, then delete the file."
