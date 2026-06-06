# Troubleshooting

## Dashboard Not Appearing

1. Verify the ConfigMap has the correct label:
   ```bash
   oc get configmap -n monitoring -l grafana_dashboard=1
   ```
2. Check the sidecar logs for errors:
   ```bash
   oc logs deployment/grafana -n monitoring -c grafana-sc-dashboard
   ```
3. Ensure the ConfigMap is in the `monitoring` namespace (sidecar only watches there)
4. If the ConfigMap is >262KB, add `ServerSideApply=true` to the ArgoCD app sync options

## OIDC Login Failures

1. Verify Keycloak is reachable from inside the cluster:
   ```bash
   oc exec deployment/grafana -n monitoring -- \
     curl -sk https://auth.208.haist.farm/realms/sentinel/.well-known/openid-configuration
   ```
2. Check the Grafana logs for OAuth errors:
   ```bash
   oc logs deployment/grafana -n monitoring -c grafana | grep -i oauth
   ```
3. Verify the `grafana-keycloak-secret` ExternalSecret is synced:
   ```bash
   oc get externalsecret -n monitoring
   ```

## Prometheus Datasource Errors

The Thanos Querier datasource uses a bearer token. If queries fail:

1. Check the token secret exists:
   ```bash
   oc get secret grafana-prometheus-token -n monitoring
   ```
2. Verify Thanos Querier is healthy:
   ```bash
   oc get pods -n openshift-monitoring -l app.kubernetes.io/name=thanos-query
   ```
3. Check for TLS certificate issues in Grafana logs

## UniFi Datasource Errors

The UniFi Prometheus runs on iac-control (192.168.12.210:9099). If it's unreachable:

1. OKD pods cannot reach the 192.168.12.0/24 management VLAN by default.
   Verify the firewall/routing allows monitoring traffic on port 9099.
2. Check if UniFi Prometheus is running on iac-control:
   ```bash
   ssh iac-control systemctl status prometheus-unifi
   ```

## Alerts Not Firing

1. Check unified alerting is enabled in `grafana.ini` (`unified_alerting.enabled: true`)
2. Verify the contact point webhook URL is reachable from the pod
3. Check alert rule evaluation in `Alerting > Alert rules` in the UI
4. Verify the sentinel-matrix-bot is running on iac-control:9095

## Pod Won't Start

1. Check events:
   ```bash
   oc describe pod -n monitoring -l app.kubernetes.io/name=grafana
   ```
2. Common issues:
   - Image pull failure: Verify `harbor.208.haist.farm/sentinel/grafana:12.4.0` exists
   - Secret missing: Check all ExternalSecrets are synced
   - Security context: OKD assigns UIDs — `runAsUser` must match the namespace range
