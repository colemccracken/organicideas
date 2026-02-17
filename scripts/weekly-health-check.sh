#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
if [[ -f "${REPO_ROOT}/.env" ]]; then
  set -a
  source "${REPO_ROOT}/.env"
  set +a
fi

DOMAIN="${1:-organicideas.me}"
WWW_DOMAIN="www.${DOMAIN}"
CANONICAL_DOMAIN="${CANONICAL_DOMAIN:-${DOMAIN}}"
CHECK_DNS_RESOLVER="${CHECK_DNS_RESOLVER:-1.1.1.1}"
CHECK_DNS_SOURCE="${CHECK_DNS_SOURCE:-authoritative}"
if [[ "${CANONICAL_DOMAIN}" != "${DOMAIN}" && "${CANONICAL_DOMAIN}" != "${WWW_DOMAIN}" ]]; then
  echo "FAIL: CANONICAL_DOMAIN must be ${DOMAIN} or ${WWW_DOMAIN}, got ${CANONICAL_DOMAIN}"
  exit 1
fi

BASE_URL="https://${CANONICAL_DOMAIN}"
TMP_DIR="$(mktemp -d)"
REPORT="${TMP_DIR}/health-report.txt"
SEEN_FILE="${TMP_DIR}/seen-links.txt"
OVERALL_PASS=true
AUTHORITATIVE_NS="$(dig +short NS "${DOMAIN}" | head -n 1 | sed 's/\.$//')"

resolve_ipv4_with_server() {
  local server="$1"
  local host="$2"
  dig +short @"${server}" A "${host}" | rg -m 1 '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || true
}

resolve_cname_with_server() {
  local server="$1"
  local host="$2"
  dig +short @"${server}" CNAME "${host}" | sed 's/\.$//' | head -n 1 || true
}

resolve_ipv4() {
  local host="$1"
  local ip=""
  local cname=""
  if [[ "${CHECK_DNS_SOURCE}" == "authoritative" && -n "${AUTHORITATIVE_NS}" ]]; then
    cname="$(resolve_cname_with_server "${AUTHORITATIVE_NS}" "${host}")"
    if [[ -n "${cname}" ]]; then
      ip="$(resolve_ipv4_with_server "${CHECK_DNS_RESOLVER}" "${cname}")"
    fi
    if [[ -z "${ip}" ]]; then
      ip="$(resolve_ipv4_with_server "${AUTHORITATIVE_NS}" "${host}")"
    fi
  fi
  if [[ -z "${ip}" ]]; then
    ip="$(resolve_ipv4_with_server "${CHECK_DNS_RESOLVER}" "${host}")"
  fi
  echo "${ip}"
}

APEX_IP="$(resolve_ipv4 "${DOMAIN}")"
WWW_IP="$(resolve_ipv4 "${WWW_DOMAIN}")"

ip_for_host() {
  local host="$1"
  if [[ "${host}" == "${DOMAIN}" ]]; then
    echo "${APEX_IP}"
    return
  fi
  if [[ "${host}" == "${WWW_DOMAIN}" ]]; then
    echo "${WWW_IP}"
    return
  fi
}

curl_with_resolve() {
  local url="$1"
  shift
  local host ip port
  host="${url#*://}"
  host="${host%%/*}"
  ip="$(ip_for_host "${host}")"
  if [[ "${url}" == https://* ]]; then
    port=443
  else
    port=80
  fi

  if [[ -n "${ip}" ]]; then
    curl "$@" --resolve "${host}:${port}:${ip}" "${url}"
    return
  fi

  curl "$@" "${url}"
}

cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

echo "Weekly health check for ${DOMAIN} ($(date -u '+%Y-%m-%dT%H:%M:%SZ'))" | tee -a "${REPORT}"
echo "Canonical domain: ${CANONICAL_DOMAIN}" | tee -a "${REPORT}"
echo "DNS source mode: ${CHECK_DNS_SOURCE}" | tee -a "${REPORT}"
echo "DNS resolver for HTTP/TLS checks: ${CHECK_DNS_RESOLVER}" | tee -a "${REPORT}"
echo "Authoritative NS: ${AUTHORITATIVE_NS:-<none>}" | tee -a "${REPORT}"
echo "Resolved apex IP: ${APEX_IP:-<none>}" | tee -a "${REPORT}"
echo "Resolved www IP: ${WWW_IP:-<none>}" | tee -a "${REPORT}"
echo | tee -a "${REPORT}"

echo "[1/4] DNS validation" | tee -a "${REPORT}"
if bash "$(dirname "$0")/check-dns.sh" "${DOMAIN}" >>"${REPORT}" 2>&1; then
  echo "DNS: PASS" | tee -a "${REPORT}"
else
  echo "DNS: FAIL" | tee -a "${REPORT}"
  OVERALL_PASS=false
fi
echo | tee -a "${REPORT}"

echo "[2/4] Launch checks (redirects, TLS, routes)" | tee -a "${REPORT}"
if bash "$(dirname "$0")/verify-ghost-launch.sh" "${DOMAIN}" >>"${REPORT}" 2>&1; then
  echo "Launch checks: PASS" | tee -a "${REPORT}"
else
  echo "Launch checks: FAIL" | tee -a "${REPORT}"
  OVERALL_PASS=false
fi
echo | tee -a "${REPORT}"

echo "[3/4] Internal broken-link scan" | tee -a "${REPORT}"
touch "${SEEN_FILE}"
PAGES=("/" "/about/" "/contact/" "/newsletter/")
BROKEN=0

for page in "${PAGES[@]}"; do
  html="$(curl_with_resolve "${BASE_URL}${page}" -sS 2>/dev/null || true)"
  if [[ -z "${html}" ]]; then
    echo "Broken: ${BASE_URL}${page} (unreachable)" | tee -a "${REPORT}"
    BROKEN=$((BROKEN + 1))
    continue
  fi
  while IFS= read -r href; do
    href="${href%\"}"
    href="${href#\"}"
    if [[ -z "${href}" ]]; then
      continue
    fi
    if [[ "${href}" == "mailto:"* || "${href}" == "tel:"* || "${href}" == "javascript:"* || "${href}" == "#"* || "${href}" == "//"* ]]; then
      continue
    fi
    if [[ "${href}" =~ ^https?:// ]]; then
      if [[ "${href}" != "${BASE_URL}"* ]]; then
        continue
      fi
      target="${href}"
    else
      target="${BASE_URL}${href}"
    fi
    if [[ "${target}" == *"/webmentions/receive/"* ]]; then
      continue
    fi
    if rg -Fx --quiet "${target}" "${SEEN_FILE}" 2>/dev/null; then
      continue
    fi
    echo "${target}" >>"${SEEN_FILE}"
    code="$(curl_with_resolve "${target}" -sS -L -o /dev/null -w '%{http_code}' 2>/dev/null || echo "000")"
    if [[ "${code}" -ge 400 || "${code}" == "000" ]]; then
      echo "Broken: ${target} (${code})" | tee -a "${REPORT}"
      BROKEN=$((BROKEN + 1))
    fi
  done < <(printf '%s' "${html}" | rg -o 'href="[^"]+"' | cut -d'=' -f2-)
done

if [[ "${BROKEN}" -eq 0 ]]; then
  echo "Broken-link scan: PASS" | tee -a "${REPORT}"
else
  echo "Broken-link scan: FAIL (${BROKEN} broken links)" | tee -a "${REPORT}"
  OVERALL_PASS=false
fi
echo | tee -a "${REPORT}"

echo "[4/4] SSL expiry overview" | tee -a "${REPORT}"
for host in "${DOMAIN}" "www.${DOMAIN}"; do
  host_ip="$(ip_for_host "${host}")"
  connect_target="${host}:443"
  if [[ -n "${host_ip}" ]]; then
    connect_target="${host_ip}:443"
  fi
  cert_line="$(echo | openssl s_client -connect "${connect_target}" -servername "${host}" 2>/dev/null | openssl x509 -noout -dates 2>/dev/null | tr '\n' ' ' || true)"
  if [[ -z "${cert_line}" ]]; then
    echo "${host}: certificate unavailable" | tee -a "${REPORT}"
    OVERALL_PASS=false
  else
    echo "${host}: ${cert_line}" | tee -a "${REPORT}"
  fi
done
echo | tee -a "${REPORT}"

echo "Report path: ${REPORT}"
cat "${REPORT}"

if [[ "${OVERALL_PASS}" != true ]]; then
  exit 1
fi
