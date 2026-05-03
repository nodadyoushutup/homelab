# Proxmox Development VM SSH Investigation (Temporary)

This is a temporary investigation plan for the `development` VM under
`terraform/cluster/proxmox/app`. The immediate goal is to unblock SSH access
and Docker Swarm onboarding for the AMD64 development VM. The follow-up goal is
to identify why freshly deployed images can boot into a broken SSH/package
state.

## Current Status

- Immediate priority: restore working SSH on the current `development` VM so it
  can be used for debugging and Docker Swarm worker onboarding.
- Deferred priority: root-cause why newly deployed VMs repeatedly boot with
  broken SSH even though the Terraform cloud-init config includes the expected
  user key.

## Repo-Backed Facts

- The Proxmox `development` VM is created from the custom Ubuntu image and is
  wired to custom cloud-init user and network data in
  [terraform/cluster/proxmox/app/main.tf](../../terraform/cluster/proxmox/app/main.tf:311)
  and
  [terraform/cluster/proxmox/app/main.tf](../../terraform/cluster/proxmox/app/main.tf:346).
- The base Packer build uses SSH as its communicator, which proves SSH works at
  least during image build time in
  [packer/ubuntu-24.04-ndysu.pkr.hcl](../../packer/ubuntu-24.04-ndysu.pkr.hcl:49)
  and
  [packer/ubuntu-24.04-ndysu.pkr.hcl](../../packer/ubuntu-24.04-ndysu.pkr.hcl:68).
- The base Packer cloud-init disables SSH password auth in
  [packer/cloud-init/user-data](../../packer/cloud-init/user-data:23), so
  console password login does not imply SSH password login will work.
- The image cleanup step removes `nodadyoushutup`'s baked
  `authorized_keys`, so first-boot cloud-init is responsible for restoring SSH
  key access in
  [packer/scripts/cleanup-image.sh](../../packer/scripts/cleanup-image.sh:12).
- The Proxmox tfvars cloud-init payload for the `development` VM includes the
  expected `ssh_authorized_keys` entry and a Docker Swarm join script in
  `/mnt/eapp/config/proxmox/development-user-config.yaml`.

## Runtime Evidence Collected

- SSH from the operator host to `192.168.1.101:22` failed before auth with
  `Connection refused`.
- `systemctl status ssh` on the guest showed `ExecStartPre=/usr/sbin/sshd -t`
  failing.
- `/usr/sbin/sshd` was missing on the guest even though `dpkg -l` reported
  `openssh-server` as installed.
- `dpkg --audit` also reported a broken package database entry for `xorriso`
  because its md5sums control file was missing.
- `swarm-cp-0` is listening on `192.168.1.120:2377`, but its Swarm metadata is
  still advertising the stale manager address `192.168.1.26:2377`, which
  prevents new nodes from joining and likely explains why all existing workers
  are currently `Down`.

## Working Conclusion

This is not primarily an SSH key injection problem.

The stronger current hypothesis is that the deployed VM image is reaching the
guest with a broken package/filesystem state:

- package metadata claims some packages are installed
- required files for those packages are missing on disk
- at least one unrelated package (`xorriso`) also shows package metadata drift

That points more toward image integrity or guest filesystem/package corruption
than a simple cloud-init misconfiguration.

## Immediate Unblock

1. Repair SSH on the current `development` VM manually so debugging and Swarm
   onboarding can continue.
2. Confirm the VM can accept SSH from the operator host.
3. Join the VM to the Docker Swarm controlled by `swarm-cp-0.local`.
4. Deploy the AMD64 GitHub Actions runner only after SSH and Swarm membership
   are both stable.

### Recovery Performed

- The `development` VM was joined successfully by targeting the live manager
  listener at `192.168.1.120:2377`.
- The `development` VM also needed the shared NFS-backed
  `/mnt/eapp/config` mount from `192.168.1.100:/mnt/eapp/config` before
  Swarm workloads that bind-mount repo configuration could start successfully.
- After a Docker daemon restart, the `development` worker kept trying the stale
  manager address `192.168.1.26:2377`; recovery required forcing the worker to
  leave and rejoin the swarm against `192.168.1.120:2377`.
- Existing workers `swarm-wk-0` through `swarm-wk-4` were recovered by:
  1. removing their stale node records from the manager
  2. restarting Docker after moving aside stale local Swarm state
  3. forcing the node to leave any lingering membership
  4. rejoining the swarm against `192.168.1.120:2377`
- After recovery, all workers returned to `Ready`, but the manager metadata
  still advertises `192.168.1.26:2377`, so the cluster still needs a proper
  manager-address remediation.

## Deferred Investigation Plan

1. Reproduce the issue on a fresh VM from the same published image version and
   record package/file integrity immediately after first boot.
2. Verify whether `/usr/sbin/sshd` and `/var/lib/dpkg/info/*` are already
   missing before any manual repair or extra package installs.
3. Compare a broken deployed VM against the original built artifact to decide
   whether corruption is introduced during:
   - Packer build finalization
   - artifact upload/download
   - Proxmox import/clone
   - first boot / cloud-init
4. Inspect the built qcow2 artifact offline, if needed, to verify whether
   `openssh-server` files and `dpkg` metadata are present before Proxmox
   deployment.
5. Review the Packer cleanup/finalization steps for anything that could leave
   package contents or `dpkg` metadata inconsistent, even if it is not
   obviously SSH-related.
6. Add a post-build image validation step that fails the image pipeline unless
   all of the following are true:
   - `dpkg --audit` is clean
   - `/usr/sbin/sshd` exists
   - `systemctl start ssh` succeeds in the built image
   - a smoke-deployed VM accepts SSH on port `22`

## Questions To Answer Later

- Is the published `0.0.2` AMD64 image itself broken before Proxmox ever uses
  it?
- Is package metadata drift happening inside the guest filesystem after import?
- Is cloud-init or first-boot automation indirectly damaging package state?
- Do other binaries besides `sshd` and `xorriso` show the same missing-file
  pattern?
- Why does the current Swarm manager still advertise `192.168.1.26` after the
  host moved to `192.168.1.120`, and what is the safest permanent remediation?

## Exit Criteria

This temporary plan is complete when:

1. a freshly deployed `development` VM accepts SSH without manual repair
2. `dpkg --audit` is clean on first boot
3. `/usr/sbin/sshd` exists and `ssh.service` starts normally
4. the VM can auto-join or be safely joined to the Docker Swarm
5. the image build or deployment path is updated so this failure is prevented
   for future VM deployments
