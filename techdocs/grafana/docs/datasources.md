# Datasources

## Configured Datasources

All datasources are provisioned via `values.yaml` — not created through the UI.

### Prometheus (Thanos Querier)

| Property | Value |
|----------|-------|
| **Name** | Prometheus |
| **Type** | prometheus |
| **URL** | `https://thanos-querier.openshift-monitoring.svc:9091` |
| **Default** | Yes |
| **Auth** | Bearer token from `grafana-prometheus-token` secret |
| **Scrape interval** | 30s |

This is the OKD built-in Thanos Querier that aggregates all cluster Prometheus
metrics. The bearer token is a ServiceAccount token with monitoring read access.

### UniFi Prometheus

| Property | Value |
|----------|-------|
| **Name** | UniFi Prometheus |
| **Type** | prometheus |
| **URL** | `http://192.168.12.210:9099` |
| **Default** | No |
| **Auth** | None (internal network) |
| **Scrape interval** | 30s |

Standalone Prometheus on iac-control that scrapes the UniFi exporter (:9120).
Provides network device metrics (clients, throughput, device health).

### Jaeger

| Property | Value |
|----------|-------|
| **Name** | Jaeger |
| **Type** | jaeger |
| **URL** | `http://jaeger-query-http.observability.svc.cluster.local:16686` |
| **Default** | No |
| **Features** | Node graph enabled |

Provides distributed tracing for Istio service mesh traffic.

## Adding a Datasource

Add to the `datasources.datasources.yaml.datasources` array in `values.yaml`:

```yaml
- name: My New Source
  type: prometheus
  url: http://service.namespace.svc:9090
  access: proxy
  isDefault: false
```

Commit and merge — ArgoCD will sync the updated Helm values.
