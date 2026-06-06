# Troubleshooting

## X-Frame-Options: SAMEORIGIN for Admin Console

**Symptom**: Keycloak admin console fails to load or shows a blank iframe.

**Cause**: The default security headers middleware sets `X-Frame-Options: DENY`, which prevents the Keycloak admin console from loading in its own iframes.

**Fix**: Traefik on pangolin-proxy uses a dedicated middleware `security-headers-keycloak` that sets `X-Frame-Options: SAMEORIGIN` instead of `DENY`. Verify the middleware is applied to the `auth.208.haist.farm` route in the Traefik dynamic config (`sentinel-okd-services.yml` on pangolin-proxy).

If the admin console is still blank, check:

1. The route in Traefik references the correct middleware name
2. The middleware is defined in `sentinel-middlewares.yml`
3. No other middleware is overriding the header

---

## Login Loops

### Symptom: Redirect loop between service and Keycloak

**Possible causes**:

1. **Mismatched redirect URI** -- the redirect URI registered in the Keycloak client does not match what the service sends. Check the Keycloak admin console > Clients > select client > Valid Redirect URIs. The URI must exactly match (including trailing slashes and protocol).

2. **Cookie domain mismatch** -- if the service and Keycloak are on different domains and cookies cannot be shared. Internal services should use `*.208.haist.farm` consistently.

3. **HTTPS/HTTP mismatch** -- Keycloak has `KC_PROXY_HEADERS=xforwarded` and `KC_HTTP_ENABLED=true`. If the `X-Forwarded-Proto` header is not set to `https` by the upstream proxy, Keycloak may generate redirect URIs with `http://` causing the browser to reject cookies or loop.

4. **MAS-specific**: Matrix Authentication Service "human" endpoints (`/login`, `/consent`, `/register`, `/reauth`, `/logout`, `/recover`, `/verify-email`, `/link`, `/device`, `/authorize`) MUST have explicit OKD Routes. Element's nginx SPA catch-all (`try_files $uri /index.html`) will swallow these paths and cause login loops if routes are missing.

### Debugging steps

```
1. Open browser DevTools > Network tab
2. Clear cookies for the domain
3. Attempt login
4. Watch for 302 redirects -- note the Location header at each hop
5. Check if redirect URIs match what is registered in Keycloak
6. Check for cookie Set-Cookie headers (domain, path, Secure flag)
```

---

## Double Authentication Prompts

**Symptom**: User is prompted to log in twice when accessing an external service.

**Cause**: This happens when the oauth2-proxy issuer URL does not match the issuer used by Cloudflare Access, so separate Keycloak sessions are created.

**Fix**: oauth2-proxy issuer MUST be `https://auth.haist.farm/realms/sentinel` (the external URL). This ensures that when a user authenticates via Cloudflare Access (which redirects to `auth.haist.farm`), the resulting Keycloak session cookie is valid for oauth2-proxy's subsequent token request. If oauth2-proxy used `auth.208.haist.farm`, it would not see the existing session and would prompt again.

Check the oauth2-proxy configuration:

```
# On pangolin-proxy, verify:
OAUTH2_PROXY_OIDC_ISSUER_URL=https://auth.haist.farm/realms/sentinel
```

---

## MAS OIDC Issuer Must Be Internal

**Symptom**: Matrix login fails, MAS cannot discover OIDC endpoints.

**Cause**: Matrix Authentication Service runs inside the air-gapped OKD cluster. Pods in OKD cannot reach `auth.haist.farm` because that domain resolves via Cloudflare DNS to a Cloudflare Tunnel endpoint, which is not reachable from the cluster network.

**Fix**: MAS upstream OIDC issuer MUST be `auth.208.haist.farm` (the internal address). This is resolved via the cluster's DNS to the OKD Route, which is reachable from within the cluster.

In the MAS configuration:

```
upstream_oauth2:
  issuer: https://auth.208.haist.farm/realms/sentinel
```

Note: The `matrix-authentication-service` client in Keycloak needs redirect URIs for BOTH `matrix.208.haist.farm` AND `matrix.haist.farm` since users may access from either network.

---

## oauth2-proxy ForwardAuth Returns 401 Instead of Redirect

**Symptom**: Accessing a protected external service returns a 401 error page instead of redirecting to Keycloak login.

**Cause**: The Traefik ForwardAuth middleware is configured to point to `http://oauth2-proxy:4180/oauth2/auth` instead of `http://oauth2-proxy:4180/`.

**Fix**: The ForwardAuth URL must be the root path (`/`). The root path returns a 302 redirect for unauthenticated requests, which Traefik follows to redirect the user to Keycloak. The `/oauth2/auth` path returns a 401, which Traefik presents as-is.

---

## ESO Secret Sync Failures

**Symptom**: Keycloak pod fails to start, complaining about missing Secret or credentials.

**Possible causes**:

1. **Vault token expired** -- the ClusterSecretStore `vault-backend` uses Kubernetes auth. If the Vault K8s auth role or SA token is expired/misconfigured, ESO cannot fetch secrets.

2. **Vault path changed** -- verify the Vault paths exist:
   - `secret/keycloak/admin` (properties: `username`, `password`)
   - `secret/keycloak/postgresql` (properties: `db_name`, `db_user`, `db_password`)

3. **ESO backoff** -- if ESO encountered repeated failures, it may be in exponential backoff. Force a refresh:

   ```bash
   # On iac-control with KUBECONFIG set:
   oc annotate externalsecret keycloak-admin-credentials -n keycloak \
     reconcile.external-secrets.io/trigger=$(date +%s) --overwrite
   oc annotate externalsecret postgresql-credentials -n keycloak \
     reconcile.external-secrets.io/trigger=$(date +%s) --overwrite
   ```

4. **Check ESO status**:

   ```bash
   oc get externalsecret -n keycloak
   # STATUS should be "SecretSynced"
   ```

---

## PostgreSQL Startup Takes Very Long

**Symptom**: Keycloak pod stays in `NotReady` state for an extended period after a restart.

**Cause**: PostgreSQL may be performing WAL (Write-Ahead Log) recovery after an unclean shutdown. The startup probe allows up to 60 minutes (360 failures x 10s period) for this.

**Monitoring**:

```bash
# Check PostgreSQL logs
oc logs deployment/postgresql -n keycloak

# Look for WAL recovery messages
# "redo starts at...", "redo done at..."
```

**Important**: PostgreSQL memory limit is set to 4Gi. If WAL recovery is particularly large, OOM kills can occur. If the pod keeps restarting during recovery, check `oc describe pod` for OOMKilled events.

---

## Theme Not Displaying

**Symptom**: Keycloak login page shows the default theme instead of the custom Sentinel theme.

**Check**:

1. Verify the ConfigMap exists and has content:

   ```bash
   oc get configmap keycloak-sentinel-theme -n keycloak -o yaml
   ```

2. Verify the theme is selected in Keycloak admin console: Realm Settings > Themes > Login Theme = `sentinel`

3. Verify volume mounts in the pod:

   ```bash
   oc exec deployment/keycloak -n keycloak -- ls -la /opt/keycloak/themes/sentinel/login/
   oc exec deployment/keycloak -n keycloak -- ls -la /opt/keycloak/themes/sentinel/login/resources/css/
   ```

4. Clear browser cache -- Keycloak aggressively caches theme resources.

---

## Keycloak Pod CrashLoopBackOff

**Common causes**:

1. **Database not ready** -- PostgreSQL pod must be running before Keycloak starts. Check PostgreSQL pod status first.

2. **Invalid admin credentials** -- if the Secret `keycloak-admin-credentials` contains incorrect values, the bootstrap admin creation may fail. Check ESO sync status.

3. **Java heap exhaustion** -- Keycloak is limited to 2Gi memory. With many concurrent sessions, the JVM may run out of heap. Check pod events for OOMKilled:

   ```bash
   oc describe pod -l app=keycloak -n keycloak | grep -A5 "Last State"
   ```

4. **Database schema migration failure** -- after a Keycloak version upgrade, schema migration runs on first startup. If it fails (e.g., due to PostgreSQL version incompatibility or disk space), Keycloak will crash. Check logs:

   ```bash
   oc logs deployment/keycloak -n keycloak | grep -i "migration\|liquibase\|schema"
   ```

---

## Network Connectivity Issues

**Symptom**: Keycloak cannot reach PostgreSQL, or external services cannot reach Keycloak.

**Check NetworkPolicies**:

```bash
# List all network policies in the namespace
oc get networkpolicy -n keycloak

# Expected:
# default-deny-all        (deny everything by default)
# allow-keycloak          (ingress from router, egress to PG/DNS/SMTP)
# allow-postgresql        (ingress from keycloak, egress DNS)
# allow-istio-control-plane (egress to istio-system)
```

If a new integration needs to reach Keycloak (e.g., a new namespace), you may need to update the `allow-keycloak` NetworkPolicy to add an ingress rule. However, since Keycloak is accessed via the OKD Route (which is in the `openshift-ingress` namespace), most services do not need direct pod-to-pod access.

---

## SMTP Email Not Sending

**Symptom**: Password reset emails or verification emails are not delivered.

**Check**:

1. **NetworkPolicy**: Verify the `allow-keycloak` policy permits egress on port 587 to external IPs.

2. **SMTP config**: In Keycloak admin console, go to Realm Settings > Email. Verify host, port (587), authentication credentials, and From address.

3. **Mailjet status**: Check Mailjet dashboard for bounces, blocks, or quota limits.

4. **Pod logs**: Look for SMTP errors:

   ```bash
   oc logs deployment/keycloak -n keycloak | grep -i "smtp\|email\|mail"
   ```

---

## Useful Diagnostic Commands

```bash
# Check pod status
oc get pods -n keycloak

# Check ArgoCD sync status
oc get application keycloak -n openshift-gitops -o jsonpath='{.status.sync.status}'

# View Keycloak logs (last 100 lines)
oc logs deployment/keycloak -n keycloak --tail=100

# View PostgreSQL logs
oc logs deployment/postgresql -n keycloak --tail=100

# Check ExternalSecret sync
oc get externalsecret -n keycloak

# Check Route
oc get route -n keycloak

# Check endpoints (should show pod IPs)
oc get endpoints keycloak -n keycloak

# Describe pod for events
oc describe pod -l app=keycloak -n keycloak
```
