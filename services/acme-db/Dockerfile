# Acme DB: the sample company's PostgreSQL database that Foundry's "Use the
# sample" connects to, as upstream's `acme-db` service (local/compose.yaml),
# on Railway's Postgres 18 image (SSL, volume checks) instead of
# postgres:17-alpine on tmpfs.
#
# The data is upstream's local/acme/acme.sql (Apache-2.0, made-up company),
# fetched from the pinned commit and checked against its SHA-256: a changed
# file fails the build instead of loading unknown SQL. It is loaded once, on
# the first boot of the volume, by load-acme.sh.
ARG ACME_DB_IMAGE=ghcr.io/railwayapp-templates/postgres-ssl:18@sha256:4fc833b43d2aaf6ecc9b18615f5533602b723a32d0e2efe2dae8ca0f7217c863
FROM ${ACME_DB_IMAGE}

ADD https://raw.githubusercontent.com/HelixDB/helix-foundry/c900024caa1c65157604d7ee84b1f60d7fbfc00d/local/acme/acme.sql /opt/railway-sample/acme.sql
RUN echo "bce83a6d2ea1bbd815fc72e7d2926b16bb1337e67437e95a3fdeb54c19a053d1  /opt/railway-sample/acme.sql" | sha256sum -c - \
 && chmod 0755 /opt/railway-sample \
 && chmod 0644 /opt/railway-sample/acme.sql \
 && grep -q "^CREATE ROLE acme_reader LOGIN PASSWORD 'acme';$" /opt/railway-sample/acme.sql

# /docker-entrypoint-initdb.d already exists in the base image (0755); the
# script runs as the postgres user, so it must be world-readable and executable.
COPY --chmod=0755 load-acme.sh /docker-entrypoint-initdb.d/50-load-acme.sh
RUN bash -n /docker-entrypoint-initdb.d/50-load-acme.sh
