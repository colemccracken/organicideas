#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

THEME_DIR="${REPO_ROOT}/theme/organic-thoughts"
DIST_DIR="${REPO_ROOT}/dist"
ZIP_PATH="${DIST_DIR}/organic-thoughts.zip"

if ! command -v zip >/dev/null 2>&1; then
  echo "zip command not found. Install zip and retry."
  exit 1
fi

if [[ ! -d "${THEME_DIR}" ]]; then
  echo "Theme directory not found: ${THEME_DIR}"
  exit 1
fi

mkdir -p "${DIST_DIR}"
rm -f "${ZIP_PATH}"

(
  cd "${THEME_DIR}"
  zip -r "${ZIP_PATH}" . -x "*.DS_Store"
)

echo "Created theme zip: ${ZIP_PATH}"
