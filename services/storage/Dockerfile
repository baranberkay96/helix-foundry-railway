# Storage: the S3-compatible store Foundry keeps synced tables, snapshots and
# documents in, as upstream's `storage` service (SeaweedFS 4.47, the same
# image and digest as local/compose.yaml), with one S3 identity for Foundry.
#
# Foundry signs browser uploads for the store's own address, so the store is
# reached at its public Railway domain by both Foundry and the browser (only
# the S3 API listens beyond loopback; it checks every request's signature).
# A Railway Bucket cannot replace it: Foundry addresses its store path-style
# and creates its bucket on every start.
ARG FOUNDRY_STORAGE_IMAGE=chrislusf/seaweedfs:4.47@sha256:ce9e796f1fe6f06968f4c04bdaf8f678dad9c8acdfef3d244133d71bfa6bf882
FROM ${FOUNDRY_STORAGE_IMAGE}

# /usr/local/bin exists in the base image, so --chmod only applies to the file.
COPY --chmod=0755 railway-storage.sh /usr/local/bin/railway-storage.sh
RUN sh -n /usr/local/bin/railway-storage.sh && command -v weed >/dev/null

ENTRYPOINT ["/usr/local/bin/railway-storage.sh"]
CMD []
