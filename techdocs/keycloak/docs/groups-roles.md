# Groups and Roles

## Keycloak Groups

The `sentinel` realm defines three groups that map to authorization levels across all integrated services:

| Group | Purpose | Typical Members |
|-------|---------|-----------------|
| **admin** | Full administrative access to all services | `koiakoia`, `admin` |
| **operator** | Operational access (view + limited write) | `dan`, operations staff |
| **viewer** | Read-only access across services | Stakeholders, auditors |

## Group-to-Service Role Mapping

When a user authenticates via Keycloak, their group membership is included in the OIDC token claims (typically via a group mapper). Each service maps these groups to its own internal roles:

### ArgoCD

| Keycloak Group | ArgoCD Role | Permissions |
|----------------|-------------|-------------|
| admin | `role:admin` | Full access: create/delete apps, sync, manage settings |
| operator | `role:readonly` | View applications, sync status, logs |
| viewer | `role:readonly` | View applications, sync status, logs |

ArgoCD RBAC is configured in the ArgoCD CR `spec.rbac.policy` in the `openshift-gitops` namespace. [VERIFY exact policy CSV]

### Grafana

| Keycloak Group | Grafana Org Role | Permissions |
|----------------|------------------|-------------|
| admin | Admin | Full dashboard/datasource management |
| operator | Editor | Create/edit dashboards, view all data |
| viewer | Viewer | View dashboards only |

Grafana maps Keycloak groups to org roles via the `auth.generic_oauth` configuration in its Helm values. [VERIFY exact role_attribute_path setting]

### Harbor

| Keycloak Group | Harbor Role | Permissions |
|----------------|-------------|-------------|
| admin | Admin | Manage projects, users, replication, robot accounts |
| operator | Developer | Push/pull images, manage tags |
| viewer | Guest | Pull images only |

Harbor uses OIDC group claims to auto-assign project roles. Note: OIDC mode disables local password auth for the Docker `/v2/` API -- CI pipelines use robot accounts instead. [VERIFY exact Harbor OIDC group mapping]

### NetBox

| Keycloak Group | NetBox Role | Permissions |
|----------------|-------------|-------------|
| admin | Superuser / Admin | Full DCIM/IPAM management |
| operator | Staff | Create/edit devices, IPs, sites |
| viewer | Read-only | View inventory only |

[VERIFY exact NetBox OIDC group-to-permission mapping]

### GitLab

| Keycloak Group | GitLab Role | Permissions |
|----------------|-------------|-------------|
| admin | Admin | Instance administration |
| operator | Developer/Maintainer | Push, merge, manage projects |
| viewer | Guest/Reporter | View code, create issues |

GitLab uses OmniAuth OIDC. Group mapping may be configured via GitLab SAML/OIDC group sync. [VERIFY if GitLab auto-maps Keycloak groups or uses manual assignment]

### Wazuh (OpenSearch Dashboards)

| Keycloak Group | OpenSearch Role | Permissions |
|----------------|-----------------|-------------|
| admin | admin | Full dashboard and index management |
| operator | readall | View all indices and dashboards |
| viewer | kibana_read_only | Dashboard viewing only |

[VERIFY exact OpenSearch OIDC role mapping in security config]

### DefectDojo

| Keycloak Group | DefectDojo Role | Permissions |
|----------------|-----------------|-------------|
| admin | Superuser | Full vulnerability management |
| operator | Staff | Manage findings, products |
| viewer | Reader | View findings only |

[VERIFY exact DefectDojo OIDC group mapping]

### Overwatch Console

| Keycloak Group | Console Role | Permissions |
|----------------|--------------|-------------|
| admin | Full access | All dashboard panels, work log, settings |
| operator | Operational | Dashboard panels, work log |
| viewer | Read-only | Dashboard viewing only |

### Backstage

Backstage does not enforce fine-grained authorization based on groups -- all authenticated users can access the catalog and TechDocs. Group membership is available for future RBAC plugin integration.

## Token Claims

Keycloak includes group membership in OIDC tokens via protocol mappers. The standard configuration includes:

- **groups** claim: array of group names the user belongs to (e.g., `["admin"]`)
- **preferred_username** claim: the Keycloak username
- **email** claim: user's email address
- **aud** claim: target client_id (configured per-client via audience mapper)

Services typically read the `groups` claim to determine authorization level. The exact claim name may vary per client mapper configuration.

## Managing Users and Groups

### Adding a New User

1. Log in to Keycloak admin console at `https://auth.208.haist.farm`
2. Select the `sentinel` realm
3. Navigate to Users > Add User
4. Set username, email, and required actions (e.g., Update Password)
5. After creation, go to the Groups tab and join the appropriate group

### Changing Group Membership

1. Keycloak admin console > Users > select user > Groups tab
2. Join or Leave groups as needed
3. The user's next token refresh will include updated group claims
4. Note: `KC_SPI_USER_CACHE_DEFAULT_ENABLED=false` is set, so changes are immediately visible to Keycloak (no cache invalidation needed). However, downstream services may cache the token until it expires.

### Adding a New Service Client

1. Keycloak admin console > Clients > Create Client
2. Set Client ID, protocol (OpenID Connect), access type (confidential for server-side, public for SPAs)
3. Configure redirect URIs (both internal `*.208.haist.farm` and external `*.haist.farm` if needed)
4. Add protocol mappers:
   - Group membership mapper (claim name: `groups`, full group path: off)
   - Audience mapper if the service validates the `aud` claim
5. Store the client secret in Vault at the appropriate path
6. Create an ExternalSecret in the service's namespace to pull the secret

## SMTP Configuration

Keycloak is configured to send emails via Mailjet for:

- Email verification for new users
- Password reset flows
- Admin notifications

SMTP egress is explicitly allowed by NetworkPolicy on port 587 to external IPs (Mailjet servers). The SMTP configuration is set in the Keycloak admin console under Realm Settings > Email.
