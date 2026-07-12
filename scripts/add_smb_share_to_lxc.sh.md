# add_smb_share_to_lxc.sh

## What it does

Automates the full process of mounting a CIFS/SMB network share (e.g. from a NAS) on a **Proxmox host** and exposing it as a bind-mount inside one or more LXC containers — with proper permission mapping so the share is actually usable inside the container.

## Why it exists

Mounting a NAS share into an LXC sounds straightforward. In practice there are at least five moving parts that all have to align:

1. **UID/GID mapping** — Proxmox LXCs use a UID offset (`100000`). A file owned by `uid=100000` on the host appears as `uid=0` (root) inside the container. Get this wrong and your share is read-only or flat-out inaccessible.
2. **Group setup inside the LXC** — the container needs a matching group (`lxc_shares`, GID 10000) and root added to it, or permission checks fail.
3. **fstab with the right CIFS options** — `_netdev` and `x-systemd.automount` ensure the mount survives reboots and doesn't block boot if the NAS is temporarily unreachable.
4. **Shared mount flag** — the `shared=1` in the LXC config tells Proxmox this mount point is shared across containers, which is required for multi-LXC setups.
5. **Teardown order** — unmounting without first stopping dependent LXCs causes kernel-level mount lock issues. The script reminds you of the right order.

This script handles steps 2–5 automatically and walks you through step 1.

## How it works

### LXC-side (manual — run inside the container once)
```bash
groupadd -g 10000 lxc_shares
usermod -aG lxc_shares root
```
This creates a group with a fixed GID that maps correctly to the host-side mount permissions.

### Host-side (automated by this script)
1. **Creates the mount point** at `/mnt/lxc_shares/nas_rwx` (or your configured path)
2. **Adds an fstab entry** with correct CIFS options — idempotent, won't duplicate
3. **Reloads systemd** and mounts the share immediately
4. **Appends a bind-mount** to the target LXC's `/etc/pve/lxc/<ID>.conf` with `shared=1`

### The UID/GID magic

```
uid=100000,gid=110000,dir_mode=0770,file_mode=0770
```

- `uid=100000` → maps to `root` (uid 0) inside the LXC
- `gid=110000` → maps to the `lxc_shares` group (gid 10000) inside the LXC
- `0770` permissions → owner + group have full access, others locked out

This means files on the share are owned by root:lxc_shares inside the container with full rwx.

## Prerequisites

- Proxmox host with `pct` and standard LXC tooling
- NAS accessible over the network with a CIFS share configured
- `cifs-utils` installed on the Proxmox host (`apt install cifs-utils`)
- Target LXC with group setup completed (see above)

## Configuration

Edit the top of the script:

```bash
NAS_HOST="192.168.50.129"          # NAS IP or hostname
NAS_SHARE="shared"                 # SMB share name
SMB_USER="admin"                   # SMB username
SMB_PASS="changeme"                # SMB password
HOST_MOUNT="/mnt/lxc_shares/nas_rwx"  # Host-side mount point
LXC_MOUNT="/mnt/nas"               # Path inside the container
LXC_ID=""                          # LXC ID to configure (blank = skip)
```

## Usage

Run on the **Proxmox host**:

```bash
chmod +x add_smb_share_to_lxc.sh
./add_smb_share_to_lxc.sh
```

The script will confirm you've done the LXC-side group setup before proceeding.

## Removing the mount

The script prints teardown instructions on completion. In brief:

1. Shut down all LXCs/VMs using the mount
2. `umount /mnt/lxc_shares/nas_rwx`
3. Remove the entry from `/etc/fstab`
4. `systemctl daemon-reload`
5. Remove the `mp` line from `/etc/pve/lxc/<ID>.conf`

⚠️ **Always stop dependent containers before unmounting.** Unmounting a live bind-mount causes stale mounts inside the container that require a full reboot to recover from.
