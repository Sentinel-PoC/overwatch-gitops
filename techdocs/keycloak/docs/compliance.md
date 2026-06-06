# Compliance

Keycloak directly supports several NIST 800-53 controls in the Project Sentinel compliance framework. This page maps Keycloak's role to specific controls and identifies where compliance evidence is generated.

## NIST 800-53 Control Mapping

### IA-2: Identification and Authentication (Organizational Users)

**Control requirement**: Uniquely identify and authenticate organizational users.

**How Keycloak satisfies this**:

- All platform users authenticate through Keycloak's `sentinel` realm with unique usernames
- OIDC tokens include `preferred_username`, `sub` (unique user ID), and `email` claims
- Password policies are enforced at the realm level (complexity, history, expiration)
- Event logging (`KC_SPI_EVENTS_STORE_PROVIDER=jpa`) records all authentication events to PostgreSQL with timestamps, usernames, IP addresses, and outcomes

**Evidence**:

- Keycloak admin console > Events > Login Events (successful and failed)
- Keycloak event logs in PostgreSQL (queryable via admin REST API)
- Daily compliance check validates SSO is operational (`nist-compliance-check.sh`)

### IA-5: Authenticator Management

**Control requirement**: Manage information system authenticators (passwords, tokens, certificates).

**How Keycloak satisfies this**:

- Password policies configurable per-realm (length, complexity, expiry, history)
- OIDC tokens have configurable TTL (access token, refresh token lifespans)
- Client secrets are stored in Vault and rotated via ExternalSecrets
- Session timeout and idle timeout configurable in realm settings

**Related WARN**: IA-5(13) -- token TTL validation is one of the 6 remaining WARNs in the compliance check. The check verifies that token lifespans are within acceptable bounds.

### IA-8: Identification and Authentication (Non-Organizational Users)

**Control requirement**: Identify and authenticate non-organizational users.

**How Keycloak satisfies this**:

- External users authenticate through the same Keycloak OIDC flow
- Cloudflare Access provides a pre-authentication layer before Keycloak
- oauth2-proxy adds service-level authentication for externally published services
- All external authentication events are logged in Keycloak events store

### AC-2: Account Management

**Control requirement**: Manage information system accounts (create, enable, modify, disable, remove).

**How Keycloak satisfies this**:

- Centralized user management in the `sentinel` realm
- Three groups (admin, operator, viewer) provide tiered access
- User accounts can be enabled/disabled without deletion
- Required actions (password reset, email verification) can be set per-user
- Admin console provides full user lifecycle management
- Group membership changes propagate to all integrated services via OIDC token claims

**Evidence**:

- Keycloak admin console > Users (user listing with status)
- Keycloak admin events log (all administrative changes)
- Group membership visible in admin console > Groups

### AC-3: Access Enforcement

**Control requirement**: Enforce approved authorizations for logical access.

**How Keycloak satisfies this**:

- OIDC tokens include group claims that services use for authorization decisions
- Each service maps groups to internal roles (admin/editor/viewer patterns)
- NetworkPolicies restrict which pods can receive traffic from the ingress layer
- Client-level access can be restricted via Keycloak client policies

### AC-7: Unsuccessful Logon Attempts

**Control requirement**: Enforce a limit of consecutive invalid logon attempts and take action.

**How Keycloak satisfies this**:

- Brute force detection is configurable in the `sentinel` realm settings
- After N failed attempts, the account can be temporarily or permanently locked
- Failed login events are logged with IP address and username

**Evidence**:

- Keycloak admin console > Realm Settings > Security Defenses > Brute Force Detection
- Event log: failed login events with `LOGIN_ERROR` type

[VERIFY exact brute force settings (max failures, wait time, lockout duration)]

### AC-14: Permitted Actions Without Identification or Authentication

**Control requirement**: Identify user actions that can be performed without authentication.

**How Keycloak satisfies this**:

- The Keycloak login page itself is unauthenticated (by necessity)
- OIDC discovery endpoints (`/.well-known/openid-configuration`) are public
- All other actions require authentication
- oauth2-proxy bypass paths (GitLab API, Matrix federation endpoints) are explicitly documented and limited to machine-to-machine APIs that use their own authentication mechanisms (PAT, federation keys)

**Evidence**:

- NetworkPolicy manifests define what traffic is allowed
- oauth2-proxy bypass paths documented in Traefik middleware config
- Service-level `AuthorizationPolicy` objects (for meshed services)

### AU-2: Event Logging / AU-3: Content of Audit Records

**Control requirement**: Generate and retain audit records with sufficient detail.

**How Keycloak satisfies this**:

- Login events stored in PostgreSQL via JPA event store provider
- Event detail length up to 1000 characters (`KC_SPI_EVENTS_STORE_JPA_MAX_DETAIL_LENGTH=1000`)
- Success events logged at INFO level (`KC_SPI_EVENTS_LISTENER_JBOSS_LOGGING_SUCCESS_LEVEL=info`)
- Admin events capture all configuration changes (client creation, user management, realm settings)
- Events include: timestamp, event type, realm, client, user, IP address, session ID, error

### SC-12: Cryptographic Key Establishment and Management

**Control requirement**: Establish and manage cryptographic keys.

**How Keycloak satisfies this**:

- Keycloak manages its own RSA key pairs for signing OIDC tokens (JWT RS256)
- Keys are automatically rotated by Keycloak (configurable rotation policy)
- TLS is terminated at the OKD Route (edge termination with OKD-managed certificates)
- Client secrets are managed in Vault and delivered via ExternalSecrets

## Compliance Evidence Locations

| Evidence Type | Location |
|---------------|----------|
| Authentication events | Keycloak admin console > Events > Login Events |
| Admin audit trail | Keycloak admin console > Events > Admin Events |
| User inventory | Keycloak admin console > Users |
| Group membership | Keycloak admin console > Groups |
| Client configuration | Keycloak admin console > Clients |
| Realm security settings | Keycloak admin console > Realm Settings > Security Defenses |
| Deployment manifests | `overwatch-gitops/apps/keycloak/` |
| Vault secrets (metadata only) | `secret/keycloak/admin`, `secret/keycloak/postgresql`, `secret/keycloak/oauth2-proxy`, `secret/keycloak/synapse` |
| NetworkPolicy definitions | `apps/keycloak/network-policies.yaml` |
| Daily compliance reports | `compliance-vault/reports/daily/` |
| NIST gap analysis | `sentinel-iac-work/docs/nist-gap-analysis.md` |

## Automated Compliance Checks

The daily `nist-compliance-check.sh` script (runs at 6AM UTC on iac-control) includes checks relevant to Keycloak:

- Verifies Keycloak pod is running and healthy
- Validates OIDC endpoint availability
- Checks token TTL configuration (related to IA-5(13) WARN)
- Verifies SSO integration is functional

Results are published to `compliance-vault/reports/daily/` and tracked in `compliance-vault/reports/compliance-trend-summary.md`.

## Wazuh Integration

Keycloak authentication events can be forwarded to Wazuh for SIEM correlation:

- Failed login attempts generate alerts
- Brute force patterns are detected
- Account lockouts are monitored
- Events correlate with Wazuh agent data from other VMs

[VERIFY exact Wazuh rules that process Keycloak events and whether log forwarding is configured]
