# Compliance

## NIST 800-53 Control Mapping

Grafana supports the following NIST 800-53 controls as part of the Sentinel Platform:

| Control | Title | How Grafana Supports It |
|---------|-------|------------------------|
| AU-6 | Audit Record Review | Security dashboards visualize Wazuh alerts, vulnerability trends, and compliance scores |
| AU-7 | Audit Reduction | Dashboards aggregate and filter audit data from Prometheus metrics |
| CA-7 | Continuous Monitoring | 14 dashboards provide real-time visibility into infrastructure, security, and compliance |
| IR-4 | Incident Handling | Alert rules detect anomalies (CPU, memory, CVEs, crash loops) and notify via Matrix |
| SI-4 | System Monitoring | Platform Overview and Infrastructure dashboards track system health metrics |
| SI-4(5) | System-Generated Alerts | 5 alert rules with automated webhook notifications |

## Security Controls

| Control | Implementation |
|---------|---------------|
| **Authentication** | Keycloak OIDC — no anonymous access, local login available as fallback |
| **Authorization** | Group-based RBAC: admin=Admin, operator=Editor, viewer=Viewer |
| **Secrets** | All credentials from Vault via ESO — no plaintext in config |
| **Network** | TLS reencrypt via OKD Route, internal-only access |
| **Container Security** | Non-root, no privilege escalation, all capabilities dropped, seccomp enforced |
| **Image Provenance** | Images from Harbor with Kyverno cosign verification |
| **GitOps** | All config in version control, ArgoCD-managed, UI changes reverted |

## Compliance Dashboards

Two dashboards directly support compliance monitoring:

- **Security Posture Dashboard**: NIST compliance check results, pass/fail/warn counts,
  control family coverage, trend over time
- **Compliance Overview Dashboard**: Control implementation status, gap analysis metrics
