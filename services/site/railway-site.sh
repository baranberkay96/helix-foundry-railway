#!/bin/bash
# Site start (Railway): restores the sample chunk from the build's pristine
# copy, writes FOUNDRY_SAMPLE_DB_HOST into it (see the Dockerfile), then runs
# the image's own server (node server.js). Any problem with the sample host
# is logged and the app starts anyway: only "Use the sample" depends on it.
set -uo pipefail

log() { echo "railway-site: $*"; }
warn() { echo "railway-site: WARNING: $*" >&2; }

cd /app || exit 1
readonly UPSTREAM_HOST=acme-db

patch_sample_host() {
	local path host
	path=$(cat /app/.railway/sample-chunk.path 2>/dev/null) || { warn "no sample chunk recorded; Use the sample keeps host $UPSTREAM_HOST"; return; }
	host=${FOUNDRY_SAMPLE_DB_HOST:-}
	if [ -z "$host" ]; then
		warn "FOUNDRY_SAMPLE_DB_HOST is empty; Use the sample keeps host $UPSTREAM_HOST, which does not resolve on Railway"
		host=$UPSTREAM_HOST
	elif [[ ! $host =~ ^[a-z0-9]([a-z0-9.-]{0,251}[a-z0-9])?$ ]]; then
		warn "FOUNDRY_SAMPLE_DB_HOST='$host' is not a host name; Use the sample keeps host $UPSTREAM_HOST"
		host=$UPSTREAM_HOST
	fi
	if ! cp /app/.railway/sample-chunk.pristine "$path"; then
		warn "could not restore $path; Use the sample may connect to an old host"
		return
	fi
	if [ "$host" != "$UPSTREAM_HOST" ] && ! sed -i "s/host:\"$UPSTREAM_HOST\"/host:\"$host\"/" "$path"; then
		warn "could not write the sample host into $path"
		return
	fi
	if grep -qF "host:\"$host\"" "$path"; then
		log "Use the sample connects to $host:5432 (database acme, login acme_reader)"
	else
		warn "the sample host is not in $path; Use the sample may not connect"
	fi
}

patch_sample_host
log "site on ${HOSTNAME:-0.0.0.0}:${PORT:-3000}, API ${HELIX_WFE_ORIGIN:-unset}, origin ${FOUNDRY_ORIGIN:-unset}"
exec node server.js
