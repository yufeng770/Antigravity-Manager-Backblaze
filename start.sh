#!/usr/bin/env bash
set -Eeuo pipefail

DATA_DIR=/root/.antigravity_tools
BACKUP_FILE=/tmp/antigravity-backup.tar.gz
B2_KEY_ID="${B2_KEY_ID:-}"
B2_APP_KEY="${B2_APP_KEY:-}"
B2_BUCKET_ID="${B2_BUCKET_ID:-}"
B2_BUCKET_NAME="${B2_BUCKET_NAME:-}"
B2_PREFIX="${B2_PREFIX:-antigravity/backup.tar.gz}"
B2_API=""
B2_TOKEN=""
B2_UPLOAD_URL=""
B2_UPLOAD_TOKEN=""

b2_auth() {
  [[ -n "$B2_KEY_ID" && -n "$B2_APP_KEY" && -n "$B2_BUCKET_ID" ]] || return 1
  local response
  response=$(curl --fail --silent --user "$B2_KEY_ID:$B2_APP_KEY" https://api.backblazeb2.com/b2api/v2/b2_authorize_account)
  B2_API=$(jq -r .apiUrl <<<"$response")
  B2_TOKEN=$(jq -r .authorizationToken <<<"$response")
}

backup() {
  b2_auth || return 0
  tar -czf "$BACKUP_FILE" -C /root .antigravity_tools
  local upload
  upload=$(curl --fail --silent -X POST "$B2_API/b2api/v2/b2_get_upload_url" \
    -H "Authorization: $B2_TOKEN" -d "{\"bucketId\":\"$B2_BUCKET_ID\"}")
  B2_UPLOAD_URL=$(jq -r .uploadUrl <<<"$upload")
  B2_UPLOAD_TOKEN=$(jq -r .authorizationToken <<<"$upload")
  local sha
  sha=$(sha1sum "$BACKUP_FILE" | awk '{print $1}')
  curl --fail --silent --show-error --retry 3 -X POST "$B2_UPLOAD_URL" \
    -H "Authorization: $B2_UPLOAD_TOKEN" -H "X-Bz-File-Name: $B2_PREFIX" \
    -H "Content-Type: application/gzip" -H "X-Bz-Content-Sha1: $sha" \
    --data-binary "@$BACKUP_FILE" >/dev/null
}

restore() {
  b2_auth || return 0
  local response download_url file_id
  response=$(curl --fail --silent -X POST "$B2_API/b2api/v2/b2_list_file_names" \
    -H "Authorization: $B2_TOKEN" -d "{\"bucketId\":\"$B2_BUCKET_ID\",\"prefix\":\"$B2_PREFIX\",\"maxFileCount\":1}") || return 0
  file_id=$(jq -r '.files[0].fileId // empty' <<<"$response")
  [[ -n "$file_id" ]] || return 0
  download_url=$(jq -r .downloadUrl <<<"$response")
  if curl --fail --silent --show-error --location -o "$BACKUP_FILE" \
      "$download_url/file/$B2_BUCKET_NAME/$B2_PREFIX"; then
    tar -xzf "$BACKUP_FILE" -C /
    echo 'B2 backup restored'
  else
    rm -f "$BACKUP_FILE"
  fi
}

restore
"/app/antigravity-tools" --headless &
APP_PID=$!
trap 'kill -TERM "$APP_PID" 2>/dev/null || true; wait "$APP_PID"' TERM INT

while kill -0 "$APP_PID" 2>/dev/null; do
  sleep "${BACKUP_INTERVAL_SECONDS:-900}"
  kill -0 "$APP_PID" 2>/dev/null || break
  backup || echo 'R2 backup failed'
done
wait "$APP_PID"
