# Foundry: Helix Foundry's API, MCP and workers (the `foundry` binary) and its
# ontology agent, in one container.
#
# Upstream runs them in one pod (local/compose.yaml): the agent serves foundry
# on 127.0.0.1:50051 and reads the snapshot files foundry writes to /work.
# A Railway volume belongs to one service, so both processes share this one.
#
# Both images are HelixDB's own releases, pinned by tag and digest, and used
# unchanged. The agent needs glibc 2.38 (Debian 13), the foundry binary is a
# static Go build, so this image starts from the agent's and copies foundry in.
# FOUNDRY_IMAGE and FOUNDRY_AGENT_IMAGE are service variables; Railway passes
# them to the build as arguments, so an upgrade is a variable change.
ARG FOUNDRY_IMAGE=ghcr.io/helixdb/foundry:0.1.2@sha256:5adf4ca93c2b53661275ff3b9a4c5054d8ee42acfa569c4dcbfd2c8b6b27ba62
ARG FOUNDRY_AGENT_IMAGE=ghcr.io/helixdb/ontology-agent:0.1.1@sha256:d5a543bee8d9f403fa898ad5773b9a3d95b394f31396b36ec2b13448af07faa8

FROM ${FOUNDRY_IMAGE} AS foundry

FROM ${FOUNDRY_AGENT_IMAGE}

USER root

# curl: the start script waits for the S3 store's health URL. Foundry's own
# user (65532), as upstream: it owns /work and runs both processes.
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl \
 && rm -rf /var/lib/apt/lists/* \
 && groupadd --system --gid 65532 foundry \
 && useradd --system --uid 65532 --gid 65532 --create-home --home-dir /home/foundry --shell /usr/sbin/nologin foundry \
 && mkdir -p /work \
 && chown 65532:65532 /work

COPY --from=foundry /usr/local/bin/foundry /usr/local/bin/foundry
COPY --from=foundry /etc/foundry/foundry.yaml /etc/foundry/foundry.yaml
# /usr/local/bin exists in the base image, so --chmod only applies to the file.
COPY --chmod=0755 railway-foundry.sh /usr/local/bin/railway-foundry.sh

# Fail the build, not the deploy, if either binary or the config is missing.
RUN test -x /usr/local/bin/foundry \
 && test -x /usr/local/bin/ontology-agent \
 && test -s /etc/foundry/foundry.yaml \
 && bash -n /usr/local/bin/railway-foundry.sh \
 && for tool in bash setpriv curl sha256sum base64 timeout; do command -v "$tool" >/dev/null || { echo "missing $tool" >&2; exit 1; }; done

# Railway health-checks /readyz over HTTP (PORT); the agent image's exec probe
# does not apply here.
HEALTHCHECK NONE
WORKDIR /home/foundry
EXPOSE 8081 8083
ENTRYPOINT ["/usr/local/bin/railway-foundry.sh"]
CMD []
