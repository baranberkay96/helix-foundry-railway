#!/bin/sh
# Gateway start (Railway): hashes the basic-auth password (Caddy needs a
# bcrypt hash; the plain password lives only in the Railway variable),
# normalises the switches, then runs Caddy with this template's Caddyfile.
set -eu

log() { echo "railway-gateway: $*"; }
warn() { echo "railway-gateway: WARNING: $*" >&2; }
die() { echo "railway-gateway: $*" >&2; exit 1; }

: "${FOUNDRY_SITE_UPSTREAM:?FOUNDRY_SITE_UPSTREAM must be set (e.g. site.railway.internal:3000)}"
: "${FOUNDRY_API_UPSTREAM:?FOUNDRY_API_UPSTREAM must be set (e.g. foundry.railway.internal:8081)}"

password=${BASIC_AUTH_PASSWORD:-}
# Fail closed without failing the deploy: Foundry has no sign-in of its own, so an
# unusable password (under 12 characters, or over bcrypt's 72 bytes) locks the
# whole install with a random password nobody knows.
if [ "${#password}" -lt 12 ] || [ "$(printf '%s' "$password" | wc -c)" -gt 72 ]; then
	warn "BASIC_AUTH_PASSWORD must be 12-72 characters. The site is locked until you set it in the Gateway service Variables and redeploy."
	password=$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')
fi

user=${BASIC_AUTH_USERNAME:-}
case "$user" in
'' | *[!A-Za-z0-9._@-]*)
	warn "BASIC_AUTH_USERNAME='$user' is empty or has characters other than A-Z a-z 0-9 . _ @ -; using 'admin'"
	user=admin
	;;
esac
BASIC_AUTH_USERNAME=$user

case "$(printf '%s' "${FOUNDRY_AGENT_ENDPOINTS:-on}" | tr 'A-Z' 'a-z')" in
on | true | yes | 1) FOUNDRY_AGENT_ENDPOINTS=on ;;
off | false | no | 0) FOUNDRY_AGENT_ENDPOINTS=off ;;
*)
	warn "FOUNDRY_AGENT_ENDPOINTS='${FOUNDRY_AGENT_ENDPOINTS}' is not on or off; using on"
	FOUNDRY_AGENT_ENDPOINTS=on
	;;
esac

BASIC_AUTH_HASH=$(caddy hash-password --plaintext "$password")
unset BASIC_AUTH_PASSWORD password
export BASIC_AUTH_USERNAME BASIC_AUTH_HASH FOUNDRY_AGENT_ENDPOINTS

log "basic auth for user $BASIC_AUTH_USERNAME; site $FOUNDRY_SITE_UPSTREAM; MCP and HTTP Ask $FOUNDRY_AGENT_ENDPOINTS ($FOUNDRY_API_UPSTREAM); port ${PORT:-8080}"
exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile
