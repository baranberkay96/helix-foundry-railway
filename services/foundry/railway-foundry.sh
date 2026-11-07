#!/bin/bash
# Foundry service start (Railway). Runs as root only to prepare /work, then
# starts both processes as foundry's user (65532), as upstream's pod does:
#   ontology-agent serve  (gRPC on 127.0.0.1:50051, reads /work)
#   foundry               (REST/MCP :8081, health :8083, workers; writes /work)
# If either exits, the other is stopped and the script exits, so Railway's
# restart policy starts the pair again. SIGTERM is passed to both, which drain.
#
# Variables (template.json documents each):
#   FOUNDRY_LOCAL_TOKEN    owner bearer token -> HELIX_LOCAL__SITE_TOKEN
#   FOUNDRY_S3_SECRET      store secret       -> HELIX_LOCAL__S3__SECRET_ACCESS_KEY
#   FOUNDRY_CONNECTOR_KEY  sealing key        -> HELIX_FOUNDRY__CONNECTORS__CURRENT_KEY
#   FOUNDRY_WORK_MAX_GB    cache cap per draft/load in /work (default 2)
#   FOUNDRY_STARTUP_WAIT_SECONDS  wait for MySQL and the store (default 600)
set -uo pipefail

readonly RUN_ID=65532
readonly WORK=/work

log() { echo "railway-foundry: $*"; }
warn() { echo "railway-foundry: WARNING: $*" >&2; }
die() { echo "railway-foundry: $*" >&2; exit 1; }

# A positive integer from $1, else the default $2 (with a warning if $1 was set).
int_or() {
	local value=$1 fallback=$2 name=$3
	if [[ $value =~ ^[0-9]{1,6}$ ]] && ((10#$value > 0)); then
		echo $((10#$value))
	else
		[ -z "$value" ] || warn "$name=$value is not a positive whole number; using $fallback"
		echo "$fallback"
	fi
}

# 64 hex characters as standard base64 (32 bytes).
hex_to_base64() {
	printf '%b' "$(printf '%s' "$1" | sed 's/../\\x&/g')" | base64 -w0
}

# Foundry wants a 32-byte AES key in strict base64 (config.validateAESKey).
# Accepts that form (a key from an existing install), 64 hex characters (what
# the template generates), or any other value of 32+ characters, hashed.
connector_key() {
	local value=$1
	if [[ $value =~ ^[A-Za-z0-9+/]{42}[AEIMQUYcgkosw048]=$ ]]; then
		printf '%s' "$value"
	elif [[ $value =~ ^[0-9a-fA-F]{64}$ ]]; then
		hex_to_base64 "$value"
	elif [ "${#value}" -ge 32 ]; then
		warn "FOUNDRY_CONNECTOR_KEY is neither base64 of 32 bytes nor 64 hex characters; using its SHA-256 as the key"
		hex_to_base64 "$(printf '%s' "$value" | sha256sum | cut -c1-64)"
	else
		return 1
	fi
}

map_secrets() {
	local token=${FOUNDRY_LOCAL_TOKEN:-${HELIX_LOCAL__SITE_TOKEN:-}}
	[ "${#token}" -ge 32 ] || die "FOUNDRY_LOCAL_TOKEN must be at least 32 characters: it is the owner's bearer token (site and agents). Refusing to start."
	export HELIX_LOCAL__SITE_TOKEN=$token

	local s3=${FOUNDRY_S3_SECRET:-${HELIX_LOCAL__S3__SECRET_ACCESS_KEY:-}}
	[ -n "$s3" ] || die "FOUNDRY_S3_SECRET is empty; it must equal FOUNDRY_S3_SECRET on the Storage service"
	export HELIX_LOCAL__S3__SECRET_ACCESS_KEY=$s3

	if [ -n "${FOUNDRY_CONNECTOR_KEY:-}" ]; then
		local key
		key=$(connector_key "$FOUNDRY_CONNECTOR_KEY") ||
			die "FOUNDRY_CONNECTOR_KEY is shorter than 32 characters. It seals every password and API key given to Foundry; set a long random value (and never change it afterwards)."
		export HELIX_FOUNDRY__CONNECTORS__CURRENT_KEY=$key
	elif [ -z "${HELIX_FOUNDRY__CONNECTORS__CURRENT_KEY:-}" ]; then
		die "FOUNDRY_CONNECTOR_KEY is empty; connectors need it to seal credentials"
	fi
	unset FOUNDRY_LOCAL_TOKEN FOUNDRY_S3_SECRET FOUNDRY_CONNECTOR_KEY
}

configure() {
	# Health and readiness on all interfaces, for Railway's healthcheck (PORT);
	# upstream keeps them on loopback inside its pod.
	export HELIX_LOCAL__LISTEN__HEALTH=${HELIX_LOCAL__LISTEN__HEALTH:-:8083}
	local gb bytes
	gb=$(int_or "${FOUNDRY_WORK_MAX_GB:-}" 2 FOUNDRY_WORK_MAX_GB)
	bytes=$((gb * 1024 * 1024 * 1024))
	export HELIX_FOUNDRY__ONTOLOGY__AGENT__MAX_WORK_BYTES=$bytes
	export HELIX_FOUNDRY__GRAPH__AGENT__MAX_WORK_BYTES=$bytes
	# The agent's thread pools follow the host's cores otherwise.
	local cpus=0 quota period
	if read -r quota period 2>/dev/null </sys/fs/cgroup/cpu.max && [[ $quota =~ ^[0-9]+$ ]] && [[ $period =~ ^[0-9]+$ ]] && ((period > 0)); then
		cpus=$(((quota + period - 1) / period))
	fi
	((cpus > 0)) || cpus=$(nproc)
	((cpus > 8)) && cpus=8
	((cpus < 2)) && cpus=2
	export TOKIO_WORKER_THREADS=${TOKIO_WORKER_THREADS:-$cpus} RAYON_NUM_THREADS=${RAYON_NUM_THREADS:-$cpus}
	export HOME=/home/foundry
	log "S3 store ${HELIX_LOCAL__S3__ENDPOINT:-unset}, HelixDB ${HELIX_LOCAL__HELIX_URL:-unset}, site ${HELIX_LOCAL__SITE_ORIGIN:-unset}, cache cap ${gb} GiB, ${cpus} agent threads"
}

memory_note() {
	local limit
	limit=$(cat /sys/fs/cgroup/memory.max 2>/dev/null || echo max)
	if [[ $limit =~ ^[0-9]+$ ]] && ((limit < 1536 * 1024 * 1024)); then
		warn "this service may use $((limit / 1024 / 1024)) MiB. Foundry and its ontology agent need about 1-2 GB while drafting or loading; on Railway's Free (0.5 GB) or Trial (1 GB) plans those runs can be stopped for lack of memory. Hobby or Pro is recommended."
	fi
}

prepare_work() {
	mkdir -p "$WORK" && chown "$RUN_ID:$RUN_ID" "$WORK" && chmod 0700 "$WORK" ||
		die "cannot prepare $WORK (the Railway volume): check that it is mounted at $WORK"
}

# Waits until MySQL accepts connections and the store answers, up to the
# shared deadline; foundry then migrates and makes its bucket at once.
wait_for_dependencies() {
	local limit deadline hostport host port endpoint code
	limit=$(int_or "${FOUNDRY_STARTUP_WAIT_SECONDS:-}" 600 FOUNDRY_STARTUP_WAIT_SECONDS)
	deadline=$((SECONDS + limit))
	if [[ ${HELIX_DB_DSN:-} =~ @tcp\(([^\)]+)\) ]]; then
		hostport=${BASH_REMATCH[1]} host=${hostport%:*} port=${hostport##*:}
		until timeout 3 bash -c 'exec 3<>"/dev/tcp/$1/$2"' _ "$host" "$port" 2>/dev/null; do
			((signalled)) && return 0
			((SECONDS >= deadline)) && { warn "MySQL at $hostport is not reachable after ${limit}s; starting anyway"; break; }
			log "waiting for MySQL at $hostport"
			sleep 5
		done
	fi
	endpoint=${HELIX_LOCAL__S3__ENDPOINT:-}
	endpoint=${endpoint%/}
	[ -n "$endpoint" ] || return 0
	while ((!signalled)); do
		code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$endpoint/healthz" 2>/dev/null)
		[ "$code" = 200 ] && { log "store answers at $endpoint"; return 0; }
		((SECONDS >= deadline)) && { warn "store at $endpoint did not answer within ${limit}s (HTTP ${code:-none}); starting anyway"; return 0; }
		log "waiting for the store at $endpoint (HTTP ${code:-none})"
		sleep 5
	done
}

as_foundry() {
	setpriv --reuid="$RUN_ID" --regid="$RUN_ID" --clear-groups -- "$@"
}

agent_pid='' foundry_pid='' signalled=0
stop_both() {
	log "stopping foundry and the ontology agent (they finish or hand back work in flight)"
	local pid
	for pid in "$foundry_pid" "$agent_pid"; do
		[ -n "$pid" ] && kill -TERM "$pid" 2>/dev/null
	done
	return 0
}
on_signal() {
	signalled=1
	stop_both
}
# Waits until the process $1 has exited (a signal may interrupt one wait).
reap() {
	[ -n "$1" ] || return 0
	while kill -0 "$1" 2>/dev/null; do
		wait "$1" 2>/dev/null
	done
}

main() {
	cd /home/foundry || die "no /home/foundry"
	map_secrets
	configure
	memory_note
	prepare_work
	trap on_signal TERM INT
	wait_for_dependencies
	((signalled)) && exit 0

	# As local/compose.yaml runs the agent (its loopback address is the default).
	as_foundry /usr/local/bin/ontology-agent serve --files-root "$WORK" \
		--max-concurrent-turns 2 --max-concurrent-reads 8 --max-concurrent-asks 4 \
		--drain-secs 100 --allow-private-model-hosts \
		--max-concurrent-titles 4 --max-concurrent-probes 1 &
	agent_pid=$!
	as_foundry /usr/local/bin/foundry --config /etc/foundry/foundry.yaml &
	foundry_pid=$!
	log "started ontology-agent (pid $agent_pid) and foundry (pid $foundry_pid)"

	local status=0 which=foundry
	wait -n "$agent_pid" "$foundry_pid"
	status=$?
	if ((signalled)); then
		# Railway is stopping this deployment: let both drain, then exit cleanly.
		reap "$foundry_pid"
		reap "$agent_pid"
		exit 0
	fi
	kill -0 "$foundry_pid" 2>/dev/null && which=ontology-agent
	warn "$which exited with status $status; stopping the other so Railway restarts the service"
	stop_both
	reap "$foundry_pid"
	reap "$agent_pid"
	((status == 0)) && status=1
	exit "$status"
}

main "$@"
