#!/usr/bin/env bash
set -euo pipefail

required_env() {
  local name="$1"

  if [[ -z "${!name:-}" ]]; then
    echo "Missing required environment variable: $name" >&2
    exit 1
  fi
}

required_env GARAGE_ACCESS_KEY
required_env GARAGE_SECRET_KEY
required_env GARAGE_BUCKET
required_env GARAGE_ENDPOINT_URL

export AWS_ACCESS_KEY_ID="$GARAGE_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$GARAGE_SECRET_KEY"
export AWS_DEFAULT_REGION="${GARAGE_REGION:-garage}"

prefix="${GARAGE_PREFIX:-acquisition/}"
object_key="${prefix%/}/smoke/garage-smoke-$(date +%Y%m%d%H%M%S)-$$.txt"
upload_file="$(mktemp)"
download_file="$(mktemp)"

cleanup() {
  rm -f "$upload_file" "$download_file"
}

trap cleanup EXIT

printf 'gnome-garden garage smoke %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$upload_file"

aws_s3api() {
  aws --endpoint-url "$GARAGE_ENDPOINT_URL" s3api "$@"
}

aws_s3api head-bucket --bucket "$GARAGE_BUCKET" >/dev/null
aws_s3api put-object --bucket "$GARAGE_BUCKET" --key "$object_key" --body "$upload_file" >/dev/null
aws_s3api get-object --bucket "$GARAGE_BUCKET" --key "$object_key" "$download_file" >/dev/null

if ! cmp -s "$upload_file" "$download_file"; then
  echo "Garage smoke failed: downloaded object did not match upload." >&2
  exit 1
fi

aws_s3api delete-object --bucket "$GARAGE_BUCKET" --key "$object_key" >/dev/null

echo "Garage smoke passed for s3://$GARAGE_BUCKET/$object_key"
