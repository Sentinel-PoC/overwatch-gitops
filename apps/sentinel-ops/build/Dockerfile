# ── Stage 1: etcdctl binary extraction ──────────────────────────────────────
# OPS-239: Add etcdctl 3.5.x for cross-namespace etcd backup pattern (OPS-183 refactor).
# Multi-stage build keeps the final image lean (only the binary, not the full tarball).
# Version: v3.5.29 — latest stable 3.5.x (published 2026-04-01); API-compatible with
#   OCP 4.19 etcd server (3.5.x series). Pinned by SHA256 for supply-chain integrity.
FROM python:3.12-slim AS etcdctl-builder

ARG ETCDCTL_VERSION=v3.5.29
ARG ETCDCTL_SHA256=7692f812db0bfeee3a731c45046864cf729e552bad82ce7cb5b507053d033267

RUN apt-get update && \
    apt-get upgrade -y --no-install-recommends && \
    apt-get install -y --no-install-recommends curl && \
    rm -rf /var/lib/apt/lists/*

RUN curl -fsSL \
      "https://github.com/etcd-io/etcd/releases/download/${ETCDCTL_VERSION}/etcd-${ETCDCTL_VERSION}-linux-amd64.tar.gz" \
      -o /tmp/etcd.tar.gz && \
    echo "${ETCDCTL_SHA256}  /tmp/etcd.tar.gz" | sha256sum -c - && \
    tar xzf /tmp/etcd.tar.gz \
      -C /tmp \
      "etcd-${ETCDCTL_VERSION}-linux-amd64/etcdctl" \
      --strip-components=1 && \
    install -m 755 /tmp/etcdctl /usr/local/bin/etcdctl && \
    rm -f /tmp/etcd.tar.gz /tmp/etcdctl

# ── Stage 2: final image ─────────────────────────────────────────────────────
FROM python:3.12-slim

RUN apt-get update && \
    apt-get upgrade -y --no-install-recommends && \
    apt-get install -y --no-install-recommends \
    curl jq ca-certificates unzip && \
    rm -rf /var/lib/apt/lists/*

# Install mc (MinIO client) with checksum verification
# OPS-254: pin MC_VERSION because mc.sha256sum file references the release-tagged
# filename (mc.RELEASE.<ts>), but `curl ... mc -o /usr/local/bin/mc` saved the
# binary as plain "mc". sha256sum -c then failed with "mc.RELEASE.<ts>: No such
# file or directory". Pin a known-good version, download to the matching
# filename, verify, then mv to plain "mc".
RUN MC_VERSION="RELEASE.2025-08-13T08-35-41Z" && \
    curl -fsSL "https://dl.min.io/client/mc/release/linux-amd64/mc.${MC_VERSION}" -o "/usr/local/bin/mc.${MC_VERSION}" && \
    curl -fsSL "https://dl.min.io/client/mc/release/linux-amd64/mc.${MC_VERSION}.sha256sum" -o /tmp/mc.sha256sum && \
    cd /usr/local/bin && sha256sum -c /tmp/mc.sha256sum && \
    mv "mc.${MC_VERSION}" mc && chmod +x mc && rm /tmp/mc.sha256sum

# Install vault CLI with checksum verification
# OPS-254: same filename/sha256sum mismatch pattern as the mc install above —
# vault_*.SHA256SUMS lists the file by its full release name, so the download
# target must match. Save as vault_<ver>_linux_amd64.zip not vault.zip.
RUN curl -fsSL https://releases.hashicorp.com/vault/1.21.2/vault_1.21.2_linux_amd64.zip -o /tmp/vault_1.21.2_linux_amd64.zip && \
    curl -fsSL https://releases.hashicorp.com/vault/1.21.2/vault_1.21.2_SHA256SUMS -o /tmp/vault_sums.txt && \
    cd /tmp && grep vault_1.21.2_linux_amd64.zip vault_sums.txt | sha256sum -c - && \
    unzip vault_1.21.2_linux_amd64.zip && mv vault /usr/local/bin/ && rm vault_1.21.2_linux_amd64.zip vault_sums.txt

# Copy etcdctl from builder stage (binary only — tarball not included in final image)
COPY --from=etcdctl-builder /usr/local/bin/etcdctl /usr/local/bin/etcdctl

# Python HTTP client
RUN pip install --no-cache-dir requests

USER 1000
WORKDIR /opt/sentinel-ops
