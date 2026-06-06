# Langfuse ClickHouse Backup and Restore

**Applies to:** `langfuse-clickhouse` Deployment in `langfuse` namespace  
**Backup mechanism:** Native ClickHouse `BACKUP DATABASE ... TO Disk('backups', ...)` syntax  
**Backup storage:** NFS PVC `langfuse-ch-backup` mounted at `/var/lib/clickhouse/backups/` (TrueNAS `/mnt/DATA/backups/langfuse-clickhouse`)  
**Schedule:** CronJob `langfuse-ch-backup` runs daily at 02:30 UTC

---

## (a) Native CH BACKUP / RESTORE Syntax

ClickHouse native backup writes a self-contained zip to the configured disk. The backup disk `backups` is defined in `backup-disk.xml` (ConfigMap `langfuse-clickhouse-config`) and points to `/var/lib/clickhouse/backups/` which is backed by the NFS PVC.

### Create a manual backup

```bash
# exec into the clickhouse pod
POD=$(oc get pod -n langfuse -l app.kubernetes.io/name=clickhouse -o name | head -1)
oc exec -n langfuse $POD -- clickhouse-client \
  --user default \
  --password clickhouse-pass-change-me \
  --query "BACKUP DATABASE default TO Disk('backups', 'langfuse-ch-manual-$(date -u +%Y%m%dT%H%M%SZ).zip') SETTINGS async=false"
```

### List existing backups

```bash
oc exec -n langfuse $POD -- ls -lh /var/lib/clickhouse/backups/
```

### Restore from a backup (syntax reference)

```bash
BACKUP_FILE="langfuse-ch-20260425T023000Z.zip"
oc exec -n langfuse $POD -- clickhouse-client \
  --user default \
  --password clickhouse-pass-change-me \
  --query "RESTORE DATABASE default FROM Disk('backups', '${BACKUP_FILE}') SETTINGS allow_non_empty_tables=true"
```

`allow_non_empty_tables=true` is required if the target database already has tables (even empty ones). Use `RESTORE ... SETTINGS allow_non_empty_tables=true, restore_replace_existing=true` to overwrite existing data in-place.

---

## (b) Full Database Restore Procedure

Use this when the entire `default` database needs to be restored (e.g., after data loss).

```bash
BACKUP_FILE="langfuse-ch-20260425T023000Z.zip"
NAMESPACE="langfuse"

# 1. Scale Langfuse web and worker to 0 to stop writes
oc scale deployment langfuse-web   -n $NAMESPACE --replicas=0
oc scale deployment langfuse-worker -n $NAMESPACE --replicas=0

# Wait for pods to terminate
oc wait --for=delete pod -n $NAMESPACE -l app.kubernetes.io/component=web   --timeout=120s
oc wait --for=delete pod -n $NAMESPACE -l app.kubernetes.io/component=worker --timeout=120s

# 2. Drop and recreate the database in ClickHouse to ensure clean state
POD=$(oc get pod -n $NAMESPACE -l app.kubernetes.io/name=clickhouse -o name | head -1)
oc exec -n $NAMESPACE $POD -- clickhouse-client \
  --user default \
  --password clickhouse-pass-change-me \
  --query "DROP DATABASE IF EXISTS default SYNC"
oc exec -n $NAMESPACE $POD -- clickhouse-client \
  --user default \
  --password clickhouse-pass-change-me \
  --query "CREATE DATABASE default"

# 3. Restore from backup
oc exec -n $NAMESPACE $POD -- clickhouse-client \
  --user default \
  --password clickhouse-pass-change-me \
  --query "RESTORE DATABASE default FROM Disk('backups', '${BACKUP_FILE}') SETTINGS async=false"

# 4. Verify row counts match expected values
oc exec -n $NAMESPACE $POD -- clickhouse-client \
  --user default \
  --password clickhouse-pass-change-me \
  --query "SELECT table, count() as rows FROM system.tables WHERE database='default' AND engine NOT LIKE '%View%' ORDER BY table FORMAT Pretty"

# 5. Scale web and worker back up
oc scale deployment langfuse-web   -n $NAMESPACE --replicas=1
oc scale deployment langfuse-worker -n $NAMESPACE --replicas=1
```

Expected row counts after restore from 2026-04-25 recovery backup:
- `observations`: 7716
- `blob_storage_file_log`: 7882
- `traces`: 5
- `schema_migrations`: 68
- `project_environments`: 1

---

## (c) Partial Table Restore

To restore a single table without touching the rest of the database:

```bash
BACKUP_FILE="langfuse-ch-20260425T023000Z.zip"
TABLE="observations"
POD=$(oc get pod -n langfuse -l app.kubernetes.io/name=clickhouse -o name | head -1)

# Restore one table — existing data in that table will be merged
oc exec -n langfuse $POD -- clickhouse-client \
  --user default \
  --password clickhouse-pass-change-me \
  --query "RESTORE TABLE default.${TABLE} FROM Disk('backups', '${BACKUP_FILE}') SETTINGS async=false, allow_non_empty_tables=true"
```

If you need a clean restore of a single table (replace existing data):

```bash
oc exec -n langfuse $POD -- clickhouse-client \
  --user default \
  --password clickhouse-pass-change-me \
  --query "TRUNCATE TABLE default.${TABLE}"

oc exec -n langfuse $POD -- clickhouse-client \
  --user default \
  --password clickhouse-pass-change-me \
  --query "RESTORE TABLE default.${TABLE} FROM Disk('backups', '${BACKUP_FILE}') SETTINGS async=false"
```

---

## (d) Scratch-Pod Drill Procedure (Backup Integrity Verification)

Use this to verify a backup is restorable without touching the production ClickHouse instance.

```bash
BACKUP_FILE="langfuse-ch-20260425T023000Z.zip"
DRILL_NS="langfuse-restore-drill"

# 1. Create scratch namespace
oc new-project $DRILL_NS

# 2. Allow UID 101 to run in the drill namespace
oc adm policy add-scc-to-group anyuid system:serviceaccounts:$DRILL_NS

# 3. Deploy a scratch ClickHouse pod with the backup PVC mounted read-only
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: ch-drill
  namespace: $DRILL_NS
spec:
  restartPolicy: Never
  securityContext:
    runAsUser: 101
    runAsGroup: 101
    fsGroup: 101
  imagePullSecrets:
  - name: harbor-pull-secret
  containers:
  - name: clickhouse
    image: harbor.208.haist.farm/sentinel/clickhouse-server:25.8-alpine
    env:
    - name: CLICKHOUSE_USER
      value: default
    - name: CLICKHOUSE_PASSWORD
      value: clickhouse-pass-change-me
    volumeMounts:
    - name: backup
      mountPath: /var/lib/clickhouse/backups
      readOnly: true
  volumes:
  - name: backup
    persistentVolumeClaim:
      claimName: langfuse-ch-backup
      readOnly: true
EOF

# Wait for pod to be running
oc wait pod/ch-drill -n $DRILL_NS --for=condition=Ready --timeout=120s

# 4. Restore the backup into the scratch CH instance
oc exec -n $DRILL_NS ch-drill -- clickhouse-client \
  --user default \
  --password clickhouse-pass-change-me \
  --query "RESTORE DATABASE default FROM Disk('backups', '${BACKUP_FILE}') SETTINGS async=false"

# 5. Verify counts
oc exec -n $DRILL_NS ch-drill -- clickhouse-client \
  --user default \
  --password clickhouse-pass-change-me \
  --query "SELECT table, count() as rows FROM system.tables WHERE database='default' AND engine NOT LIKE '%View%' ORDER BY table FORMAT Pretty"

# 6. Clean up drill namespace
oc delete project $DRILL_NS
```

Accept the drill if `observations` returns 7716 and `blob_storage_file_log` returns 7882.

---

## (e) Appendix: 2026-04-25 Quarantine Drill Procedure

This documents the exact procedure used on 2026-04-25 to recover from the failed-tar data loss event. Recorded for audit purposes.

**Context:** On 2026-04-25, langfuse-clickhouse data directory was restored from a tar archive (`langfuse-ch-full-tree-20260424T101710Z.tar`, 7.5 GiB) captured while ClickHouse was still running. The tar captured parts mid-write, causing CH to crash on startup with `errno 20 ENOTDIR` while loading `system.text_log` part `202604_36091_36123_7`.

**Recovery procedure:**

```bash
POD=$(oc get pod -n langfuse -l app.kubernetes.io/name=clickhouse -o name | head -1)

# 1. Scale Langfuse web and worker to 0
oc scale deployment langfuse-web   -n langfuse --replicas=0
oc scale deployment langfuse-worker -n langfuse --replicas=0

# 2. Scale ClickHouse to 0
oc scale deployment langfuse-clickhouse -n langfuse --replicas=0

# 3. Start a restore pod with the data PVC mounted as the correct UID
#    This mounts langfuse-clickhouse-data (the iSCSI PVC, not the NFS backup PVC)
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: ch-restore
  namespace: langfuse
spec:
  restartPolicy: Never
  securityContext:
    runAsUser: 101
    runAsGroup: 101
    fsGroup: 101
  imagePullSecrets:
  - name: harbor-pull-secret
  containers:
  - name: restore
    image: harbor.208.haist.farm/sentinel/alpine:3.20
    command: ["sleep", "7200"]
    volumeMounts:
    - name: data
      mountPath: /var/lib/clickhouse
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: langfuse-clickhouse-data
EOF

oc wait pod/ch-restore -n langfuse --for=condition=Ready --timeout=120s

# 4. Clear the existing data directory (wipe broken data)
oc exec -n langfuse ch-restore -- find /var/lib/clickhouse -mindepth 1 -depth -delete

# 5. Copy the tar into the pod and extract
oc cp /home/koiakoia/plane-recovery-backup/langfuse-ch-full-tree-20260424T101710Z.tar \
  langfuse/ch-restore:/tmp/ch-backup.tar

oc exec -n langfuse ch-restore -- tar -xf /tmp/ch-backup.tar -C /var/lib/clickhouse

# 6. Move broken system table UUIDs to quarantine
#    (19 system table directories: text_log, query_log, metric_log, trace_log,
#     processors_profile_log, etc.)
oc exec -n langfuse ch-restore -- mkdir -p /var/lib/clickhouse/_quarantine
# Move each broken UUID — example for text_log:
# oc exec -n langfuse ch-restore -- mv /var/lib/clickhouse/data/<UUID> /var/lib/clickhouse/_quarantine/

# 7. Delete the restore pod and scale ClickHouse back up
oc delete pod ch-restore -n langfuse
oc scale deployment langfuse-clickhouse -n langfuse --replicas=1

# Wait for CH to start
oc wait pod -n langfuse -l app.kubernetes.io/name=clickhouse --for=condition=Ready --timeout=300s

# 8. Verify recovery
POD=$(oc get pod -n langfuse -l app.kubernetes.io/name=clickhouse -o name | head -1)
oc exec -n langfuse $POD -- clickhouse-client \
  --user default \
  --password clickhouse-pass-change-me \
  --query "SELECT table, count() as rows FROM system.tables WHERE database='default' ORDER BY table FORMAT Pretty"

# 9. Scale web and worker back up
oc scale deployment langfuse-web   -n langfuse --replicas=1
oc scale deployment langfuse-worker -n langfuse --replicas=1
```

**Result of 2026-04-25 drill:** 15,672 rows recovered. 16 parts remained in `detached/` (broken-on-start or covered-by-broken from mid-write capture; ATTACH attempts all failed). These are scheduled for cleanup in OPS-111-B after 48h stability gate.

**Lesson:** ClickHouse cannot be safely tar-backed up while running. Always use `BACKUP DATABASE default TO Disk(...)` (native backup) or scale to 0 before capturing the data directory.
