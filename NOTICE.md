# Notice

## Upstream software

This repository contains Railway configuration and small start scripts only. Helix Foundry and HelixDB are **HelixDB's open-source projects**; their software is pulled from HelixDB's published container images and is not stored here. This is a community template, not affiliated with or endorsed by HelixDB.

| Software | License | Used as |
|---|---|---|
| Helix Foundry (web app `foundry-site` 0.1.3, backend `foundry` 0.1.2) | Apache License 2.0. Upstream NOTICE: "Helix Foundry, Copyright 2026 HelixDB. This product includes software developed at HelixDB." | Images `ghcr.io/helixdb/foundry-site:0.1.3` and `ghcr.io/helixdb/foundry:0.1.2`, pinned by digest, both built from commit `c7de40515f56a491d1b46af0bb1efa890f106700` (image label). The Foundry service copies the `foundry` binary and `/etc/foundry/foundry.yaml` unchanged; the Site service rewrites one string at start (the sample database host, see below). |
| Helix Foundry ontology agent 0.1.1 | Apache License 2.0 (`/usr/share/doc/ontology-agent/LICENSE` in the image) | Image `ghcr.io/helixdb/ontology-agent:0.1.1`, pinned by digest, used unchanged as the Foundry service's base. Its source is not in a public repository we could find; upstream's README states the image is Apache-2.0. |
| HelixDB server v0.0.14 | Apache License 2.0 (github.com/HelixDB/helix-db) | Image `ghcr.io/helixdb/helixdb:v0.0.14`, pinned by digest, unchanged. |
| Acme Corp sample data (`local/acme/acme.sql`) | Apache License 2.0 (part of helix-foundry; made-up company data) | Downloaded at build time from helix-foundry commit `c900024caa1c65157604d7ee84b1f60d7fbfc00d`, verified by SHA-256 `bce83a6d2ea1bbd815fc72e7d2926b16bb1337e67437e95a3fdeb54c19a053d1`, loaded unmodified. Not stored in this repository. |
| SeaweedFS 4.47 | Apache License 2.0 | Image `chrislusf/seaweedfs:4.47`, pinned by digest (the one upstream's compose file pins); start command written for this template. |
| MySQL 8.0.46 | GPL-2.0 with the Universal FOSS Exception (Oracle) | Official image `mysql:8.0.46`, pinned by digest, unchanged, as a separate service. |
| PostgreSQL 18 | PostgreSQL License | `ghcr.io/railwayapp-templates/postgres-ssl:18` (Railway; MIT-licensed image repository) for Acme DB |
| Caddy 2.11.9 | Apache License 2.0 | Official image `caddy:2.11.9-alpine`, pinned by digest, with this template's Caddyfile |
| Lucide icons (`waypoints`, `shield-check`, `app-window`, `workflow`, `share-2`, `hard-drive`) | ISC | Referenced by URL from `cdn.jsdelivr.net/npm/lucide-static@1.59.0`; not copied |

The Apache License 2.0 text is at https://www.apache.org/licenses/LICENSE-2.0 and inside each HelixDB image.

### Changes to upstream behaviour (Apache-2.0 section 4)

- **Site:** the compiled browser chunk that holds the sample database host `acme-db` (`NEXT_PUBLIC_SAMPLE_DB_HOST`) gets that one string replaced at start by the Acme DB service's private host. Nothing else in the image changes.
- **Foundry:** run with environment overrides upstream documents (`HELIX_*` keys of `foundry.yaml`): the health listener on all interfaces, the site origin, HelixDB URL and S3 endpoint for Railway, a 2 GiB cap per draft/load cache. Secrets come from Railway variables instead of upstream's `init-secrets` volume.
- **Topology:** upstream's shared network namespace is replaced by Railway services on the private network; a Caddy gateway with HTTP basic auth fronts the site, which upstream ships for loopback only.

## External services (not legal advice)

- **AI providers** (Anthropic, OpenAI, Azure OpenAI, Amazon Bedrock or others you configure) receive your data during drafts, document reads and questions, under their own terms and pricing. None is configured by default.
- This summary is practical guidance, not legal advice.

## Verified against

| What | Upstream file | Ref | Checked |
|---|---|---|---|
| Services, images, ports, secrets, volumes | `compose.yaml`, `local/compose.yaml`, `local/compose.mcp.yaml`, `local/README.md`, `local/.env.example`, `README.md` | `c900024c` | 2026-11-07 |
| Image builds and revisions | `Dockerfile`, `backend/Dockerfile`, `.github/workflows/foundry-image.yml`, `site-image.yml`; ghcr manifests and configs (`org.opencontainers.image.revision`); compare `c7de4051...c900024c` (only compose/README/test changed) | 0.1.3 / 0.1.2 / 0.1.1 | 2026-11-07 |
| Foundry configuration, listeners, secrets, migrations | `backend/cmd/foundry/{foundry.yaml,config.go,run.go,secrets.go}`, `backend/config/config.go` (defaults, `validateAESKey`), `backend/local/{storage.go,integration.go,local.go}`, `backend/document/document.go` | `c900024c`; `foundry.yaml` identical in the image | 2026-11-07 |
| Site local mode (Host and Origin checks, CSRF, token) | `src/server/{local.ts,config.ts,papi-handler.ts,csrf.ts}`, `src/app/papi/[...path]/route.ts`, `next.config.ts`, `src/web/areas/ontology/sample.ts`, `src/web/areas/documents/documents-api.ts`; compiled image layer (one chunk holds `host:"acme-db"`) | `c900024c` / image 0.1.3 | 2026-11-07 |
| Ontology agent flags, listen address, glibc | Image layers (binary help strings: loopback by default; needs GLIBC 2.38; Debian 13 base) | 0.1.1 | 2026-11-07 |
| HelixDB env, probes, storage | HelixDB/helix-db `crates/server/src/config.rs`, `docker-image/README.md` | `main` (v0.0.14 era) | 2026-11-07 |
| SeaweedFS flags, S3 health, signature host behind a proxy | seaweedfs `weed/command/server.go`, `weed/s3api/s3api_server.go`, `weed/s3api/auth_signature_v4.go`, `weed/topology/volume_growth.go`, `docker/entrypoint.sh`, `docker/Dockerfile.go_build` | tag `4.47` | 2026-11-07 |
| Caddy header matcher placeholders, header replace | caddyserver/caddy `modules/caddyhttp/matchers.go`, `modules/caddyhttp/headers/` | `v2.11.9` | 2026-11-07 |
| Railway Postgres and MySQL bases | `templates/_railway-base/{postgres,mysql}.json`, railwayapp-templates/postgres-ssl `wrapper.sh` | — | 2026-11-07 |

## Our files

| File | Origin |
|---|---|
| `services/*/Dockerfile`, `services/*/railway-*.sh`, `services/gateway/Caddyfile`, `services/acme-db/load-acme.sh`, `template.json`, `TEMPLATE.md`, `README.md` | Written for this template. The Caddyfile pattern (basic auth, cross-site refusal) follows our own `86-redis` gateway; `load-acme.sh` follows our own `91-auto-ontology` sample loader. No upstream code or prose is copied. |

## Reference only (not copied)

- No Railway marketplace template for Helix Foundry existed when this was written.
- Upstream README and `local/README.md` were read for behaviour; no prose was copied.

## Trademarks

"Helix Foundry" and "HelixDB" are names of HelixDB. "Railway", "MySQL", "PostgreSQL", "SeaweedFS", "Caddy", "Claude", "Cursor" and other names belong to their respective owners. The template uses neutral icons and no HelixDB logo. It is a community template and is not affiliated with or endorsed by HelixDB or Railway.
