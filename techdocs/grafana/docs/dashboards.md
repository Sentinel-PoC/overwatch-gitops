# Dashboards

## Provisioning

Dashboards are provisioned via the Grafana sidecar, which watches ConfigMaps in
the `monitoring` namespace with the label `grafana_dashboard: "1"`. Each dashboard
is stored as inline JSON inside a ConfigMap.

**Important**: The cluster is air-gapped. Dashboard JSON must be inline — `gnetId`
imports fail silently because Grafana cannot reach grafana.com.

## Dashboard Inventory

| Dashboard | ConfigMap File | Focus |
|-----------|---------------|-------|
| Platform Overview | `platform-overview-dashboard.yaml` | Top-level health summary |
| Infrastructure | `infrastructure-dashboard.yaml` | Node/VM resource usage |
| Kubernetes Cluster | `kubernetes-cluster-dashboard.yaml` | Cluster-level K8s metrics |
| Kubernetes Pods | `kubernetes-pods-dashboard.yaml` | Per-pod resource metrics |
| Node Exporter | `node-exporter-dashboard.yaml` | Host-level system metrics |
| CoreDNS | `coredns-dashboard.yaml` | DNS query rates and errors |
| etcd | `etcd-dashboard.yaml` | etcd cluster health |
| Service Mesh | `service-mesh-dashboard.yaml` | Istio traffic and mTLS |
| GitOps Pipeline | `gitops-pipeline-dashboard.yaml` | CI/CD pipeline metrics |
| Security Posture | `security-posture-dashboard.yaml` | NIST compliance scores |
| Compliance Overview | `compliance-overview-dashboard.yaml` | Control family status |
| Wazuh Vulnerabilities | `wazuh-vulnerabilities-dashboard.yaml` | CVE counts by severity |
| CrowdSec | `crowdsec-dashboard.yaml` | IPS decisions and bans |
| UniFi Network | `unifi-network-dashboard.yaml` | Network device metrics |

All dashboard files are in `clusters/overwatch/apps/monitoring/grafana/dashboards/`.

## Adding a New Dashboard

1. Export or create the dashboard JSON
2. Create a ConfigMap YAML in `grafana/dashboards/`:
   ```yaml
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: my-dashboard
     namespace: monitoring
     labels:
       grafana_dashboard: "1"
   data:
     my-dashboard.json: |
       { ... inline JSON ... }
   ```
3. Commit and push — ArgoCD handles deployment

### Size Limits

ConfigMaps larger than 262KB require `ServerSideApply=true` in the ArgoCD sync
options. If a dashboard exceeds this, add to the ArgoCD app:

```yaml
syncOptions:
  - ServerSideApply=true
```

## Sidecar RBAC

The sidecar needs permission to list/watch ConfigMaps. RBAC is defined in
`grafana/dashboards/sidecar-rbac.yaml` with a ClusterRole and ClusterRoleBinding
scoped to the `monitoring` namespace.
