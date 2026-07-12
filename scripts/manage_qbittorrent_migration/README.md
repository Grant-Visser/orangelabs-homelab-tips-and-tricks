# manage_qbittorrent_migration.sh

## What it does

This script migrates all your torrents from one qBittorrent instance to another — **including their categories** — without you having to touch the WebUI, re-add torrents manually, or lose hours of careful organisation.

It's designed specifically for **Proxmox LXC container** setups where you're moving qBittorrent from one container to another (e.g. a full LXC migration or a clean rebuild).

## Why it's cool 🎉

### The Problem It Solves

When you migrate qBittorrent the naive way — copy your `.torrent` files, import them, done — you lose **all your category assignments**. Every torrent lands in the default bucket. If you've got hundreds of torrents sorted into Movies, TV, Music, Software, etc., that's a painful mess to rebuild.

The real category data lives in qBittorrent's binary `.fastresume` files in `BT_backup/`. These are [Bencoded](https://en.wikipedia.org/wiki/Bencode) binary blobs — not human-readable, not trivially parseable.

### How it solves it

1. **Mounts the source LXC filesystem** directly using `pct mount` — no SSH, no file copying, just direct filesystem access on the Proxmox host.

2. **Parses `.fastresume` files natively** using an embedded Python snippet that reads the raw Bencode binary structure to extract the `qBt-category` field from each torrent's metadata. No external libraries needed.

3. **Authenticates with the target qBittorrent WebUI API** and provisions all detected categories on the new instance before importing anything.

4. **Uploads torrents in chunked batches** (30 at a time) grouped by category, using the qBittorrent API's `torrents/add` endpoint. Each torrent lands in the right category, paused, ready for you to verify and resume.

5. **Cleans up after itself** — unmounts the source container, removes temp files.

### The result

Your new qBittorrent instance has all your torrents, all your categories, and all assignments intact. What would've been an hour of manual work is a single script run.

## Prerequisites

- Proxmox host with `pct` available
- Source LXC container ID (the one you're migrating *from*)
- Target LXC running qBittorrent with WebUI enabled
- Python 3 on the Proxmox host (standard on most setups)
- `curl` (standard)

## Configuration

Edit the top of the script:

```bash
SOURCE_ID="121"              # Proxmox LXC ID of the source container
TARGET_IP="192.168.50.173"   # IP of the target container
TARGET_PORT="8090"           # qBittorrent WebUI port on the target
WEBUI_USER="admin"           # WebUI username
WEBUI_PASS="adminadmin"      # WebUI password
BT_BACKUP_PATH="root/.local/share/qBittorrent/BT_backup"  # Path inside source LXC
```

## Usage

Run this **on your Proxmox host** (not inside a container):

```bash
chmod +x manage_qbittorrent_migration.sh
./manage_qbittorrent_migration.sh
```

The source container does **not** need to be running — the script mounts its filesystem directly.

## Output

```
==================================================
 qBittorrent Native Bencode Category Patch Tool 
==================================================
[*] Mounting Source LXC 121 storage volume...
[*] Authenticating with Target WebUI API...
[+] API Session authenticated successfully.
[*] Parsing .fastresume binary structures natively...
[*] Provisioning real category indices on target application...
 -> Creating category: 'Movies'
 -> Creating category: 'TV Shows'
[*] Beginning localized chunk processing batches...
[*] Processing real category 'Movies' (47 torrents)...
 -> Chunk 1: Status 200
 -> Chunk 2: Status 200
...
[+] Done! Check your WebUI now.
==================================================
```

## Notes

- Torrents are added **paused** — gives you a chance to verify before everything starts downloading/seeding.
- The script handles `uncategorized` torrents separately — they're added without a category tag.
- Categories are provisioned on the target **before** torrents are uploaded, so no orphaned assignments.
- Chunk size of 30 is conservative and avoids API timeouts on large libraries. Adjust `CHUNK_SIZE` if needed.
