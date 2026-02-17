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
RESOLVERS=("1.1.1.1" "8.8.8.8")

EXPECTED_APEX_A="${EXPECTED_APEX_A:-}"
EXPECTED_APEX_CNAME="${EXPECTED_APEX_CNAME:-}"
EXPECTED_WWW_CNAME="${EXPECTED_WWW_CNAME:-}"

pass=true
apex_a_any_match=true
apex_cname_any_match=true
www_cname_any_match=true
apex_a_partial=false
apex_cname_partial=false
www_cname_partial=false

if [[ -n "${EXPECTED_APEX_A}" ]]; then
  apex_a_any_match=false
fi
if [[ -n "${EXPECTED_APEX_CNAME}" ]]; then
  apex_cname_any_match=false
fi
if [[ -n "${EXPECTED_WWW_CNAME}" ]]; then
  www_cname_any_match=false
fi

trim() {
  awk '{$1=$1};1'
}

normalize_dns() {
  tr '[:upper:]' '[:lower:]' | sed 's/\.$//'
}

check_expected_contains() {
  local actual="$1"
  local expected_csv="$2"
  IFS=',' read -r -a expected_values <<<"${expected_csv}"
  for expected in "${expected_values[@]}"; do
    local norm
    norm="$(printf '%s' "${expected}" | trim | normalize_dns)"
    if [[ -n "${norm}" && "${actual}" == "${norm}" ]]; then
      return 0
    fi
  done
  return 1
}

print_header() {
  echo "DNS check for ${DOMAIN} ($(date -u '+%Y-%m-%dT%H:%M:%SZ'))"
  echo "Resolvers: ${RESOLVERS[*]}"
  echo
}

print_expected() {
  echo "Expected values (optional):"
  echo "  EXPECTED_APEX_A=${EXPECTED_APEX_A:-<not set>}"
  echo "  EXPECTED_APEX_CNAME=${EXPECTED_APEX_CNAME:-<not set>}"
  echo "  EXPECTED_WWW_CNAME=${EXPECTED_WWW_CNAME:-<not set>}"
  echo
}

print_header
print_expected

for resolver in "${RESOLVERS[@]}"; do
  echo "Resolver @${resolver}"

  apex_a="$(dig +short @"${resolver}" A "${DOMAIN}" | trim)"
  apex_cname="$(dig +short @"${resolver}" CNAME "${DOMAIN}" | trim | normalize_dns)"
  www_a="$(dig +short @"${resolver}" A "${WWW_DOMAIN}" | trim)"
  www_cname="$(dig +short @"${resolver}" CNAME "${WWW_DOMAIN}" | trim | normalize_dns)"

  echo "  ${DOMAIN} A: ${apex_a:-<none>}"
  echo "  ${DOMAIN} CNAME: ${apex_cname:-<none>}"
  echo "  ${WWW_DOMAIN} A: ${www_a:-<none>}"
  echo "  ${WWW_DOMAIN} CNAME: ${www_cname:-<none>}"

  if [[ -n "${EXPECTED_APEX_A}" ]]; then
    local_match=false
    while IFS= read -r actual; do
      actual_norm="$(printf '%s' "${actual}" | trim | normalize_dns)"
      if check_expected_contains "${actual_norm}" "${EXPECTED_APEX_A}"; then
        local_match=true
      fi
    done <<<"${apex_a}"
    if [[ "${local_match}" != true ]]; then
      echo "  WARN: apex A does not match EXPECTED_APEX_A on this resolver"
      apex_a_partial=true
    else
      apex_a_any_match=true
    fi
  fi

  if [[ -n "${EXPECTED_APEX_CNAME}" ]]; then
    if check_expected_contains "${apex_cname}" "${EXPECTED_APEX_CNAME}"; then
      apex_cname_any_match=true
    else
      echo "  WARN: apex CNAME does not match EXPECTED_APEX_CNAME on this resolver"
      apex_cname_partial=true
    fi
  fi

  if [[ -n "${EXPECTED_WWW_CNAME}" ]]; then
    if check_expected_contains "${www_cname}" "${EXPECTED_WWW_CNAME}"; then
      www_cname_any_match=true
    else
      echo "  WARN: www CNAME does not match EXPECTED_WWW_CNAME on this resolver"
      www_cname_partial=true
    fi
  fi

  echo
done

if [[ "${apex_a_any_match}" != true ]]; then
  echo "FAIL: apex A did not match EXPECTED_APEX_A on any checked resolver"
  pass=false
fi
if [[ "${apex_cname_any_match}" != true ]]; then
  echo "FAIL: apex CNAME did not match EXPECTED_APEX_CNAME on any checked resolver"
  pass=false
fi
if [[ "${www_cname_any_match}" != true ]]; then
  echo "FAIL: www CNAME did not match EXPECTED_WWW_CNAME on any checked resolver"
  pass=false
fi

if [[ "${apex_a_partial}" == true || "${apex_cname_partial}" == true || "${www_cname_partial}" == true ]]; then
  echo "NOTE: DNS is partially propagated across resolvers."
fi

if [[ "${pass}" == true ]]; then
  echo "DNS check: PASS"
else
  echo "DNS check: FAIL"
  exit 1
fi
