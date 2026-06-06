# OIDC Clients

The `sentinel` realm contains 15 custom OIDC clients (plus 8 Keycloak built-in clients). All custom clients use the OpenID Connect protocol.

## Client Inventory

### Platform Services

These clients provide SSO for core platform services deployed in OKD or on VMs.

#### argocd

| Property | Value |
|----------|-------|
| **Client ID** | `argocd` |
| **Purpose** | ArgoCD GitOps dashboard SSO |
| **Service URL** | `https://argocd.208.haist.farm` |
| **Notes** | ArgoCD RBAC maps Keycloak groups to ArgoCD roles. Admin group gets `role:admin`, operator gets `role:readonly` [VERIFY exact RBAC mapping in ArgoCD configmap] |

#### backstage

| Property | Value |
|----------|-------|
| **Client ID** | `backstage` |
| **Purpose** | Backstage developer portal SSO |
| **Service URL** | `https://backstage.208.haist.farm` |
| **Notes** | Standard OIDC code flow |

#### defectdojo

| Property | Value |
|----------|-------|
| **Client ID** | `defectdojo` |
| **Purpose** | DefectDojo ASDB platform SSO |
| **Service URL** | `https://defectdojo.208.haist.farm` |
| **Notes** | Vulnerability tracking dashboard |

#### forgejo

| Property | Value |
|----------|-------|
| **Client ID** | `forgejo` |
| **Purpose** | Forgejo git host SSO |
| **Service URL** | `https://forgejo.208.haist.farm` |
| **Notes** | Declared in Ansible at `sentinel-iac/ansible/roles/forgejo-server/tasks/keycloak-client.yml` (OPS-188). Callback path is lowercase `/user/oauth2/keycloak/callback`. A capital-K redirect URI was temporarily registered as an interim compatibility measure while the Forgejo DB auth source Name was migrated from "Keycloak" (UI typo) to lowercase "keycloak" — tracked for removal after migration completes |

#### gitlab

| Property | Value |
|----------|-------|
| **Client ID** | `gitlab` |
| **Purpose** | GitLab CI/CD platform SSO |
| **Service URL** | `https://gitlab.haist.farm` (external) / `http://192.168.12.68` (direct) |
| **Notes** | Uses Keycloak as OmniAuth OIDC provider. External access additionally protected by oauth2-proxy ForwardAuth |

#### grafana

| Property | Value |
|----------|-------|
| **Client ID** | `grafana` |
| **Purpose** | Grafana observability dashboards SSO |
| **Service URL** | `https://grafana.208.haist.farm` |
| **Notes** | Keycloak groups map to Grafana org roles (admin/editor/viewer) [VERIFY exact role mapping in Grafana helm values] |

#### harbor

| Property | Value |
|----------|-------|
| **Client ID** | `harbor` |
| **Purpose** | Harbor container registry SSO |
| **Service URL** | `https://harbor.208.haist.farm` |
| **Notes** | OIDC mode blocks local password auth for `/v2/` API -- CI uses robot accounts (`robot$ci-system`) instead |

#### netbox

| Property | Value |
|----------|-------|
| **Client ID** | `netbox` |
| **Purpose** | NetBox DCIM/IPAM SSO |
| **Service URL** | `https://netbox.208.haist.farm` |
| **Notes** | Standard OIDC code flow |

#### okd-console

| Property | Value |
|----------|-------|
| **Client ID** | `okd-console` |
| **Purpose** | OKD web console SSO |
| **Service URL** | `https://console-openshift-console.apps.overwatch.haist.farm` [VERIFY] |
| **Notes** | OKD OAuth server configured to use Keycloak as identity provider |

#### overwatch-console

| Property | Value |
|----------|-------|
| **Client ID** | `overwatch-console` |
| **Purpose** | Security operations dashboard SSO |
| **Service URL** | `https://console-sec.208.haist.farm` |
| **Notes** | FastAPI + React app, standard OIDC code flow |

#### pangolin

| Property | Value |
|----------|-------|
| **Client ID** | `pangolin` |
| **Purpose** | Pangolin proxy management interface SSO |
| **Service URL** | `https://pangolin.208.haist.farm` [VERIFY] |
| **Notes** | Reverse proxy admin panel authentication |

#### wazuh

| Property | Value |
|----------|-------|
| **Client ID** | `wazuh` |
| **Purpose** | Wazuh SIEM dashboard SSO |
| **Service URL** | `https://wazuh.208.haist.farm` |
| **Notes** | OpenSearch Dashboards OIDC integration. Wazuh OpenSearch PEM CA must be in `/etc/wazuh-indexer/` tree |

### Matrix / Communication

#### matrix-authentication-service

| Property | Value |
|----------|-------|
| **Client ID** | `matrix-authentication-service` |
| **Purpose** | Matrix Authentication Service (MAS) OIDC |
| **Service URL** | `https://matrix.208.haist.farm` (internal) / `https://matrix.haist.farm` (external) |
| **Notes** | MAS v0.12.0 upstream OIDC issuer MUST be `auth.208.haist.farm` (internal address) because MAS runs in the air-gapped OKD cluster and cannot reach `auth.haist.farm` via Cloudflare. Redirect URIs must cover BOTH hostnames |

#### synapse

| Property | Value |
|----------|-------|
| **Client ID** | `synapse` |
| **Purpose** | Synapse Matrix homeserver (legacy/direct OIDC) |
| **Service URL** | `https://matrix.208.haist.farm` |
| **Notes** | May be a legacy client from before MAS was deployed [VERIFY if still actively used or superseded by matrix-authentication-service] |

### External Access

#### cloudflare-access

| Property | Value |
|----------|-------|
| **Client ID** | `cloudflare-access` |
| **Purpose** | Cloudflare Access identity provider |
| **Notes** | Keycloak acts as the OIDC IdP for Cloudflare Access. Cloudflare Access policies use this client to authenticate users before granting access to externally published services. CF Access application ID: `3e540434-...` |

#### oauth2-proxy

| Property | Value |
|----------|-------|
| **Client ID** | `oauth2-proxy` |
| **Purpose** | ForwardAuth gateway for external services |
| **Notes** | oauth2-proxy v7.7.1 on pangolin-proxy. Protects `gitlab.haist.farm` and `matrix.haist.farm` with Traefik ForwardAuth middleware. Cookie: `_oauth2_proxy` on `.haist.farm`, 10h expiry, 30min refresh. Credentials in Vault `secret/keycloak/oauth2-proxy`, cookie secret in `secret/pangolin/oauth2-proxy`. Issuer MUST be `auth.haist.farm` (external) to share Keycloak session cookies with apps |

### Automation / Machine-to-Machine

#### haists-website

| Property | Value |
|----------|-------|
| **Client ID** | `haists-website` |
| **Purpose** | Public website backend API authentication |
| **Service URL** | `https://www.haist.farm` |
| **Notes** | Uses OIDC `client_credentials` grant (machine-to-machine) to proxy requests to the Overwatch Console API |

#### mcp-service-cli

| Property | Value |
|----------|-------|
| **Client ID** | `mcp-service-cli` |
| **Purpose** | MCP server CLI authentication |
| **Notes** | Used by the `mcp-service` user for machine-to-machine authentication. Provides token for MCP Keycloak server operations. Credentials stored in Vault `secret/mcp` |

## Built-in Clients

These are Keycloak system clients and should not be modified:

| Client ID | Purpose |
|-----------|---------|
| `account` | User self-service account management |
| `account-console` | Account management UI |
| `admin-cli` | Admin CLI tool authentication |
| `broker` | Identity brokering |
| `realm-management` | Realm administration |
| `security-admin-console` | Admin console |

## Client Configuration Patterns

### Standard OIDC Code Flow

Most platform service clients use the authorization code flow:

1. User visits service (e.g., Grafana)
2. Service redirects to `auth.208.haist.farm/realms/sentinel/protocol/openid-connect/auth`
3. User authenticates (or existing session is reused)
4. Keycloak redirects back with authorization code
5. Service exchanges code for tokens at the token endpoint

### Client Credentials Grant

Machine-to-machine clients (`haists-website`) use the client credentials grant:

1. Backend service authenticates directly with client_id and client_secret
2. Keycloak returns an access token
3. Token is used to call downstream APIs

### Audience Mapper

Several clients require an `oidc-audience-mapper` to include the `client_id` in the `aud` claim of the access token. This is required for services that validate the audience claim (notably Matrix Authentication Service).

## Vault Secret Paths for Client Credentials

| Client | Vault Path |
|--------|-----------|
| oauth2-proxy | `secret/keycloak/oauth2-proxy` |
| matrix-authentication-service | `secret/keycloak/synapse` |
| mcp-service-cli | `secret/mcp` (keycloak field) |
| forgejo | `secret/keycloak/forgejo` |
| haists-website | [VERIFY vault path] |
| General Keycloak admin | `secret/keycloak/admin` |
