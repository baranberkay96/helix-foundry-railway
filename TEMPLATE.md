# Helix Foundry 0.1 Ontology and Knowledge Graph from Your Data — Railway template spec

## Listing

| Field | Value |
|---|---|
| Name | **Helix Foundry 0.1 Ontology and Knowledge Graph from Your Data** (`0.1` = major.minor of the release images the pinned commit runs: site 0.1.3, foundry 0.1.2, agent 0.1.1; upstream has no GitHub releases, but it does publish versioned images, so the snapshot label "2026.11" was not needed) |
| Description | Connect databases and documents; an AI agent maps them into one graph. (70 chars) |
| Category | AI/ML |
| Tags | helix-foundry, helixdb, ontology, knowledge-graph, graph-database, ai-agents, mcp, data-integration |
| Icon | `https://cdn.jsdelivr.net/npm/lucide-static@1.59.0/icons/waypoints.svg` (neutral Lucide icon, ISC; no HelixDB logo) |
| Repo | `baranberkay96/helix-foundry-railway`, services in `/services/<svc>` |
| User input at deploy | **None required.** Optional: `ANTHROPIC_API_KEY` / `OPENAI_API_KEY` on Foundry (keys can instead be entered in Settings › AI models). |

## Base market templates

No Helix Foundry template exists on Railway (`_market/` is empty; task note: "No Railway competitor has users"). Built from upstream's `local/compose.yaml` at the pinned commit and HelixDB's published images.

## Pinned versions

| Service | Source | Version | Built | Checked |
|---|---|---|---|---|
| Site | `ghcr.io/helixdb/foundry-site:0.1.3@sha256:ac69e52d…74ae` (amd64 `sha256:6a18d512…b221`) + `services/site` | 0.1.3 (Next.js 16.3.8) | 2026-11-05 | 2026-11-07 |
| Foundry | `ghcr.io/helixdb/ontology-agent:0.1.1@sha256:d5a543be…faa8` (amd64 `6c475028…713a`) + foundry binary from `ghcr.io/helixdb/foundry:0.1.2@sha256:5adf4ca9…ba62` (amd64 `8a705ca2…be0e`) | agent 0.1.1, foundry 0.1.2 | 2026-11-05 | 2026-11-07 |
| HelixDB | `ghcr.io/helixdb/helixdb:v0.0.14@sha256:1470a3bc…f62a` | v0.0.14 | 2026-11-06 | 2026-11-07 |
| Storage | `chrislusf/seaweedfs:4.47@sha256:ce9e796f…f882` + `services/storage` | 4.47 | 2026-09-14 | 2026-11-07 |
| MySQL | `mysql:8.0.46@sha256:7dcddc01…ae2b` (Railway MySQL base, upstream's pin) | 8.0.46 | 2026-05-04 | 2026-11-07 |
| Acme DB | `ghcr.io/railwayapp-templates/postgres-ssl:18@sha256:4fc833b4…c863` + `acme.sql` (sha256 `bce83a6d…53d1`) | PostgreSQL 18.6 | 2026-10-23 | 2026-11-07 |
| Gateway | `caddy:2.11.9-alpine@sha256:0bbb055b…9fee` + `services/gateway` | 2.11.9 | 2026-11-05 | 2026-11-07 |

- **Pinned commit `c900024caa1c65157604d7ee84b1f60d7fbfc00d`** (2026-11-06, head of `main` on 2026-11-07). Its `local/compose.yaml` names exactly the images above (foundry 0.1.2, site 0.1.3, agent 0.1.1, HelixDB v0.0.14, SeaweedFS 4.47, MySQL 8.0.46). The site and foundry images carry `org.opencontainers.image.revision = c7de40515f56`; `compare c7de4051...c900024c` shows two commits touching only `local/compose.yaml`, `local/README.md` and one test, so the images are the pinned code. No source build is needed.
- The `foundry.yaml` baked into the 0.1.2 image is byte-identical to `backend/cmd/foundry/foundry.yaml` at the pin.
- The ontology agent's source is not public; its image is labelled and licensed Apache-2.0 (LICENSE file in the image).

## Architecture

```
Browser ─HTTPS─▶ Gateway (Caddy, basic auth)                                  public :8080
                  ├─ /mcp, /v1/ontologies/* (bearer FOUNDRY_LOCAL_TOKEN) ─▶ Foundry :8081
                  └─ everything else, Host/Origin rewritten to localhost:3000 ─▶ Site :3000
Site (Next.js, local mode) ─ /papi + owner token ─▶ Foundry :8081 (REST gateway)
Foundry container: foundry (API, MCP, sync/document/ontology/graph/ask workers; health :8083)
                   + ontology-agent (gRPC 127.0.0.1:50051), sharing volume /work
Foundry ─▶ MySQL :3306 (store, migrated at start) · HelixDB :8080 (graph) · Acme DB :5432 (sample connector)
Foundry ─HTTPS─▶ Storage public URL (S3, path-style, bucket foundry-data)
Browser ─HTTPS PUT (presigned, CORS)─▶ Storage public URL                    public :8333
```

## Design decisions

### Why seven services, and why Foundry and the agent share one

- Upstream's `pod` gives `foundry`, `ontology-agent` and `storage` one network namespace. The agent listens on loopback only (its help text: "The address to listen on; loopback unless given"; default `127.0.0.1:50051`) and reads the snapshot files foundry writes to `/work` (`foundry.{ontology,graph}.agent.work_dir`). A Railway volume belongs to one service, so foundry and the agent run in **one container** with one volume, exactly as in the pod.
- The agent binary needs GLIBC 2.38 (Debian 13); the foundry image is Debian 12 (glibc 2.36), but its binary is static Go (`CGO_ENABLED=0`, `file`: statically linked). So `services/foundry` starts `FROM` the agent image and copies `/usr/local/bin/foundry` and `/etc/foundry/foundry.yaml` from the foundry image (multi-stage, both by digest). It adds curl (Debian repo, unversioned) for the start wait.
- `railway-foundry.sh` (bash) prepares `/work` as root, then runs both as uid 65532 via `setpriv` (as upstream: same user, owner-only files), agent with upstream's exact flags. If either exits, the other is stopped and the container exits (restart policy ALWAYS); SIGTERM goes to both, which drain (agent 100 s, foundry 30 s; draining window 120 s).
- Storage stays its own service: browsers must reach it anyway (below), and it has its own volume.

### Storage: SeaweedFS, not a Railway Bucket

- `backend/local/storage.go` forces path-style (`UsePathStyle = true`) on the one endpoint used for Foundry's own S3 calls **and** the browser's presigned uploads, and `CreateBucket` runs on every start. Railway Buckets need virtual-hosted URLs and a fixed bucket, so they cannot work without changing Foundry. SeaweedFS 4.47 with a volume, as upstream.
- "Browsers PUT documents to URLs presigned for Endpoint, so it must be the same address from the install and from the browser." The browser cannot reach `*.railway.internal`, so the endpoint is Storage's **public** domain, used by Foundry too. Consequence: Foundry's S3 traffic leaves and re-enters Railway (egress). Alternatives considered and rejected: rewriting presigned URLs in response bodies (needs a custom Caddy build with a third-party plugin; fragile), or a same-origin path on the Gateway (Foundry's own S3 calls would then hit the password).
- The S3 API checks a SigV4 signature on every request (one identity, `foundry`, secret `FOUNDRY_S3_SECRET`); master, volume and filer stay on loopback like upstream. CORS: `-s3.allowedOrigins` = the Gateway's origin (upstream: `http://localhost:3000`); the upload is a credential-less XHR (`documents-api.ts`). `-s3.externalUrl` = the public URL (SeaweedFS tries it first when checking signatures behind a proxy; it also tries Host and X-Forwarded-* candidates).
- Volume files of 256 MB instead of upstream's 1 GB: `-volume.max=0` sizes the slot count from free disk / volume size, and growth asks for 7 volumes at once (`VolumeGrowStrategy.Copy1Count`); with 1 GB on a 5 GB Hobby volume only ~4 slots exist (growth is partial, not fatal, but tight).
- Runs as the image's `seaweed` user via `su-exec` after giving it `/data` (as the image's own entrypoint does); upstream runs it as root.

### Making the loopback-only site work behind a domain, with a password

- `src/server/config.ts`: a local build accepts only a loopback `FOUNDRY_ORIGIN`; `src/server/local.ts` refuses any request whose `Host` is not that origin's host; `papi-handler.ts`/`csrf.ts` refuse unsafe methods unless `Origin` equals that origin, plus an HMAC double-submit CSRF token (cookie `SameSite=Lax`). So `FOUNDRY_ORIGIN=http://localhost:3000` and the Gateway sets `Host: localhost:3000`, and rewrites `Origin` to `http://localhost:3000` only for requests whose Origin is `https://{host}`. Cross-site requests (Origin present but different) are refused with 403 before basic auth, because browsers attach cached basic-auth credentials to them (pattern from our 86-redis gateway; the Caddy header matcher expands `{host}`, checked in `matchers.go` v2.11.9). The site's CSRF token remains in force.
- Upstream says "anyone who can reach it controls it". The Gateway's basic auth (`BASIC_AUTH_PASSWORD` = `secret(24)`, bcrypt-hashed at start; under 12 characters it refuses to start) is the only door to the site. The `Authorization` header is stripped before the site. `Location: http://localhost:3000…` responses are rewritten to `https://{host}` (none expected: the app redirects relatively).
- No server actions exist in the site, and the hosted-only auth routes (WorkOS) are unused in local mode.

### Agents (MCP and HTTP Ask)

- Foundry serves `/mcp` and `/v1/ontologies/{id}/ask` on :8081 behind the owner token, a host allow-list (localhost names plus the host of `local.site_origin`) and Go's cross-origin protection (`local/integration.go`). With `HELIX_LOCAL__SITE_ORIGIN = https://{gateway domain}` and the Gateway forwarding those two paths with Host preserved, agents can use `https://{domain}/mcp` with `Authorization: Bearer {FOUNDRY_LOCAL_TOKEN}`. They bypass basic auth because a client sends only one Authorization header; `FOUNDRY_AGENT_ENDPOINTS=off` puts them behind the password. The site itself never calls those two paths (allowlist uses `/v1/workspaces/...`).
- The in-app "Set up with your agent" prompt is compiled for the Docker install (`localhost:8081`, `docker compose` steps) and is left unchanged; README explains the Railway way.

### The sample (Acme Corp)

- "Use the sample" (`src/web/areas/ontology/sample.ts`) connects a PostgreSQL connector to `host: NEXT_PUBLIC_SAMPLE_DB_HOST`, `acme` / `acme_reader` / `acme`, TLS off, uploads nine documents from `/samples/acme/` to presigned URLs, creates the ontology from the pre-drafted `backend/sample/acme.json` (no AI needed for the draft) and loads it; loading documents and the question need an AI provider.
- The host is compiled into the browser bundle as `acme-db` (compose's service name), which does not resolve on Railway. The image layer was downloaded and grepped: `host:"acme-db"` appears once, in one chunk (`.next/static/chunks/20l0-xwoj-2mv.js`); no precompressed copies exist. `services/site` asserts that at build (exactly one file, one occurrence), keeps a pristine copy, and at every start restores it and writes `FOUNDRY_SAMPLE_DB_HOST` (= `${{Acme DB.RAILWAY_PRIVATE_DOMAIN}}`) in; an empty or invalid value keeps `acme-db` with a warning (lesson 29). Tested on the real chunk: correct host, idempotent, restores on fallback.
- Acme DB: Railway Postgres 18 base (requires its volume) + upstream's `acme.sql` from the pinned commit URL, SHA-256 checked. `load-acme.sh` (initdb, first boot) loads it into `acme` (40 accounts, 121 contacts, 45 subscriptions, 363 invoices, 327 support tickets, 225 usage rows) and narrows `acme_reader`: read-only transactions, `statement_timeout` 60 s, no CONNECT on `postgres`, CONNECT on `acme` only, no CREATE. The password `acme` is fixed by the site bundle and public upstream; the data is made up and the service has no domain or TCP proxy. Tested on local PostgreSQL 15.

### Secrets

- Upstream writes four secrets into a `secrets` volume (`foundry init-secrets`). Here they are Railway variables generated at deploy: `FOUNDRY_LOCAL_TOKEN` (64 hex, on Foundry, referenced by Site), `FOUNDRY_S3_SECRET` (64 hex, on Storage, referenced by Foundry), `MYSQL_ROOT_PASSWORD` (Railway base, letters only, safe unescaped in the DSN) and `FOUNDRY_CONNECTOR_KEY` (64 hex, on Foundry). The start script maps them to the `HELIX_*` overrides foundry reads.
- Foundry validates the connector key with **strict** base64 of 32 bytes (`config.validateAESKey`: `StdEncoding.Strict()`), which `secret()` cannot produce directly (the 43rd character must be one of 16). The script converts 64 hex characters to base64, passes an existing strict key through unchanged (so a local install's key can be reused), and hashes any other value of 32+ characters with SHA-256 (warning). Tested: NUL/`%`/newline/backslash bytes, upper-case hex, strictness of every output.

### Other choices

- **MySQL 8.0.46** (upstream's pin; Railway base supports 8 and 9) with the base's start flags, `--innodb-buffer-pool-size=256M` (base: 1G; Foundry's store is metadata) and upstream's `utf8mb4_unicode_ci`. Root user and the base's `railway` database; Foundry migrates at every start (goose), retries the connection ~5 min, and the start script waits for the port first.
- **HelixDB**: `HELIX_DATA_DIR=/var/lib/helix` on a volume, `HELIX_HTTP_ADDR=[::]:8080` (parsed as a `SocketAddr`; Rust does not set V6ONLY, so dual-stack), `/readyz` probe, telemetry off, `RAILWAY_RUN_UID=0` (distroless image runs as 65532, the Railway volume is root-owned).
- **Health listener** moved from `127.0.0.1:8083` to `:8083` (`HELIX_LOCAL__LISTEN__HEALTH`) so Railway can probe `/readyz` (ready after migrations, bucket creation and all workers started). REST stays `:8081` (Go, dual-stack).
- **Work cache cap** `FOUNDRY_WORK_MAX_GB=2` per draft and per load (upstream 6 GiB each, above the 5 GB Hobby volume).
- **Threads**: `TOKIO_WORKER_THREADS`/`RAYON_NUM_THREADS` for the agent from the cgroup CPU quota (2-8), lesson 15. Go 1.26 sizes GOMAXPROCS from the cgroup itself.
- **Site** binds `HOSTNAME=::` (Next standalone `server.js` reads it directly); healthcheck `/ask` (`/` answers 307 to `/ask`).
- **AI**: none required. With no provider named, foundry detects `ANTHROPIC_API_KEY`, then `OPENAI_API_KEY`, then local Ollama/LM Studio (absent here), else none; owners choose in Settings › AI models (keys sealed with the connector key). `allow_private_hosts` stays on (upstream) so an Ollama service in the same project works.
- **Left out:** Ollama (upstream profile; CPU inference on Railway is impractical, lesson 15) and a backup job (Railway volume backups; upstream's backup is "all five volumes, stack stopped").

## Services

Create in this order. Values are entered exactly as shown (Railway resolves `${{...}}`).

### MySQL

- **Source:** image `mysql:8.0.46@sha256:7dcddc01f13bab2f15cde676d44d01f61fc9f99fe7785e86196dfc07d358ae2b`
- **Start command:** `docker-entrypoint.sh mysqld --innodb-use-native-aio=0 --disable-log-bin --performance_schema=0 --innodb-buffer-pool-size=256M --character-set-server=utf8mb4 --collation-server=utf8mb4_unicode_ci`
- **Healthcheck:** none (TCP) · **Public domain:** none · **Volume:** `/var/lib/mysql` · **Restart:** ON_FAILURE (10) · **Replicas:** 1
- Railway MySQL base (`_railway-base/mysql.json`) with upstream's 8.0.46 pin, smaller buffer pool and utf8mb4_unicode_ci.

| Variable | Value | Description |
|---|---|---|
| `MYSQLHOST` | `${{RAILWAY_PRIVATE_DOMAIN}}` | Railway Private Domain Name. |
| `MYSQLPORT` | `3306` | MySQL port. |
| `MYSQLUSER` | `root` | MySQL user, used for the Data panel. |
| `MYSQL_URL` | `mysql://${{ MYSQLUSER }}:${{ MYSQL_ROOT_PASSWORD }}@${{ RAILWAY_PRIVATE_DOMAIN }}:3306/${{ MYSQL_DATABASE }}` | URL to connect to MySQL. |
| `MYSQLDATABASE` | `${{ MYSQL_DATABASE }}` | Default database, used for Data panel. |
| `MYSQLPASSWORD` | `${{ MYSQL_ROOT_PASSWORD }}` | Root password, used for Data panel. |
| `MYSQL_DATABASE` | `railway` | Database to be created on image startup (Foundry's tables). |
| `MYSQL_ROOT_PASSWORD` | `${{ secret(32, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ") }}` | Root password for MySQL DB, generated at deploy (letters only: it sits in Foundry's DSN unescaped). |
| `RAILWAY_DEPLOYMENT_DRAINING_SECONDS` | `30` | Time MySQL gets to shut down cleanly on redeploy. |

### HelixDB

- **Source:** image `ghcr.io/helixdb/helixdb:v0.0.14@sha256:1470a3bce07866367f1d2a5b250ec9c3244d62356ac27d537023ef5492a8f62a`
- **Healthcheck:** `/readyz` (timeout 300 s) · **Public domain:** none · **Volume:** `/var/lib/helix` · **Restart:** ON_FAILURE (10) · **Replicas:** 1
- Never add a domain or TCP proxy: HelixDB checks no key.

| Variable | Value | Description |
|---|---|---|
| `PORT` | `8080` | Port Railway health-checks (HelixDB's HTTP API). |
| `HELIX_HTTP_ADDR` | `[::]:8080` | HelixDB's HTTP listener (IPv4 and IPv6 on the private network). It checks no key: never add a public domain or TCP proxy. |
| `HELIX_DATA_DIR` | `/var/lib/helix` | Where HelixDB keeps its database (the volume). |
| `HELIX_TELEMETRY_LEVEL` | `off` | No telemetry, as upstream's compose file runs it. |
| `RAILWAY_RUN_UID` | `0` | Run as root so HelixDB can write the root-owned Railway volume (the image's user is 65532 and has no shell to change it). |
| `RAILWAY_DEPLOYMENT_DRAINING_SECONDS` | `30` | Time HelixDB gets to drain and close its storage on redeploy. |

### Storage

- **Source:** repo `baranberkay96/helix-foundry-railway`, root `/services/storage`
- **Healthcheck:** `/healthz` (timeout 300 s) · **Public domain:** yes, target port `8333` · **Volume:** `/data` · **Restart:** ALWAYS · **Replicas:** 1
- Public domain = the S3 API (browser uploads and Foundry). Every request is signature-checked.

| Variable | Value | Description |
|---|---|---|
| `FOUNDRY_STORAGE_IMAGE` | `chrislusf/seaweedfs:4.47@sha256:ce9e796f1fe6f06968f4c04bdaf8f678dad9c8acdfef3d244133d71bfa6bf882` | SeaweedFS image this service's Docker build starts FROM (the version upstream's compose file pins). |
| `PORT` | `8333` | Port of the S3 API (public domain target and healthcheck). |
| `FOUNDRY_S3_SECRET` | `${{secret(64, "0123456789abcdef")}}` | Secret of the store's one S3 identity, foundry, generated at deploy. Foundry references it. |
| `STORAGE_ALLOWED_ORIGINS` | `https://${{Gateway.RAILWAY_PUBLIC_DOMAIN}}` | Comma-separated origins whose pages may upload (CORS). Add your custom domain here if you give the Gateway one. |
| `STORAGE_VOLUME_SIZE_MB` | `256` | Size of each SeaweedFS volume file. Small files fit a 5 GB Railway volume; raise it on large volumes. |
| `RAILWAY_DEPLOYMENT_DRAINING_SECONDS` | `60` | Time SeaweedFS gets to stop cleanly on redeploy (it takes about 20 s). |

### Acme DB

- **Source:** repo `baranberkay96/helix-foundry-railway`, root `/services/acme-db`
- **Healthcheck:** none (TCP) · **Public domain:** none · **Volume:** `/var/lib/postgresql/data` · **Restart:** ON_FAILURE (10) · **Replicas:** 1
- Optional demo: delete it (and the sample connector in the app) if you do not want the sample.

| Variable | Value | Description |
|---|---|---|
| `ACME_DB_IMAGE` | `ghcr.io/railwayapp-templates/postgres-ssl:18@sha256:4fc833b43d2aaf6ecc9b18615f5533602b723a32d0e2efe2dae8ca0f7217c863` | Railway Postgres image this service's Docker build starts FROM. |
| `PGDATA` | `/var/lib/postgresql/data/pgdata` | Location where the database will be initialized. |
| `PGHOST` | `${{RAILWAY_PRIVATE_DOMAIN}}` | Railway Private Domain Name (the Site writes it into Use the sample). |
| `PGPORT` | `5432` | Port to connect to Postgres (the sample expects 5432). |
| `PGUSER` | `${{ POSTGRES_USER }}` | Required variable for Data panel. |
| `PGDATABASE` | `${{POSTGRES_DB}}` | Required variable for the data panel. |
| `PGPASSWORD` | `${{POSTGRES_PASSWORD}}` | Required variable for Data panel. |
| `POSTGRES_DB` | `acme` | Database holding Acme Corp's sample tables. Keep acme: Foundry's Use the sample connects to it by that name. |
| `DATABASE_URL` | `postgresql://${{PGUSER}}:${{POSTGRES_PASSWORD}}@${{RAILWAY_PRIVATE_DOMAIN}}:5432/${{PGDATABASE}}` | Superuser connection string (private network). |
| `POSTGRES_USER` | `postgres` | Superuser created on first boot. |
| `POSTGRES_PASSWORD` | `${{ secret(32, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ") }}` | Superuser password, generated at deploy. Foundry uses the read-only login acme_reader instead (password acme, built into the web app; made-up data, private network only). |
| `SSL_CERT_DAYS` | `820` | SSL certificate expiry in days. |
| `RAILWAY_DEPLOYMENT_DRAINING_SECONDS` | `30` | Allow Postgres to cleanly shut down. |

### Foundry

- **Source:** repo `baranberkay96/helix-foundry-railway`, root `/services/foundry`
- **Healthcheck:** `/readyz` (timeout 1200 s) · **Public domain:** none · **Volume:** `/work` · **Restart:** ALWAYS · **Replicas:** 1
- Start: `railway-foundry.sh` (waits for MySQL and the store, then runs ontology-agent and foundry as uid 65532). Never add a public domain: the Gateway forwards only /mcp and /v1/ontologies/.

| Variable | Value | Description |
|---|---|---|
| `FOUNDRY_IMAGE` | `ghcr.io/helixdb/foundry:0.1.2@sha256:5adf4ca93c2b53661275ff3b9a4c5054d8ee42acfa569c4dcbfd2c8b6b27ba62` | Foundry backend image the foundry binary and its config are copied from at build (HelixDB's release, unchanged). |
| `FOUNDRY_AGENT_IMAGE` | `ghcr.io/helixdb/ontology-agent:0.1.1@sha256:d5a543bee8d9f403fa898ad5773b9a3d95b394f31396b36ec2b13448af07faa8` | Ontology agent image this service's Docker build starts FROM (HelixDB's release, unchanged). |
| `PORT` | `8083` | Port of Foundry's health listener, which Railway health-checks (/readyz). The API listens on 8081 (private). |
| `FOUNDRY_LOCAL_TOKEN` | `${{secret(64, "0123456789abcdef")}}` | Owner token, generated at deploy: the web app sends it to Foundry, and MCP clients send it as Authorization: Bearer. Whoever has it controls this install; at least 32 characters. |
| `FOUNDRY_CONNECTOR_KEY` | `${{secret(64, "0123456789abcdef")}}` | Key that seals every database password and API key given to Foundry, generated at deploy. Never change it: credentials sealed with it become unreadable. Back it up with your data. |
| `FOUNDRY_S3_SECRET` | `${{Storage.FOUNDRY_S3_SECRET}}` | Secret of the store's foundry identity (set on Storage). |
| `HELIX_DB_DSN` | `root:${{MySQL.MYSQL_ROOT_PASSWORD}}@tcp(${{MySQL.MYSQLHOST}}:${{MySQL.MYSQLPORT}})/${{MySQL.MYSQL_DATABASE}}?parseTime=true&multiStatements=true` | Foundry's MySQL database (Go DSN). Foundry migrates it at every start. |
| `HELIX_LOCAL__SITE_ORIGIN` | `https://${{Gateway.RAILWAY_PUBLIC_DOMAIN}}` | Public URL of Foundry (the Gateway): links given to agents start here, and MCP and HTTP Ask answer only for this host. Change it when you add a custom domain. |
| `HELIX_LOCAL__HELIX_URL` | `http://${{HelixDB.RAILWAY_PRIVATE_DOMAIN}}:8080` | HelixDB on the private network: every ontology's loads share it. |
| `HELIX_LOCAL__S3__ENDPOINT` | `https://${{Storage.RAILWAY_PUBLIC_DOMAIN}}` | The S3 store's public URL. Browsers upload documents to URLs Foundry signs for it, so Foundry uses the same public address. |
| `ANTHROPIC_API_KEY` | *(empty)* | Optional. A Claude API key: Foundry then drafts, reads documents and answers with Claude. Leave empty to choose a provider and enter its key in Settings > AI models instead (stored sealed). |
| `OPENAI_API_KEY` | *(empty)* | Optional. An OpenAI API key, used when ANTHROPIC_API_KEY is empty. Leave empty to choose in Settings > AI models. |
| `FOUNDRY_WORK_MAX_GB` | `2` | GiB of snapshots one draft or one load may unpack into the /work volume (upstream: 6). Keep two of them below the volume size. |
| `FOUNDRY_STARTUP_WAIT_SECONDS` | `600` | Seconds the start waits for MySQL and the store before starting Foundry anyway (keep it below the healthcheck timeout). |
| `RAILWAY_DEPLOYMENT_DRAINING_SECONDS` | `120` | Seconds between SIGTERM and SIGKILL on redeploy: a load or question in flight finishes or is handed back (the agent drains for 100 s). |

### Site

- **Source:** repo `baranberkay96/helix-foundry-railway`, root `/services/site`
- **Healthcheck:** `/ask` (timeout 300 s) · **Public domain:** none · **Volume:** none · **Restart:** ALWAYS · **Replicas:** 1
- Start: `railway-site.sh` (writes the sample host into the browser bundle, then `node server.js`).

| Variable | Value | Description |
|---|---|---|
| `FOUNDRY_SITE_IMAGE` | `ghcr.io/helixdb/foundry-site:0.1.3@sha256:ac69e52df43e99b5c49879399f1f20f475a8fcdf7f43e66f27ca6b6b11da74ae` | Foundry web app image this service's Docker build starts FROM (HelixDB's release image, unchanged). Upgrade it together with FOUNDRY_IMAGE and FOUNDRY_AGENT_IMAGE on Foundry. |
| `PORT` | `3000` | Port the web app listens on (healthcheck). |
| `HOSTNAME` | `::` | Bind address of the Next.js server (:: = IPv4 and IPv6 on the private network). |
| `HELIX_WFE_ORIGIN` | `http://${{Foundry.RAILWAY_PRIVATE_DOMAIN}}:8081` | Foundry API on the private network; the web app's /papi forwards to it with the owner token. |
| `FOUNDRY_ORIGIN` | `http://localhost:3000` | The origin the web app believes it is served at. Keep it: the local build accepts only loopback origins, and the Gateway presents every request as localhost:3000. |
| `FOUNDRY_LOCAL_TOKEN` | `${{Foundry.FOUNDRY_LOCAL_TOKEN}}` | Owner token the web app sends to Foundry (set on Foundry). |
| `FOUNDRY_SAMPLE_DB_HOST` | `${{Acme DB.RAILWAY_PRIVATE_DOMAIN}}` | Host that Use the sample connects to (the Acme DB service), written into the web app at start in place of upstream's acme-db. |
| `NEXT_TELEMETRY_DISABLED` | `1` | No Next.js telemetry. |
| `RAILWAY_DEPLOYMENT_DRAINING_SECONDS` | `15` | Seconds between SIGTERM and SIGKILL on redeploy. |

### Gateway

- **Source:** repo `baranberkay96/helix-foundry-railway`, root `/services/gateway`
- **Healthcheck:** `/_gateway/health` (timeout 300 s) · **Public domain:** yes, target port `8080` · **Volume:** none · **Restart:** ALWAYS · **Replicas:** 1
- Start: `railway-gateway.sh` (hashes the password, then `caddy run`). The URL users open.

| Variable | Value | Description |
|---|---|---|
| `FOUNDRY_GATEWAY_IMAGE` | `caddy:2.11.9-alpine@sha256:0bbb055bda6793c999bde78b1b5ce3e89f829fb031af2cf50056ea1246559fee` | Caddy image this service's Docker build starts FROM (Railway passes it as a build argument). |
| `PORT` | `8080` | Port the gateway listens on (public domain target and healthcheck). |
| `BASIC_AUTH_USERNAME` | `admin` | User name for the browser's sign-in prompt. Letters, digits and . _ @ - (anything else falls back to admin). |
| `BASIC_AUTH_PASSWORD` | `${{secret(24, "abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789")}}` | Password for the browser's sign-in prompt, generated at deploy. Foundry has no sign-in of its own, so this protects the whole install; at least 12 characters or the gateway refuses to start. |
| `FOUNDRY_AGENT_ENDPOINTS` | `on` | on: /mcp and /v1/ontologies/... go straight to Foundry, which requires FOUNDRY_LOCAL_TOKEN as a bearer token (for Claude Code, Cursor and other MCP clients). off: they stay behind the password like the rest. |
| `FOUNDRY_SITE_UPSTREAM` | `${{Site.RAILWAY_PRIVATE_DOMAIN}}:3000` | Foundry web app on the private network. |
| `FOUNDRY_API_UPSTREAM` | `${{Foundry.RAILWAY_PRIVATE_DOMAIN}}:8081` | Foundry API (MCP and HTTP Ask) on the private network. |
| `RAILWAY_DEPLOYMENT_DRAINING_SECONDS` | `15` | Seconds between SIGTERM and SIGKILL on redeploy. |

## Improvements over market templates

No market template exists. Compared with upstream's `local/compose.yaml`, run as-is on Railway:

- Reachable on a public HTTPS domain at all: the site's loopback-only Host/Origin checks are satisfied by the Gateway, which adds the password upstream lacks and refuses cross-site requests.
- The pod's shared namespace replaced by one container for foundry + agent (shared `/work` volume) and private-network services for the rest; browser uploads work through Storage's public, signature-checked S3 domain with CORS for the Gateway.
- "Use the sample" works: the compiled `acme-db` host is rewritten to the Railway private host at start; the sample login is narrowed to read-only.
- MCP and HTTP Ask usable by remote agents with the owner token (upstream: loopback only, opt-in compose file).
- Secrets generated per deploy as Railway variables (upstream: a Docker volume); strict connector-key format handled.
- Volume-size-aware settings (SeaweedFS volume files, Foundry work cache cap), CPU-quota thread caps, memory warning in the start log, dual-stack listeners where the binaries allow it, every image pinned by digest.

## Scaling

- Every service stays at **one replica**: Foundry's workers lease jobs from MySQL but the agent's cache lives on its volume, HelixDB and SeaweedFS are single-node with volumes, MySQL/Postgres are single databases. Site and Gateway are stateless but cheap; replicas bring nothing for a one-owner install.
- Scale vertically: Foundry (drafts, loads, questions) and HelixDB (graph size) need RAM first. Agent concurrency is upstream's (2 turns, 8 reads, 4 asks, 4 titles, 1 probe).
- Bigger data: raise the Railway volume (Pro), then `FOUNDRY_WORK_MAX_GB` and `STORAGE_VOLUME_SIZE_MB`.

## Resource estimate

Prices: RAM $10/GB-month, vCPU $20/vCPU-month, volume $0.15/GB-month, egress $0.05/GB. **Not measured** (no container run this round); derived from the processes each image runs. Measure on the first deploy (Railway metrics) before stating limits in the listing.

| Service | Idle RAM / vCPU | Typical RAM / vCPU | Notes |
|---|---|---|---|
| Gateway | 0.03 GB / 0.001 | 0.04 GB / 0.01 | Caddy |
| Site | 0.15 GB / 0.002 | 0.25 GB / 0.02 | Next.js 16 standalone |
| Foundry | 0.30 GB / 0.01 | 0.9 GB / 0.15 (peaks 1.5–2 GB during loads) | Go monolith + Rust agent |
| HelixDB | 0.15 GB / 0.005 | 0.5 GB / 0.05 | SlateDB on disk, in-memory caches |
| Storage | 0.12 GB / 0.005 | 0.25 GB / 0.03 | `weed server` all-in-one |
| MySQL | 0.25 GB / 0.005 | 0.40 GB / 0.03 | 256 MB buffer pool, perf schema off |
| Acme DB | 0.04 GB / 0.001 | 0.06 GB / 0.005 | 1 MB of sample data |

- **Idle ≈ $12/month** (1.04 GB × $10 + 0.03 vCPU × $20 + ~1 GB volumes × $0.15).
- **Typical ≈ $30/month** (2.4 GB × $10 + 0.3 vCPU × $20 + ~4 GB volumes + a few GB of egress: Foundry's S3 traffic goes through Storage's public domain, so each sync's snapshot counts roughly twice).
- Model calls are billed by the AI provider; Foundry's spend caps apply ($20 per load job, $100/month loads, $30/month questions; `foundry.yaml`).
- **Minimum plan: Hobby.** Free (0.5 GB/service) cannot hold Foundry during a load; Trial (1 GB/service) boots and runs the sample but large drafts/loads may be OOM-killed. The Foundry start log warns when its limit is under 1.5 GB (lesson 31). 7 services, 5 volumes (each ≤ 5 GB on Hobby).

## Verification checklist

1. **Builds:** Gateway runs `caddy validate` twice (agents on/off); Site build prints nothing and passes the one-chunk assertion; Foundry passes its tool/binary checks; Storage `sh -n`; Acme DB passes `sha256sum -c` and `bash -n`.
2. **Health:** Gateway `/_gateway/health`, Site `/ask`, Foundry `/readyz` (8083), HelixDB `/readyz`, Storage `/healthz` all 200.
3. **Logs:** Storage `railway-storage: S3 on :8333 for origins https://{gateway-domain}, volumes of 256 MB in /data, as seaweed`; Acme DB `load-acme: done: 40 accounts, 363 invoices, 327 support tickets`; Foundry `store answers at https://{storage-domain}`, then foundry's `running db migrations`, `created the owner's first workspace`, `foundry ready`; Site `Use the sample connects to acme-db.railway.internal:5432`.
4. **Password:** `curl -i https://{gateway-domain}/` → 401 with `WWW-Authenticate: Basic`; with `-u admin:{BASIC_AUTH_PASSWORD}` → 307 to `/ask`; browser shows My workspace.
5. **Origin handling:** in the app, rename the workspace or create a document set (a POST through /papi) → succeeds (no `ORIGIN_REJECTED`/`HOST_REJECTED`). `curl -u admin:{pw} -X POST -H 'Origin: https://evil.example' https://{gateway-domain}/papi/csrf` → 403 "Cross-origin request refused".
6. **AI:** Settings › AI models → add a Claude key → test passes.
7. **Sample:** Use the sample → connector to `acme-db.railway.internal` tests OK and syncs six tables; nine documents upload (browser PUT to the Storage domain: check the network tab for 200 and a CORS preflight 200); ontology created and loaded; the first question answers with sources. Explorer shows accounts linked to invoices and contracts.
8. **Upload signature behind the proxy:** a document's `:complete` succeeds (Foundry re-reads the object through the public URL and checks its SHA-256).
9. **MCP:** `curl -i https://{gateway-domain}/mcp` → 401 from Foundry (no basic-auth challenge); with `-H "Authorization: Bearer {FOUNDRY_LOCAL_TOKEN}" -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' --data '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'` → tool list incl. `helix_foundry_ask`. With `FOUNDRY_AGENT_ENDPOINTS=off` → basic-auth 401.
10. **Private services:** HelixDB, MySQL, Acme DB, Site and Foundry have no domain.
11. **Redeploy everything:** workspace, connector (credential still opens: connector key unchanged), documents, ontology and its load persist; Acme DB does not reload; Site re-patches the chunk from pristine.
12. **Memory:** record each service's RAM idle and during the sample load; check Foundry stays under 1 GB for the sample (Trial claim).

## Open questions

- **Not deployed; no Docker build or container run** (instruction). Verified statically: registry manifests/configs/layers, upstream sources at the pin, HelixDB/SeaweedFS/Caddy sources at the pinned versions, `bash -n`/`sh -n`, script function tests (connector key, int parsing, DSN parsing, storage flags and CORS origins, gateway variable handling, site chunk patch on the real chunk), `load-acme.sh` against local PostgreSQL 15, JSON/reference checks, `to_serialized.py`.
- **Presigned uploads through Railway's edge:** SeaweedFS must accept signatures for the public host; `-s3.externalUrl` plus its Host/X-Forwarded candidates should cover it, unverified until deploy. CORS preflight through the edge likewise.
- **Caddy specifics** (`expression` constant from env substitution, `request_header` with matcher, regex `header_down`) are validated at build by `caddy validate`, not run here.
- **`wait -n` supervision** needs bash ≥ 5.1 (Debian 13 has 5.2); the loop logic was reviewed, not executed (macOS bash 3.2).
- **HelixDB on `[::]:8080`** and as root (`RAILWAY_RUN_UID=0`): unverified at runtime; fallback `HELIX_HTTP_ADDR=0.0.0.0:8080` (Go and Node callers fall back to IPv4).
- **MySQL 8.0** is past Oracle's end of support (April 2026); upstream still pins 8.0.46. Moving to 8.4 LTS needs a Foundry test first.
- **Egress:** Foundry's own S3 traffic uses Storage's public URL; large syncs cost egress. Unavoidable without changing Foundry's single-endpoint S3 config.
- **AI provider required for value:** without a key the app runs, connects and syncs, but drafting, document reading, loading the sample's documents and questions wait for a provider. First-run time with Claude unmeasured (upstream: "about a minute" for the sample).
- **Ontology agent source** is not public (Apache-2.0 image). Its flags were read from the binary's help strings.
- **Upstream pace:** repo created 2026-10, images 0.1.x, pushes daily. Upgrade the three Foundry images together to a set named by a later `local/compose.yaml`, and re-check that `host:"acme-db"` is still in one chunk (the Site build fails loudly if not).
