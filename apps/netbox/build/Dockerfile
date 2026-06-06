# OPS-692: NetBox with netbox-acls plugin pre-installed.
#
# Base: Harbor-mirrored upstream netbox:v4.6.1 (supply-chain integrity;
#   same tag pinned in clusters/overwatch/apps/netbox/values.yaml).
#
# Plugin: netbox-acls==2.0.1
#   Compatibility verified:
#     - Django 5.2 classifier matches NetBox v4.6.1 runtime (verified compatible)
#     - Python 3.12 classifier matches NetBox v4.6.1 container Python
#   Source: https://pypi.org/project/netbox-acls/2.0.1/
#
# Output image: harbor.208.haist.farm/sentinel/netbox-with-acls:v4.6.1-acls2.0.1
#   Tag encodes both the NetBox base version and the plugin version
#   for clear traceability.
# OPS-865: bumped base image from v4.5.3 -> v4.6.1 (CVE-2026-29514 ExportTemplate RCE)
# IMPORTANT: 4.5->4.6 runs Django DB migrations on first deploy.
#            Operator must take a DB backup before deploying.
FROM harbor.208.haist.farm/sentinel/netbox:v4.6.1

# Use uv (not pip or python3 -m pip): netbox:v4.6.1 venv is managed by uv without --seed,
# so pip is absent as both a binary AND a module.
# Confirmed from task 11719 log: "/opt/netbox/venv/bin/python3: No module named pip"
# Upstream netbox-docker Dockerfile uses: /usr/local/bin/uv pip install -r /requirements.txt
# uv is present in the final image at /usr/local/bin/uv; VIRTUAL_ENV=/opt/netbox/venv is set.
# UV_NO_CACHE=1 is already set in the base image ENV (equivalent to --no-cache-dir).
RUN uv pip install netbox-acls==2.0.1
