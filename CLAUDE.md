# CLAUDE.md — overwatch-gitops

This repo (ArgoCD-managed apps for the Overwatch platform) **does not**
carry its own agent-operating framework. The authoritative framework
lives in [`sentinel-iac/CLAUDE.md`](https://forgejo.208.haist.farm/sentinel-admin/sentinel-iac/src/branch/main/CLAUDE.md).

**Why this file is a stub (not a symlink to sentinel-iac):**
ArgoCD's `repo-server` refuses to render manifests from a repository
that contains out-of-bounds symlinks. The previous `CLAUDE.md ->
../../sentinel-iac/CLAUDE.md` symlink caused all 26 non-nfs/non-manual
apps to show `sync.status=Unknown` in `oc get applications -n
openshift-gitops` — the repo-server errored before it could compute
sync state. Replacing the symlink with this plain file restores sync
visibility across the fleet.

**If you are an agent acting in this repo:** read the sentinel-iac
CLAUDE.md first. Everything in it applies here.

**If sentinel-iac CLAUDE.md changes:** post a `PLAN` note on a HAIST
issue before mirroring any relevant passage into this stub. Most of
the framework does not need mirroring — it's operator governance, not
file-scoped per-repo rules. Only mirror the sections that an agent
working in *this* repo specifically needs inline.
