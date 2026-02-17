#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
if [[ -f "${REPO_ROOT}/.env" ]]; then
  set -a
  source "${REPO_ROOT}/.env"
  set +a
fi

DOMAIN="${1:-organicthoughts.me}"
WWW_DOMAIN="www.${DOMAIN}"
CANONICAL_DOMAIN="${CANONICAL_DOMAIN:-${DOMAIN}}"
CHECK_DNS_RESOLVER="${CHECK_DNS_RESOLVER:-1.1.1.1}"
CHECK_DNS_SOURCE="${CHECK_DNS_SOURCE:-authoritative}"
if [[ "${CANONICAL_DOMAIN}" != "${DOMAIN}" && "${CANONICAL_DOMAIN}" != "${WWW_DOMAIN}" ]]; then
  echo "FAIL: CANONICAL_DOMAIN must be ${DOMAIN} or ${WWW_DOMAIN}, got ${CANONICAL_DOMAIN}"
  exit 1
fi

if [[ "${CANONICAL_DOMAIN}" == "${DOMAIN}" ]]; then
  ALIAS_DOMAIN="${WWW_DOMAIN}"
else
  ALIAS_DOMAIN="${DOMAIN}"
fi

BASE_HTTPS="https://${CANONICAL_DOMAIN}"
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

declare -a REQUIRED_PATHS=(
  "/about/"
  "/contact/"
  "/newsletter/"
  "/sitemap.xml"
)

PASS=true

fail() {
  echo "FAIL: $*"
  PASS=false
}

info() {
  echo "$*"
}

http_code() {
  local url="$1"
  local code
  code="$(curl_with_resolve "${url}" -sS -L -o /dev/null -w "%{http_code}" 2>/dev/null || true)"
  if [[ -z "${code}" ]]; then
    echo "000"
    return
  fi
  echo "${code}"
}

final_url() {
  local url="$1"
  local result
  result="$(curl_with_resolve "${url}" -sS -L -o /dev/null -w "%{url_effective}" 2>/dev/null || true)"
  if [[ -z "${result}" ]]; then
    echo "<unreachable>"
    return
  fi
  echo "${result}"
}

first_response() {
  local url="$1"
  curl_with_resolve "${url}" -sS -I --max-redirs 0 2>/dev/null || true
}

extract_status() {
  awk 'toupper($1) ~ /^HTTP/ {print $2; exit}'
}

extract_location() {
  awk 'tolower($1) == "location:" {$1=""; sub(/^ /, ""); gsub("\r", ""); print; exit}'
}

check_tls() {
  local host="$1"
  local ip connect_target
  ip="$(ip_for_host "${host}")"
  connect_target="${host}:443"
  if [[ -n "${ip}" ]]; then
    connect_target="${ip}:443"
  fi
  info "TLS check for ${host}"
  if ! cert_output="$(echo | openssl s_client -connect "${connect_target}" -servername "${host}" 2>/dev/null | openssl x509 -noout -subject -issuer -dates 2>/dev/null)"; then
    fail "unable to read TLS certificate for ${host}"
    return
  fi
  echo "${cert_output}" | sed 's/^/  /'
}

info "Ghost launch verification ($(date -u '+%Y-%m-%dT%H:%M:%SZ'))"
info "Apex domain: ${DOMAIN}"
info "Canonical domain: ${CANONICAL_DOMAIN}"
info "DNS source mode: ${CHECK_DNS_SOURCE}"
info "DNS resolver for HTTP/TLS checks: ${CHECK_DNS_RESOLVER}"
info "Authoritative NS: ${AUTHORITATIVE_NS:-<none>}"
info "Resolved apex IP: ${APEX_IP:-<none>}"
info "Resolved www IP: ${WWW_IP:-<none>}"
echo

info "1) Redirect checks"
http_apex_head="$(first_response "http://${DOMAIN}")"
http_www_head="$(first_response "http://${WWW_DOMAIN}")"
https_alias_head="$(first_response "https://${ALIAS_DOMAIN}")"

http_apex_status="$(printf '%s\n' "${http_apex_head}" | extract_status)"
http_apex_location="$(printf '%s\n' "${http_apex_head}" | extract_location)"
http_www_status="$(printf '%s\n' "${http_www_head}" | extract_status)"
http_www_location="$(printf '%s\n' "${http_www_head}" | extract_location)"
https_alias_status="$(printf '%s\n' "${https_alias_head}" | extract_status)"
https_alias_location="$(printf '%s\n' "${https_alias_head}" | extract_location)"

info "  http://${DOMAIN} -> status ${http_apex_status:-unknown} location ${http_apex_location:-<none>}"
info "  http://${WWW_DOMAIN} -> status ${http_www_status:-unknown} location ${http_www_location:-<none>}"
info "  https://${ALIAS_DOMAIN} -> status ${https_alias_status:-unknown} location ${https_alias_location:-<none>}"

if [[ -z "${http_apex_status}" || "${http_apex_status}" =~ ^2 ]]; then
  fail "http://${DOMAIN} should redirect to HTTPS"
fi

if [[ -z "${http_www_status}" || "${http_www_status}" =~ ^2 ]]; then
  fail "http://${WWW_DOMAIN} should redirect"
fi

if [[ ! "${https_alias_status:-}" =~ ^30[1278]$ ]]; then
  fail "https://${ALIAS_DOMAIN} should return a redirect status"
fi

if [[ "${https_alias_location:-}" != "https://${CANONICAL_DOMAIN}/" && "${https_alias_location:-}" != "https://${CANONICAL_DOMAIN}" ]]; then
  fail "https://${ALIAS_DOMAIN} should redirect to https://${CANONICAL_DOMAIN}/"
fi

canonical_final="$(final_url "https://${CANONICAL_DOMAIN}")"
alias_final="$(final_url "https://${ALIAS_DOMAIN}")"
info "  Final URL for https://${CANONICAL_DOMAIN}: ${canonical_final}"
info "  Final URL for https://${ALIAS_DOMAIN}: ${alias_final}"
if [[ "${canonical_final}" != "https://${CANONICAL_DOMAIN}/" && "${canonical_final}" != "https://${CANONICAL_DOMAIN}" ]]; then
  fail "final URL for https://${CANONICAL_DOMAIN} should resolve to canonical host"
fi
if [[ "${alias_final}" != "https://${CANONICAL_DOMAIN}/" && "${alias_final}" != "https://${CANONICAL_DOMAIN}" ]]; then
  fail "final URL for https://${ALIAS_DOMAIN} should resolve to canonical host"
fi

echo
info "2) TLS checks"
check_tls "${DOMAIN}"
check_tls "${WWW_DOMAIN}"

echo
info "3) Required page/status checks"
for route in "${REQUIRED_PATHS[@]}"; do
  url="${BASE_HTTPS}${route}"
  code="$(http_code "${url}")"
  info "  ${url} -> ${code}"
  if [[ ! "${code}" =~ ^[0-9]{3}$ || "${code}" -lt 200 || "${code}" -ge 400 ]]; then
    fail "${url} returned ${code}"
  fi
done

echo
info "4) Membership portal surface check"
portal_code="$(http_code "${BASE_HTTPS}/#/portal/signup")"
info "  ${BASE_HTTPS}/#/portal/signup -> ${portal_code}"
if [[ ! "${portal_code}" =~ ^[0-9]{3}$ || "${portal_code}" -lt 200 || "${portal_code}" -ge 400 ]]; then
  fail "Portal signup route returned ${portal_code}"
fi

echo
if [[ "${PASS}" == true ]]; then
  info "Overall result: PASS"
else
  info "Overall result: FAIL"
  exit 1
fi
