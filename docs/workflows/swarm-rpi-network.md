# Swarm Raspberry Pi network and NFS

Swarm **aarch64** nodes (`swarm-cp-0`, `swarm-wk-0` … `swarm-wk-4`) use **Ethernet only** (`eth0`). Wi‑Fi must stay off so a second default route cannot steal traffic from `eth0`.

Static `eth0` addresses: `swarm-cp-0` → `192.168.1.120`, `swarm-wk-0` … `swarm-wk-4` → `192.168.1.121`–`125`. Live netplan is on each host at `/etc/netplan/50-cloud-init.yaml`.

## SSH

Use the **`eth0` address** (e.g. `192.168.1.122` for `swarm-wk-1`) if `*.local` still resolves to a removed Wi‑Fi address.

## Docker Swarm NFS volumes

Host fstab is separate from Swarm stack NFS local volumes. After changing host mounts, update `nfs.driver_options.o` in `<homelab>/.config/terraform/providers/nfs.tfvars` (see `terraform/providers/nfs.tfvars.example`), then re-apply stacks that mount NFS.
