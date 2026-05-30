# Swarm Raspberry Pi network and NFS

Swarm **aarch64** nodes (`swarm-cp-0`, `swarm-wk-0` … `swarm-wk-4`) use **Ethernet only** (`eth0`). Wi‑Fi must stay off so a second default route cannot steal traffic from `eth0`.

Static `eth0` addresses: `swarm-cp-0` → `192.168.1.120`, `swarm-wk-0` … `swarm-wk-4` → `192.168.1.121`–`125`. Live netplan is on each host at `/etc/netplan/50-cloud-init.yaml`.

## SSH

Use the **`eth0` address** (e.g. `192.168.1.122` for `swarm-wk-1`) if `*.local` still resolves to a removed Wi‑Fi address.

## Boot time sync and Docker Swarm (every node)

Power loss or **pulling the plug** leaves Pis with a **dead RTC** (clock at
1970). Shutdown hooks never run, so time must be restored from **fake-hwclock**
(periodic saves while running) and **plain UDP NTP** on boot. **Docker starts
before chrony finishes NTP sync** without the guard, validates Swarm TLS with
the wrong time, and stays in `Swarm=error` even after the system clock is
correct.

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
sudo <repo>/scripts/install/swarm_pi_clock_bootstrap.sh
```

Or from an operator workstation (all six Pis):

```bash
<repo>/scripts/swarm/apply_swarm_pi_clock_bootstrap_all.sh
```

That script installs:

1. **fake-hwclock** with **5-minute periodic save** and **save-after-chrony-sync**
   on every boot — required because homelab Pis are normally powered off by
   **pulling the plug** (no clean shutdown, dead RTC battery).
2. **Plain UDP NTP bootstrap sources** (`192.168.1.1`, Cloudflare, pool.ntp.org)
   in `/etc/chrony/sources.d/00-homelab-bootstrap.sources` — sync works before
   NTS TLS certificates validate on a wildly wrong clock.
3. **`makestep 1 -1`** — always step large offsets after power loss.
4. **`docker_swarm_time_sync_guard.sh`** drop-ins — Docker waits for
   `chrony-wait.service` before starting Swarm.

After a guarded boot with the bootstrap sources installed, chrony should sync
within seconds and Docker starts once time is valid.

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
3. **`swarm_pi_clock_bootstrap.sh`** on that host before relying on it
   across the next power cycle (includes the Docker time-sync guard).
4. Label `role=swarm-wk-N` on the manager.

## Docker Swarm NFS volumes

Host fstab is separate from Swarm stack NFS local volumes. After changing host mounts, update `nfs.driver_options.o` in `<homelab>/.config/terraform/components/swarm/nfs.tfvars` (see `terraform/components/swarm/nfs.tfvars.example`), then re-apply stacks that mount NFS.
