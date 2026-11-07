# Site: Helix Foundry's web app (Next.js, local build), HelixDB's published
# image pinned by tag and digest. Private: the Gateway is its only entry.
#
# One change, made at start by railway-site.sh: the image has the sample
# database's host, `acme-db` (compose's service name), compiled into one
# browser chunk (NEXT_PUBLIC_SAMPLE_DB_HOST in next.config.ts). On Railway the
# sample database is `<service>.railway.internal`, so "Use the sample" would
# connect to a name that does not resolve. The build keeps a pristine copy of
# that chunk; every start restores it and writes FOUNDRY_SAMPLE_DB_HOST in.
# FOUNDRY_SITE_IMAGE is a service variable (passed to the build as an argument).
ARG FOUNDRY_SITE_IMAGE=ghcr.io/helixdb/foundry-site:0.1.3@sha256:ac69e52df43e99b5c49879399f1f20f475a8fcdf7f43e66f27ca6b6b11da74ae
FROM ${FOUNDRY_SITE_IMAGE}

USER root
# /usr/local/bin exists in the base image, so --chmod only applies to the file.
COPY --chmod=0755 railway-site.sh /usr/local/bin/railway-site.sh

# Exactly one chunk holds the host, exactly once; anything else fails the
# build (another image would need this step re-checked).
RUN set -eu; cd /app; \
    files=$(grep -rlF 'host:"acme-db"' .next/static || true); \
    count=$(printf '%s\n' "$files" | grep -c . || true); \
    [ "$count" -eq 1 ] || { echo "expected 1 chunk with host:\"acme-db\", found $count" >&2; exit 1; }; \
    [ "$(grep -oF 'host:"acme-db"' "$files" | wc -l)" -eq 1 ] || { echo "host:\"acme-db\" occurs more than once in $files" >&2; exit 1; }; \
    mkdir -p /app/.railway; \
    cp -p "$files" /app/.railway/sample-chunk.pristine; \
    printf '%s\n' "$files" > /app/.railway/sample-chunk.path; \
    chown -R node:node /app/.railway; \
    bash -n /usr/local/bin/railway-site.sh

USER node
ENTRYPOINT ["/usr/local/bin/railway-site.sh"]
CMD []
