#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMPOSE_FILE="${REPO_ROOT}/docker-compose.local.yml"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required for local Ghost preview."
  exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "docker compose is required (Docker Desktop or Compose plugin)."
  exit 1
fi

mkdir -p "${REPO_ROOT}/local/ghost-content"

docker compose -f "${COMPOSE_FILE}" up -d

cat <<'EOF'
Local Ghost is running.
- Site:  http://localhost:2368
- Admin: http://localhost:2368/ghost

Theme source is mounted from:
- theme/organic-thoughts

First run only:
1. Complete Ghost setup in /ghost.
2. Go to Settings -> Design and activate "organic-thoughts".

Then edit CSS in:
- theme/organic-thoughts/assets/css/screen.css

Refresh the browser to see changes.
EOF
