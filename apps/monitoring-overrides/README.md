# monitoring-overrides

ArgoCD-managed cluster-monitoring tweaks that live in `openshift-monitoring`.

## Contents

- `ovn-overflow-alert-relabel.yaml` — `AlertRelabelConfig` that drops the
  noisy `OVNKubernetesNodeOVSOverflowKernel` alert (see OPS-104).
- `prometheusrule-nfs-alerts.yaml` — `PrometheusRule` with three NFS health
  alerts evaluated by the cluster Prometheus against node_exporter data
  (see OPS-852): `NFSDeviceError` (critical, 2m), `NFSMountAvailZero`
  (warning, 5m), `NFSMountReadOnly` (warning, 5m).
- `argocd-rbac.yaml` — least-privilege Role+RoleBinding for ArgoCD to manage
  `AlertRelabelConfig` and `PrometheusRule` resources in this namespace
  (see OPS-212, OPS-852).

## Out-of-band prerequisite: namespace label

`openshift-monitoring` is **not** created or owned by this app — it ships with
OpenShift and is reconciled by the cluster-monitoring-operator. For ArgoCD's
cluster-scoped instance to watch it, the namespace must carry the label:

```
argocd.argoproj.io/managed-by=openshift-gitops
```

Apply it manually (the app cannot manage the namespace itself):

```bash
oc label ns openshift-monitoring argocd.argoproj.io/managed-by=openshift-gitops --overwrite
```

Without this label, the application reports `Sync=Unknown` with the condition:

```
ComparisonError: Failed to load live state: namespace "openshift-monitoring" ... is not managed
```

The label was applied on 2026-04-17 as part of OPS-212.

## Why this app carries its own RBAC file

Applying the `managed-by` label causes the openshift-gitops operator to
auto-create broad (`*/*/*`) Role/RoleBinding pairs named
`openshift-gitops-argocd-application-controller` and
`openshift-gitops-argocd-server` in the target namespace. Those grants
do not raise effective privilege — the application-controller SA is already
bound to `cluster-admin` cluster-wide via `ClusterRoleBinding/cluster-admin-0`.

The Role+RoleBinding defined in `argocd-rbac.yaml` are narrowly scoped to
`alertrelabelconfigs` and carry a different name so they coexist with the
operator-managed ones. They serve as the documented, least-privilege grant
this app actually needs — and they remain effective even if the operator's
auto-generated Role is ever disabled via
`.spec.defaultClusterScopedRoleDisabled=true` on the `ArgoCD` CR.
