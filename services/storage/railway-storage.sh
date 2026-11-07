#!/bin/sh
# Storage service start (Railway): SeaweedFS as upstream's local/compose.yaml
# runs it (`weed server` with master, volume and filer on loopback, only the
# S3 API on the network), with one identity, `foundry`, whose secret is
# FOUNDRY_S3_SECRET. Differences from upstream, all for Railway:
#   - S3 binds 0.0.0.0:8333, reached through this service's public domain
#     (Railway's healthcheck and edge use IPv4);
#   - CORS allows the Gateway's origin(s) (STORAGE_ALLOWED_ORIGINS), the
#     page that PUTs uploads; upstream allows http://localhost:3000;
#   - volumes of STORAGE_VOLUME_SIZE_MB (default 256), so a 5 GB Railway
#     volume holds about 18 of them (upstream: 1 GB on a laptop's disk);
#   - -s3.externalUrl is this service's public URL, tried first when checking
#     signatures behind Railway's proxy;
#   - like the image's own entrypoint, /data is given to the `seaweed` user
#     and the server runs as that user (upstream runs it as root).
set -eu

log() { echo "railway-storage: $*"; }
warn() { echo "railway-storage: WARNING: $*" >&2; }
die() { echo "railway-storage: $*" >&2; exit 1; }

DATA=/data
PORT_S3=8333

secret=${FOUNDRY_S3_SECRET:-}
[ "${#secret}" -ge 16 ] || die "FOUNDRY_S3_SECRET must be at least 16 characters (Foundry signs every S3 request with it). Refusing to start."
case "$secret" in
*[!A-Za-z0-9._~+/=-]*) die "FOUNDRY_S3_SECRET may only contain letters, digits and . _ ~ + / = -" ;;
esac

# Comma-separated http(s) origins without paths; anything else is dropped.
origins=''
old_ifs=$IFS
IFS=','
for origin in ${STORAGE_ALLOWED_ORIGINS:-}; do
	origin=$(printf '%s' "$origin" | tr -d ' \t')
	case "$origin" in
	'') ;;
	http://*/* | https://*/*) warn "ignoring allowed origin $origin (an origin has no path)" ;;
	http://?* | https://?*)
		case "$origin" in
		*[!A-Za-z0-9.:/_-]*) warn "ignoring allowed origin $origin (unexpected characters)" ;;
		*) origins="${origins:+$origins,}$origin" ;;
		esac
		;;
	*) warn "ignoring allowed origin $origin (not an http(s) origin)" ;;
	esac
done
IFS=$old_ifs
if [ -z "$origins" ]; then
	warn "STORAGE_ALLOWED_ORIGINS has no valid origin; allowing every origin (uploads still need Foundry's signature)"
	origins='*'
fi

size=${STORAGE_VOLUME_SIZE_MB:-256}
case "$size" in
'' | *[!0-9]*) warn "STORAGE_VOLUME_SIZE_MB=$size is not a number; using 256"; size=256 ;;
esac
if [ "$size" -lt 64 ] || [ "$size" -gt 30000 ]; then
	warn "STORAGE_VOLUME_SIZE_MB=$size is outside 64-30000; using 256"
	size=256
fi

set -- -dir="$DATA" -ip=127.0.0.1 -ip.bind=127.0.0.1 \
	-s3 -s3.ip.bind=0.0.0.0 -s3.port="$PORT_S3" -s3.config=/tmp/s3.json \
	-s3.allowedOrigins="$origins" \
	-master.volumeSizeLimitMB="$size" -volume.max=0
if [ -n "${RAILWAY_PUBLIC_DOMAIN:-}" ]; then
	set -- "$@" -s3.externalUrl="https://${RAILWAY_PUBLIC_DOMAIN}"
else
	warn "this service has no public domain: browsers cannot upload documents, and Foundry's HELIX_LOCAL__S3__ENDPOINT must point at it"
fi

mkdir -p "$DATA"
run_as=''
if [ "$(id -u)" = 0 ] && id -u seaweed >/dev/null 2>&1 && command -v su-exec >/dev/null 2>&1; then
	if [ "$(stat -c '%U' "$DATA")" != seaweed ]; then
		log "giving $DATA to the seaweed user"
		chown -R seaweed:seaweed "$DATA" || warn "could not chown $DATA; SeaweedFS may fail to write"
	fi
	run_as=seaweed
fi

umask 077
printf '{"identities":[{"name":"foundry","credentials":[{"accessKey":"foundry","secretKey":"%s"}],"actions":["Admin","Read","Write","List","Tagging"]}]}' "$secret" >/tmp/s3.json
[ -n "$run_as" ] && chown seaweed:seaweed /tmp/s3.json
unset FOUNDRY_S3_SECRET secret

log "S3 on :$PORT_S3 for origins $origins, volumes of ${size} MB in $DATA${run_as:+, as $run_as}"
if [ -n "$run_as" ]; then
	exec su-exec "$run_as" weed server "$@"
fi
exec weed server "$@"
