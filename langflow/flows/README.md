# Langflow Flow Snapshots

This directory stores exported JSON snapshots of the live Homelab Langflow
flows.

Current files:

- `homelab-user.json`: the Homelab flow in the `langflow` user's `Homelab`
  folder
- `homelab-admin.json`: the Homelab flow in the admin-side project folder used
  by local MCP tooling

These snapshots are source-of-truth artifacts for review and drift detection,
but they are not yet loaded automatically on Langflow startup.

To refresh both live flows and rewrite these snapshots after a prompt/tooling
change, run:

```bash
python3 scripts/misc/fix_langflow_homelab_flows.py --apply-live --write-snapshots
```
