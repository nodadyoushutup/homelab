# Docker Swarm: nodes, labels, and constraints (quick guide)

> Run these on a Swarm **manager** node.

## Label strategy overview
- Keep labels lightweight (`key=value` strings) and scoped to scheduling needs. The default pattern here is `role=<node-name>` so constraints are explicit and stable.
- Apply labels to every node as part of provisioning so schedulers avoid "unknown" nodes. Record label intent next to any automation (Terraform, Ansible) that writes it.
- If you ever need functional grouping later, add a second label (for example, `tier=database`) without replacing the per-node `role`.
- Double-check that labels land in `.Spec.Labels`; `docker node update` writes there while container labels live elsewhere.

## Role labels in this swarm (per-node)

Use each node name as the `role` label value:

```text
role=swarm-cp-0
role=swarm-wk-0
role=swarm-wk-1
role=swarm-wk-2
role=swarm-wk-3
role=swarm-wk-4
```

### Example usage
```bash
docker node update --label-add role=swarm-wk-0 swarm-wk-0
docker node update --label-rm role swarm-wk-0
docker service create --name pinned-task --constraint 'node.labels.role==swarm-wk-0' alpine:3.20 sleep 1d
```

## Current homelab node map

| Node        | Swarm role | Availability | Labels           | Notes                                                  |
|-------------|------------|--------------|------------------|--------------------------------------------------------|
| `swarm-cp-0`| manager    | active       | `role=swarm-cp-0`| Controller/leader.                                     |
| `swarm-wk-0`| worker     | active       | `role=swarm-wk-0`| Worker.                                                |
| `swarm-wk-1`| worker     | active       | `role=swarm-wk-1`| Worker.                                                |
| `swarm-wk-2`| worker     | active       | `role=swarm-wk-2`| Worker.                                                |
| `swarm-wk-3`| worker     | active       | `role=swarm-wk-3`| Worker.                                                |
| `swarm-wk-4`| worker     | active       | `role=swarm-wk-4`| Worker.                                                |

> Keep this table updated as nodes change. The role label always matches the node name.

## Fast label commands for this cluster
```bash
# ensure existing labels stay present
docker node update --label-add role=swarm-cp-0 swarm-cp-0
docker node update --label-add role=swarm-wk-0 swarm-wk-0
docker node update --label-add role=swarm-wk-1 swarm-wk-1
docker node update --label-add role=swarm-wk-2 swarm-wk-2
docker node update --label-add role=swarm-wk-3 swarm-wk-3
docker node update --label-add role=swarm-wk-4 swarm-wk-4

# quick removals when shifting roles
docker node update --label-rm role swarm-cp-0
docker node update --label-rm role swarm-wk-0
docker node update --label-rm role swarm-wk-1
docker node update --label-rm role swarm-wk-2
docker node update --label-rm role swarm-wk-3
docker node update --label-rm role swarm-wk-4
```

## 1) See your Docker nodes
```bash
# list all nodes in the Swarm
docker node ls

# (optional) quick view with hostname + availability + labels
docker node ls --format 'table {{.ID}}	{{.Hostname}}	{{.Availability}}	{{.ManagerStatus}}'

# quick view with hostname + role label
docker node ls --format 'table {{.Hostname}}	{{.Labels}}'

# quick view with hostname + CPU architecture
docker node inspect -f '{{ .Description.Hostname }}	{{ .Description.Platform.Architecture }}' $(docker node ls -q)
```

## 2) See what labels a node has
```bash
# show labels for ONE node (replace NODE with ID or hostname from `docker node ls`)
docker node inspect NODE --format '{{ json .Spec.Labels }}'

# pretty-print labels (requires jq)
docker node inspect NODE | jq '.[0].Spec.Labels'

# full human-readable inspect (labels included near the top)
docker node inspect --pretty NODE
```

## 3) Add (or change) a label (e.g., role=swarm-wk-0)
```bash
# add/update label "role=swarm-wk-0" on a node
docker node update --label-add role=swarm-wk-0 NODE

# verify
docker node inspect NODE --format '{{ json .Spec.Labels }}'
```

> Notes:
> - Use `--label-rm key` to remove a label.
> - Labels live in `.Spec.Labels`, so updates are done with `docker node update`.

## 4) Use the label in placement constraints

### A) With `docker service create`
```bash
docker service create   --name pinned-task   --constraint 'node.labels.role==swarm-wk-0'   alpine:3.20 sleep 1d
```

### B) In a Compose/Stack file (`docker stack deploy`)
```yaml
# docker-compose.yml
services:
  pinned-task:
    image: alpine:3.20
    command: ["sleep","1d"]
    deploy:
      placement:
        constraints:
          - node.labels.role==swarm-wk-0
```
```bash
docker stack deploy -c docker-compose.yml mystack
```

### C) In code (array style), e.g. Pulumi/Terraform/SDKs
```json
{
  "deploy": {
    "placement": {
      "constraints": ["node.labels.role==swarm-wk-0"]
    }
  }
}
```

## 5) Confirm the constraint is working
```bash
# check where the task is scheduled
docker service ps pinned-task --no-trunc

# or for stacks
docker stack ps mystack --no-trunc
```
