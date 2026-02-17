#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ZIP_PATH="${REPO_ROOT}/dist/organic-thoughts.zip"
THEME_NAME="${THEME_NAME:-organic-thoughts}"

if [[ -f "${REPO_ROOT}/.env" ]]; then
  set -a
  source "${REPO_ROOT}/.env"
  set +a
fi

if [[ -z "${GHOST_ADMIN_URL:-}" ]]; then
  echo "Missing GHOST_ADMIN_URL"
  exit 1
fi

if [[ -z "${GHOST_ADMIN_KEY:-}" ]]; then
  echo "Missing GHOST_ADMIN_KEY"
  exit 1
fi

if [[ ! -f "${ZIP_PATH}" ]]; then
  echo "Theme zip not found at ${ZIP_PATH}. Run: bun run theme:zip"
  exit 1
fi

TOKEN="$(
  node -e '
    const crypto = require("crypto");
    const key = process.env.GHOST_ADMIN_KEY || "";
    const [id, secret] = key.split(":");
    if (!id || !secret) {
      console.error("Invalid GHOST_ADMIN_KEY format");
      process.exit(1);
    }
    const iat = Math.floor(Date.now() / 1000);
    const exp = iat + 5 * 60;
    const header = {alg: "HS256", kid: id, typ: "JWT"};
    const payload = {iat, exp, aud: "/admin/"};

    const base64url = (obj) =>
      Buffer.from(JSON.stringify(obj))
        .toString("base64")
        .replace(/=/g, "")
        .replace(/\+/g, "-")
        .replace(/\//g, "_");

    const encodedHeader = base64url(header);
    const encodedPayload = base64url(payload);
    const data = `${encodedHeader}.${encodedPayload}`;
    const signature = crypto
      .createHmac("sha256", Buffer.from(secret, "hex"))
      .update(data)
      .digest("base64")
      .replace(/=/g, "")
      .replace(/\+/g, "-")
      .replace(/\//g, "_");
    process.stdout.write(`${data}.${signature}`);
  '
)"

API_URL="${GHOST_ADMIN_URL%/}/ghost/api/admin/themes/upload/?activate=true"

echo "Uploading and activating theme at ${GHOST_ADMIN_URL%/}"
HTTP_CODE="$(
  curl -sS -o /tmp/organic-thoughts-theme-upload.json -w "%{http_code}" \
    -X POST "${API_URL}" \
    -H "Authorization: Ghost ${TOKEN}" \
    -H "Accept-Version: v6.0" \
    -F "file=@${ZIP_PATH};type=application/zip"
)"

if [[ "${HTTP_CODE}" -lt 200 || "${HTTP_CODE}" -ge 300 ]]; then
  echo "Theme upload failed (HTTP ${HTTP_CODE})."
  cat /tmp/organic-thoughts-theme-upload.json
  exit 1
fi

echo "Theme upload success (HTTP ${HTTP_CODE})."

ACTIVATE_URL="${GHOST_ADMIN_URL%/}/ghost/api/admin/themes/${THEME_NAME}/activate/"
ACTIVATE_CODE="$(
  curl -sS -o /tmp/organic-thoughts-theme-activate.json -w "%{http_code}" \
    -X PUT "${ACTIVATE_URL}" \
    -H "Authorization: Ghost ${TOKEN}" \
    -H "Accept-Version: v6.0"
)"

if [[ "${ACTIVATE_CODE}" -lt 200 || "${ACTIVATE_CODE}" -ge 300 ]]; then
  echo "Theme activation failed (HTTP ${ACTIVATE_CODE})."
  cat /tmp/organic-thoughts-theme-activate.json
  exit 1
fi

echo "Theme activation success (HTTP ${ACTIVATE_CODE})."
cat /tmp/organic-thoughts-theme-activate.json
