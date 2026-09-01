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
B2_DOWNLOAD=""
B2_TOKEN=""
B2_UPLOAD_URL=""
B2_UPLOAD_TOKEN=""

b2_auth() {
  if [[ -z "$B2_KEY_ID" || -z "$B2_APP_KEY" || -z "$B2_BUCKET_ID" || -z "$B2_BUCKET_NAME" ]]; then
    echo '[B2] missing B2 configuration; skipping'
    return 1
  fi
  local response
  response=$(curl --fail --silent --user "$B2_KEY_ID:$B2_APP_KEY" https://api.backblazeb2.com/b2api/v2/b2_authorize_account)
  B2_API=$(jq -r .apiUrl <<<"$response")
  B2_DOWNLOAD=$(jq -r .downloadUrl <<<"$response")
  B2_TOKEN=$(jq -r .authorizationToken <<<"$response")
}

backup() {
  echo "[B2] backup started at $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
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
  echo "[B2] backup upload succeeded ($(stat -c '%s' "$BACKUP_FILE") bytes)"
}

restore() {
  echo '[B2] restore check started'
  b2_auth || return 0
  local response file_id
  response=$(curl --fail --silent -X POST "$B2_API/b2api/v2/b2_list_file_names" \
    -H "Authorization: $B2_TOKEN" -d "{\"bucketId\":\"$B2_BUCKET_ID\",\"prefix\":\"$B2_PREFIX\",\"maxFileCount\":1}") || return 0
  file_id=$(jq -r '.files[0].fileId // empty' <<<"$response")
  if [[ -z "$file_id" ]]; then echo '[B2] no backup found; starting with empty data'; return 0; fi
  if curl --fail --silent --show-error --location -o "$BACKUP_FILE" \
      -H "Authorization: $B2_TOKEN" \
      "$B2_DOWNLOAD/file/$B2_BUCKET_NAME/$B2_PREFIX"; then
    local size
    size=$(stat -c '%s' "$BACKUP_FILE" 2>/dev/null || wc -c < "$BACKUP_FILE")
    echo "[B2] downloaded backup size: ${size} bytes"
    echo '[B2] archive contents (first 30 entries):'
    tar -tzf "$BACKUP_FILE" | head -30 || {
      echo '[B2] downloaded object is not a valid gzip archive'
      rm -f "$BACKUP_FILE"
      return 0
    }
    if ! tar -tzf "$BACKUP_FILE" | grep -qE '^\\.antigravity_tools(/|$)'; then
      echo '[B2] archive does not contain .antigravity_tools; refusing restore'
      rm -f "$BACKUP_FILE"
      return 0
    fi
    tar -xzf "$BACKUP_FILE" -C /
    echo "[B2] restore succeeded (file id $file_id)"
    echo '[B2] restored top-level files:'
    find "$DATA_DIR" -maxdepth 2 -type f -printf '%p (%s bytes)\n' 2>/dev/null | sort || true
    echo '[B2] restored account files:'
    find "$DATA_DIR/accounts" -maxdepth 1 -type f -printf '%f\n' 2>/dev/null | sort || true
    if [[ -f "$DATA_DIR/user_tokens.db" ]]; then
      echo '[B2] restored user token rows:'
      sqlite3 "$DATA_DIR/user_tokens.db" -header -column \
        'SELECT username, enabled FROM user_tokens;' 2>/dev/null || true
    fi
  else
    rm -f "$BACKUP_FILE"
    echo '[B2] restore download failed'
  fi
}

restore
"/app/antigravity-tools" --headless &
APP_PID=$!
trap 'kill -TERM "$APP_PID" 2>/dev/null || true; wait "$APP_PID"' TERM INT

while kill -0 "$APP_PID" 2>/dev/null; do
  sleep "${BACKUP_INTERVAL_SECONDS:-900}"
  kill -0 "$APP_PID" 2>/dev/null || break
  backup || echo '[B2] backup failed'
done
wait "$APP_PID"
