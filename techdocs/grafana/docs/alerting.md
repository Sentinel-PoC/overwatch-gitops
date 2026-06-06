# Alerting

## Contact Points

| Name | Type | Target |
|------|------|--------|
| iac-control-webhook | Webhook (POST) | `http://192.168.12.210:9095/grafana` |

The webhook sends alerts to the sentinel-matrix-bot on iac-control, which forwards
them to the Matrix notification channel.

## Notification Policy

- **Default receiver**: iac-control-webhook
- **Group by**: `grafana_folder`, `alertname`
- **Group wait**: 30s
- **Group interval**: 5m
- **Repeat interval**: 4h

## Alert Rules

All rules are in the `Sentinel Infrastructure` group (folder: `Infrastructure Alerts`),
evaluated every 60s.

| Rule | UID | Condition | Severity | For |
|------|-----|-----------|----------|-----|
| High Node CPU Usage | `high-node-cpu` | CPU > 85% | warning | 5m |
| High Node Memory Usage | `high-node-memory` | Memory > 90% | warning | 5m |
| Wazuh Critical CVEs | `wazuh-critical-cves` | Critical CVE count > 0 | critical | 5m |
| Wazuh Exporter Down | `wazuh-exporter-down` | Last scrape > 900s ago | warning | 10m |
| Pod CrashLoopBackOff | `pod-crash-loop` | Restarts > 3/hour | critical | 10m |

## Adding Alert Rules

Add rules to the `alerting.rules.yaml.groups[0].rules` array in `values.yaml`.
Each rule needs:

- Unique `uid`
- `condition` referencing the threshold expression
- `data` array with query (refId A), reduce (refId B), and threshold (refId C) expressions
- `for` duration before firing
- `annotations.summary` for the notification message
- `labels.severity` (warning or critical)

## Silencing Alerts

Silences must be created through the Grafana UI (`Alerting > Silences`). They are
stored in Grafana's internal database, not in GitOps config.
