#!/bin/bash
# Acme DB, first boot only (official postgres entrypoint, initdb phase; runs as
# the postgres user against the temporary, socket-only server).
#
# 1. Loads upstream's acme.sql into POSTGRES_DB: six tables (accounts,
#    contacts, subscriptions, invoices, support_tickets, product_usage) and
#    the login acme_reader / acme with SELECT on them. Foundry's site has that
#    database name, login and password built in ("Use the sample"), so they
#    stay as upstream ships them; the data is made up and this database has
#    no public domain or TCP proxy.
# 2. Narrows acme_reader to what upstream intends ("can only select"):
#    read-only transactions, a statement timeout, and no CONNECT on the
#    server's other databases.
#
# Later boots skip this file (the data directory already exists).
set -euo pipefail

# As the entrypoint's own docker_process_sql: Railway sets PGHOST to this
# service's private domain, but during initdb the server only listens on the
# local socket.
unset PGHOST PGHOSTADDR

SQL=/opt/railway-sample/acme.sql
DB="${POSTGRES_DB:?POSTGRES_DB is required}"

log() { echo "load-acme: $*"; }
run_psql() { psql -v ON_ERROR_STOP=1 --no-psqlrc --quiet --username "$POSTGRES_USER" "$@"; }

[ "$DB" = acme ] || log "WARNING: POSTGRES_DB is '$DB', but Foundry's sample connects to the database 'acme'; Use the sample will not find its tables"

# Nothing in the file may switch or create databases.
if grep -qiE '^[[:space:]]*(\\c(onnect)?[[:space:]]|(create|drop)[[:space:]]+database)' "$SQL"; then
	log "acme.sql switches or creates databases; refusing to load it" >&2
	exit 1
fi

log "loading Acme Corp's sample tables into $DB"
run_psql --dbname "$DB" -f "$SQL"

log "limiting acme_reader to read-only access to $DB"
run_psql --dbname "$DB" -v db="$DB" <<'SQL'
ALTER ROLE acme_reader NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;
ALTER ROLE acme_reader SET default_transaction_read_only = on;
ALTER ROLE acme_reader SET statement_timeout = '60s';
REVOKE ALL ON DATABASE :"db" FROM PUBLIC;
GRANT CONNECT ON DATABASE :"db" TO acme_reader;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
REVOKE CONNECT ON DATABASE postgres FROM PUBLIC;
SQL

counts=$(run_psql --dbname "$DB" -tA -c "SELECT (SELECT count(*) FROM accounts) || ' accounts, ' || (SELECT count(*) FROM invoices) || ' invoices, ' || (SELECT count(*) FROM support_tickets) || ' support tickets'")
log "done: $counts; login acme_reader can read database $DB"
