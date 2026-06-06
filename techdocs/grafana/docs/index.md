# Grafana Observability Platform

## Service Identity

| Property | Value |
|----------|-------|
| **URL** | `https://grafana.208.haist.farm` |
| **Namespace** | `monitoring` |
| **Version** | Grafana 12.4.0 (Helm chart 10.5.15) |
| **Image** | `harbor.208.haist.farm/sentinel/grafana:12.4.0` |
| **ArgoCD App** | `grafana` |
| **Auth** | Keycloak OIDC (realm `sentinel`, client `grafana`) |

## Architecture

Grafana runs as a single-pod Helm deployment in the `monitoring` namespace on the
OKD cluster. It connects to two Prometheus datasources and one Jaeger datasource
for metrics and tracing. Dashboards are provisioned via a sidecar that watches
ConfigMaps with the `grafana_dashboard: "1"` label.

```
                Keycloak OIDC
                     |
   [OKD Route] ------+-----> [Grafana Pod :3000]
   grafana.208.haist.farm        |
                           +-----+-----+----------+
                           |           |           |
                   [Thanos Querier] [UniFi Prom] [Jaeger]
                   (OKD built-in)  (iac-control)  (OKD)
```

## Key Facts

- **14 dashboards** provisioned via sidecar ConfigMaps (inline JSON, no gnetId)
- **3 datasources**: Thanos Querier (OKD Prometheus), UniFi Prometheus (iac-control:9099), Jaeger
- **SSO**: Keycloak group-to-role mapping (admin=Admin, operator=Editor, viewer=Viewer)
- **Secrets**: Admin credentials and OAuth client secret from Vault via ESO
- **Alerting**: 5 alert rules with webhook contact point to iac-control:9095
- **Air-gapped**: All images from Harbor; no external dashboard imports (gnetId fails silently)
