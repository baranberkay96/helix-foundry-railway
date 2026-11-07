# Deploy and Host Helix Foundry with Railway

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/helix-foundry-0-1-ontology-and-kn?referralCode=20H68q)

Helix Foundry is HelixDB's open-source (Apache-2.0) app for turning company data into one graph: connect databases, tools and documents, let an agent draft an ontology over them, load it into HelixDB, then explore it and ask questions with cited answers. This community template runs Foundry's 0.1 release images with a password-protected URL and the Acme Corp sample.

## About Hosting Helix Foundry

Upstream ships Foundry as software for your own computer: no sign-in, one owner, seven containers sharing a network namespace, and a site that answers only `localhost:3000`. This template rebuilds that stack for Railway's private network. A gateway asks for a generated password before anything reaches the app and presents each request to it as localhost. Foundry and its ontology agent share one container and volume, as they share a pod upstream. HelixDB, MySQL and an S3-compatible store (SeaweedFS) run as their own services with volumes. Secrets are generated at deploy. The Acme Corp sample database is wired in, so "Use the sample" works once you add an AI key.

## Common Use Cases

- Build an ontology over PostgreSQL, MySQL, Stripe, GitHub, Linear, Notion, Slack or Google Workspace data, plus PDFs and notes, and explore it as one graph
- Ask questions across tables and documents and get answers with charts, the queries run and a source for every claim
- Give Claude Code, Cursor or your own agents an MCP server over your company graph
- Trace every value back to the row or document quote it came from, and review values documents disagree on
- Try ontology-driven analytics on a made-up company before connecting real data

## Dependencies for Helix Foundry Hosting

- Helix Foundry images by HelixDB: `foundry-site` 0.1.3, `foundry` 0.1.2, `ontology-agent` 0.1.1
- HelixDB v0.0.14 (graph database), MySQL 8.0 (Foundry's store), SeaweedFS 4.47 (S3-compatible store)
- PostgreSQL 18 with the Acme Corp sample data (optional demo source)
- An AI provider: a Claude or OpenAI key, or Azure OpenAI, Amazon Bedrock, Ollama or any OpenAI-compatible server, entered in the app

### Deployment Dependencies

- Source and local guide: https://github.com/HelixDB/helix-foundry
- Foundry docs: https://docs.helix-db.com/foundry
- HelixDB: https://github.com/HelixDB/helix-db
- SeaweedFS: https://github.com/seaweedfs/seaweedfs
- Claude API keys: https://console.anthropic.com

### Implementation Details

| Service | Role | Public |
|---|---|---|
| Gateway | Caddy: password prompt, then the app; MCP and HTTP Ask with a bearer token | **yes** |
| Site | Foundry's web app (Next.js) | no |
| Foundry | API, MCP, sync/draft/load/ask workers and the ontology agent; volume `/work` | no |
| HelixDB | Graph database every ontology loads into; volume | no |
| Storage | SeaweedFS S3 API for synced tables, snapshots and documents; volume | **yes** (S3, signed requests only) |
| MySQL | Foundry's database; volume | no |
| Acme DB | PostgreSQL with Acme Corp's made-up sample tables | no |

Storage has a public domain because your browser uploads documents straight to it, to URLs Foundry signs. Every S3 request needs Foundry's signature. HelixDB checks no key: never give it a domain or TCP proxy.

**First login**

1. Deploy. Nothing is required; optionally paste a Claude key into `ANTHROPIC_API_KEY` (or an OpenAI key into `OPENAI_API_KEY`) on Foundry.
2. Wait until all services are healthy. The first deploy builds five thin images on top of the published ones, which takes a few minutes.
3. Open the Gateway's URL. Sign in with `BASIC_AUTH_USERNAME` (default `admin`) and `BASIC_AUTH_PASSWORD`, both on Gateway → Variables.
4. Foundry opens in **My workspace**. Without a key, open **Settings › AI models** and pick a provider. Keys entered there are stored sealed, never in a variable.
5. Click **Use the sample**. It connects Acme Corp's database (accounts, contacts, subscriptions, invoices, tickets, usage), uploads its contracts and call notes, creates a ready-made ontology, loads it into HelixDB and asks a first question.

**Your own data**

Add a connector or upload documents, state a goal, and let the agent draft. A first draft can take 10 to 20 minutes on a hosted model. Review it, make it current and load it. Connectors may reach other services in this Railway project by their private names (`{service}.railway.internal`). Foundry seals every credential you give it with `FOUNDRY_CONNECTOR_KEY` on Foundry. Never change that key, and keep a copy: without it, the stored credentials cannot be read.

**Connect your agent (MCP)**

With `FOUNDRY_AGENT_ENDPOINTS=on` (the default), `https://{your-domain}/mcp` is Foundry's MCP server and `https://{your-domain}/v1/ontologies/{id}/ask` its HTTP Ask. Both skip the password prompt and require `Authorization: Bearer {token}`, where the token is `FOUNDRY_LOCAL_TOKEN` on Foundry. It acts as the owner of everything, so keep it in your client's environment. For example: `claude mcp add --transport http helix https://{your-domain}/mcp --header "Authorization: Bearer $FOUNDRY_LOCAL_TOKEN"`. The in-app **Set up with your agent** prompt describes the Docker install and does not apply here. Set the variable to `off` to keep these routes behind the password.

**Custom domain**

Add it to Gateway, then set `HELIX_LOCAL__SITE_ORIGIN` on Foundry to `https://{your-domain}`. Also add the domain to `STORAGE_ALLOWED_ORIGINS` on Storage, or uploads fail.

**Scaling and limits**

Keep every service at one replica: Foundry's workers, HelixDB and the store keep state in-process or on their volumes. Scale vertically. Foundry needs about 1 to 2 GB while drafting or loading, so Hobby or Pro is recommended. On Free (0.5 GB) or Trial (1 GB), large drafts and loads can be stopped for lack of memory. `FOUNDRY_WORK_MAX_GB` (default 2) caps the snapshots one draft or load unpacks into the 5 GB Hobby volume. Foundry's own spend caps on your keys apply: $20 per load job, $100 a month for loads, $30 a month for questions.

**Upgrades**

Each image is pinned by tag and digest in a service variable: `FOUNDRY_SITE_IMAGE` on Site, `FOUNDRY_IMAGE` and `FOUNDRY_AGENT_IMAGE` on Foundry, `HelixDB`'s image source, `FOUNDRY_STORAGE_IMAGE` on Storage. Upgrade the three Foundry images together to the set upstream's `local/compose.yaml` names, after reading its changes. Foundry migrates MySQL at start, and migrations only go forward, so back up the volumes first. The Site checks at build that the sample host it rewrites is still where it expects.

**Costs**

Estimated at Railway usage prices: about $12/month idle and $30/month with regular syncs and questions. Foundry reaches the store through its public URL, so synced data counts as egress. Model calls are billed by your AI provider.

### Why Deploy Helix Foundry on Railway?

Railway runs the whole Foundry stack, from the web app and agent to the graph database, store and sample, in one project with HTTPS, volumes, private networking and logs. You get a shareable, password-protected Foundry instead of one bound to localhost, plus an MCP endpoint for your agents. This is a community template, not affiliated with or endorsed by HelixDB. Helix Foundry and HelixDB are HelixDB's open-source projects under the Apache-2.0 licence.
