# Swarm Raspberry Pi network and NFS

Swarm **aarch64** nodes (`swarm-cp-0`, `swarm-wk-0` … `swarm-wk-4`) use **Ethernet only** (`eth0`). Wi‑Fi must stay off so a second default route cannot steal traffic from `eth0`.

Static `eth0` addresses: `swarm-cp-0` → `192.168.1.120`, `swarm-wk-0` … `swarm-wk-4` → `192.168.1.121`–`125`. Live netplan is on each host at `/etc/netplan/50-cloud-init.yaml`.

## SSH

Use the **`eth0` address** (e.g. `192.168.1.122` for `swarm-wk-1`) if `*.local` still resolves to a removed Wi‑Fi address.

## Boot time sync and Docker Swarm (every node)

Power loss or a cold boot can leave Pis with a **stale RTC** (clock weeks or
months behind). **Docker starts before chrony finishes NTP sync**, validates
Swarm TLS with the wrong time, and stays in `Swarm=error` even after the system
clock is correct. The manager may keep running if it already had the guard; workers
without it show **Down** in `docker node ls` and constrained services sit at
**Pending** (the age in `docker service ps` is *scheduler wait time*, not proof
the host or container was up that long).

### Symptoms

- Workers are **pingable** on `eth0` (`192.168.1.121`–`125`) but Swarm shows
  **Down**.
- On the worker: `docker info` reports something like:

  ```text
  Swarm: error
  error while validating Root CA Certificate: x509: certificate has expired or is not yet valid:
    current time 2026-03-13T... is before 2026-05-23T14:30:00Z
  ```

  (`date` on the host may already show the correct time — Docker was started too
  early and was not restarted after sync.)
- Manager: `docker service ps <svc>` → `no suitable node (N nodes not available
  for new tasks; scheduling constraints not satisfied on 1 node)`.

### Permanent fix (required on manager **and** every worker)

Run once per Swarm node (including new workers after join):

```bash
sudo <repo>/scripts/install/docker_swarm_time_sync_guard.sh
```

From an operator workstation with SSH to each host:

```bash
REPO=/mnt/eapp/code/homelab   # adjust
for ip in 120 121 122 123 124 125; do
  scp "${REPO}/scripts/install/docker_swarm_time_sync_guard.sh" \
    "nodadyoushutup@192.168.1.${ip}:/tmp/"
  ssh "nodadyoushutup@192.168.1.${ip}" \
    'chmod +x /tmp/docker_swarm_time_sync_guard.sh && sudo /tmp/docker_swarm_time_sync_guard.sh'
done
```

The script:

1. Writes `chrony-wait.service.d/10-no-timeout.conf` (wait until sync, no start timeout).
2. Writes `docker.service.d/10-wait-for-time-sync.conf` (`After=` / `Requires=`
   `chrony-wait.service`).
3. Enables `chrony-wait.service` and restarts Docker (use `--no-restart` to only
   install drop-ins).

After a guarded boot, Docker should not start until chrony has synchronized time.

### Verify guard is installed

On each node:

```bash
test -f /etc/systemd/system/docker.service.d/10-wait-for-time-sync.conf && echo OK
systemctl is-enabled chrony-wait.service
docker info --format 'Swarm={{.Swarm.LocalNodeState}}'
```

Expect `chrony-wait` **enabled**, drop-in **present**, and `Swarm=active` on
joined nodes.

### Break-glass recovery (guard missing or first boot after outage)

If workers are pingable but still **Down** and `docker info` shows the TLS /
`current time … is before …` error:

```bash
# on each affected worker, after timedatectl shows synchronized: yes
sudo systemctl restart docker.service
```

On the manager: `docker node ls` — all workers should return to **Ready**;
services reschedule automatically.

### New worker checklist

When joining `swarm-wk-N` to the cluster:

1. Static `eth0` and Wi‑Fi off (above).
2. `docker swarm join` (see `scripts/swarm/prepare_swarm_wk4_ai_node.sh` or
   `scripts/swarm/ensure_swarm_worker_node.sh`).
3. **`docker_swarm_time_sync_guard.sh`** on that host before relying on it
   across the next power cycle.
4. Label `role=swarm-wk-N` on the manager.

## Docker Swarm NFS volumes

Host fstab is separate from Swarm stack NFS local volumes. After changing host mounts, update `nfs.driver_options.o` in `<homelab>/.config/terraform/components/swarm/nfs.tfvars` (see `terraform/components/swarm/nfs.tfvars.example`), then re-apply stacks that mount NFS.
