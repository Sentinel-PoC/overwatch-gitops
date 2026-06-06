# Keycloak Operations

## Platform Identity Provider

Keycloak is the **sole identity provider (IdP)** for Project Sentinel. Every authenticated service in the platform federates authentication through Keycloak using OpenID Connect (OIDC). No alternative IdP (Cloudflare email OTP, GitLab native auth, etc.) is used unless explicitly approved.

## Deployment Summary

| Property | Value |
|----------|-------|
| **Realm** | `sentinel` |
| **Internal URL** | `https://auth.208.haist.farm` |
| **External URL** | `https://auth.haist.farm` |
| **Version** | Keycloak 26.1.4 |
| **OKD Namespace** | `keycloak` |
| **ArgoCD App** | `keycloak` (auto-sync, self-heal, prune) |
| **Database** | PostgreSQL 16.8 |
| **Image Registry** | `harbor.208.haist.farm/sentinel/keycloak:26.1.4` |

## What Keycloak Provides

- **SSO for 14 OIDC clients** -- platform services, external access gateways, monitoring, and automation accounts all authenticate through the `sentinel` realm.
- **Group-based RBAC** -- three groups (`admin`, `operator`, `viewer`) map to roles across all integrated services (Grafana, ArgoCD, Harbor, NetBox, etc.).
- **External access gateway** -- the `cloudflare-access` client acts as the IdP for Cloudflare Access, and the `oauth2-proxy` client provides ForwardAuth for externally published services.
- **Service account authentication** -- the `mcp-service-cli` client provides machine-to-machine auth for MCP tooling.
- **Custom login theme** -- a branded "Project Sentinel" theme with animated background, custom colors, and responsive design is deployed via ConfigMap.
- **Email notifications** -- SMTP integration via Mailjet (port 587) for password resets and verification emails.

## Users

The `sentinel` realm contains the following users:

| Username | Purpose |
|----------|---------|
| `admin` | Keycloak realm administrator |
| `koiakoia` | Primary operator account |
| `dan` | Operator account |
| `mcp-service` | Machine-to-machine service account for MCP servers |
| Other accounts | Auto-provisioned via OIDC flows |

## Architecture Overview

```
                    External Users
                         |
                   Cloudflare Tunnel
                         |
                    auth.haist.farm
                         |
              +----------+----------+
              |   Pangolin Proxy    |
              |   (Traefik :443)    |
              +----------+----------+
                         |
              auth.208.haist.farm
                         |
              +----------+----------+
              |   OKD Route (edge   |
              |   TLS termination)  |
              +----------+----------+
                         |
              +----------+----------+
              |    Keycloak :8080   |
              |  (keycloak ns)      |
              +----------+----------+
                         |
              +----------+----------+
              |  PostgreSQL :5432   |
              |  (keycloak ns)      |
              +----------+----------+
                         |
                   NFS PVC (10Gi)
```

Traffic flow:

1. Internal users reach `auth.208.haist.farm` via Tailscale split DNS or LAN dnsmasq, resolved to `192.168.12.168` (pangolin-proxy), then Traefik forwards to the OKD ingress router.
2. External users reach `auth.haist.farm` via Cloudflare DNS CNAME pointing to a Cloudflare Tunnel, which routes through cloudflared on pangolin-proxy to Traefik.
3. The OKD Route terminates TLS (edge) and forwards plaintext HTTP to the Keycloak Service on port 8080.
4. Keycloak connects to the co-located PostgreSQL instance on port 5432 (namespace-local, NetworkPolicy enforced).

## Key Operational Rules

- **GitOps only** -- all changes to Keycloak deployment manifests go through `overwatch-gitops` repo. ArgoCD auto-syncs from `main`. Never `oc patch` or `oc edit` directly.
- **Secrets via Vault** -- admin credentials and PostgreSQL credentials are managed by ExternalSecrets from HashiCorp Vault. Never hardcode secrets in manifests.
- **Istio injection disabled** -- the `keycloak` namespace has `istio-injection: disabled`. Keycloak is an unmeshed service that routes via the OKD Router, not the Istio IngressGateway.
- **X-Frame-Options** -- the Keycloak admin console requires `SAMEORIGIN` (not `DENY`). The Traefik middleware `security-headers-keycloak` handles this. See [Troubleshooting](troubleshooting.md).
