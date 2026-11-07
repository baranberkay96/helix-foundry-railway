# Gateway: basic-auth reverse proxy in front of Helix Foundry (see Caddyfile).
# The official Caddy image, pinned by tag and digest. FOUNDRY_GATEWAY_IMAGE is
# a service variable; Railway passes it to the build as an argument.
ARG FOUNDRY_GATEWAY_IMAGE=caddy:2.11.9-alpine@sha256:0bbb055bda6793c999bde78b1b5ce3e89f829fb031af2cf50056ea1246559fee
FROM ${FOUNDRY_GATEWAY_IMAGE}

# /etc/caddy and /usr/local/bin exist in the base image, so the copies keep
# their directories' permissions.
COPY Caddyfile /etc/caddy/Caddyfile
COPY --chmod=0755 railway-gateway.sh /usr/local/bin/railway-gateway.sh

# Fail the build rather than the deploy on a Caddyfile error, in both
# positions of the agent switch. The values are placeholders; the service
# variables supply the real ones at start.
RUN sh -n /usr/local/bin/railway-gateway.sh \
 && for agents in on off; do \
      PORT=8080 FOUNDRY_AGENT_ENDPOINTS=$agents \
      BASIC_AUTH_USERNAME=check \
      BASIC_AUTH_HASH='$2a$14$abcdefghijklmnopqrstuuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0' \
      FOUNDRY_SITE_UPSTREAM=site.railway.internal:3000 \
      FOUNDRY_API_UPSTREAM=foundry.railway.internal:8081 \
      caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile || exit 1; \
    done

EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/railway-gateway.sh"]
CMD []
