#!/bin/bash

# ==============================================================================
#  add_smb_share_to_lxc.sh
#  Mount a CIFS/SMB share on the Proxmox host and bind-mount it into LXC(s)
#
#  Run this script on the Proxmox HOST (not inside a container).
#  The LXC-side group setup must be done manually inside the container first.
# ==============================================================================

# --- CONFIGURATION ---
NAS_HOST="192.168.50.129"         # NAS IP or hostname
NAS_SHARE="shared"                # Share name on the NAS
SMB_USER="admin"                  # SMB username
SMB_PASS="changeme"               # SMB password
HOST_MOUNT="/mnt/lxc_shares/nas_rwx"  # Where to mount it on the host
LXC_MOUNT="/mnt/nas"              # Where it appears inside the LXC
LXC_ID=""                         # LXC container ID to expose the share to
                                  # Leave blank to skip LXC config step
# --- CONFIGURATION END ---

set -e

echo "=================================================="
echo "  SMB Share → LXC Mount Setup Tool               "
echo "=================================================="

# ---- STEP 1: LXC-SIDE (reminder — must be done manually inside the container)
echo ""
echo "[INFO] Before running this script, ensure the following was run INSIDE the LXC:"
echo "  groupadd -g 10000 lxc_shares"
echo "  usermod -aG lxc_shares root"
echo ""
read -p "[?] Have you completed the LXC-side group setup? (y/N): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "[-] Aborting. Run the group setup inside the LXC first."
    exit 1
fi

# ---- STEP 2: Create host mount point
echo "[*] Creating host mount directory: ${HOST_MOUNT}"
mkdir -p "$HOST_MOUNT"

# ---- STEP 3: Add fstab entry if not already present
FSTAB_ENTRY="//${NAS_HOST}/${NAS_SHARE} ${HOST_MOUNT} cifs _netdev,x-systemd.automount,noatime,uid=100000,gid=110000,dir_mode=0770,file_mode=0770,user=${SMB_USER},pass=${SMB_PASS} 0 0"

if grep -qF "$HOST_MOUNT" /etc/fstab; then
    echo "[~] fstab entry already exists for ${HOST_MOUNT}, skipping."
else
    echo "" >> /etc/fstab
    echo "# Mount CIFS share on demand with rwx permissions for use in LXCs" >> /etc/fstab
    echo "$FSTAB_ENTRY" >> /etc/fstab
    echo "[+] fstab entry added."
fi

# ---- STEP 4: Reload systemd and mount
echo "[*] Reloading systemd daemon..."
systemctl daemon-reload

echo "[*] Mounting ${HOST_MOUNT}..."
mount "$HOST_MOUNT"
echo "[+] Share mounted successfully."

# ---- STEP 5: Add bind-mount to LXC config (optional)
if [ -n "$LXC_ID" ]; then
    LXC_CONF="/etc/pve/lxc/${LXC_ID}.conf"
    if [ ! -f "$LXC_CONF" ]; then
        echo "[-] LXC config not found at ${LXC_CONF}. Skipping LXC bind-mount step."
    else
        MP_ENTRY="mp0: ${HOST_MOUNT}/,mp=${LXC_MOUNT},shared=1"
        if grep -qF "$HOST_MOUNT" "$LXC_CONF"; then
            echo "[~] LXC ${LXC_ID} already has a mount point for ${HOST_MOUNT}, skipping."
        else
            echo "$MP_ENTRY" >> "$LXC_CONF"
            echo "[+] Added bind-mount to LXC ${LXC_ID} config."
            echo "[!] Restart LXC ${LXC_ID} for the mount to take effect."
        fi
    fi
else
    echo "[~] No LXC_ID set. Skipping LXC config step."
    echo "    To add manually, append to /etc/pve/lxc/<ID>.conf:"
    echo "    mp0: ${HOST_MOUNT}/,mp=${LXC_MOUNT},shared=1"
fi

echo ""
echo "[+] Done!"
echo "=================================================="
echo ""
echo "TO REMOVE THIS MOUNT LATER:"
echo "  1. Shut down all LXCs/VMs using the mount"
echo "  2. umount ${HOST_MOUNT}"
echo "  3. Remove the entry from /etc/fstab"
echo "  4. systemctl daemon-reload"
echo "  5. Remove the mp line from /etc/pve/lxc/<ID>.conf"
echo "=================================================="
