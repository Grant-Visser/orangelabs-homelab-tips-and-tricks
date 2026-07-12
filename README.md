# 🏠 Orangelabs Homelab Tips & Tricks

A growing collection of tips, tricks, and scripts I've picked up running my homelab — the stuff that actually makes a difference when you're knee-deep in containers, VMs, and self-hosted services.

## What's in here?

This repo is a living document. Every time I solve a gnarly problem or find a better way to do something, it ends up here so future-me (and maybe you) doesn't have to figure it out again.

## Scripts

| Script | What it does |
|--------|-------------|
| [`manage_qbittorrent_migration`](scripts/manage_qbittorrent_migration/) | Migrate torrents between qBittorrent instances (LXC containers) with full category preservation |
| [`add_smb_share_to_lxc`](scripts/add_smb_share_to_lxc/) | Mount a CIFS/SMB NAS share on the Proxmox host and bind-mount it into LXC containers with correct UID/GID mapping |

## Philosophy

- **Automate the annoying stuff.** If you've done it twice manually, it should be a script.
- **Don't lose your data.** Especially your torrent categories and metadata — hours of organisation shouldn't vanish in a migration.
- **Keep it readable.** Scripts should be understandable by future-you at 2am.

---

*Maintained by [Grant-Visser](https://github.com/Grant-Visser)*
