# ProxRemote for TV

A read-only Apple TV companion to the [ProxRemote](https://apps.apple.com/app/proxremote)
iPhone app for managing Proxmox VE clusters.

## What it does

Pair your iPhone once via QR code (end-to-end encrypted with X25519 + AES-GCM)
and the TV shows live cluster status:

- Cluster summary tiles — nodes, VMs, containers, storage
- Node grid with live CPU/RAM bars
- VM and container detail pages with status, config, and snapshot lists
- Recent-tasks feed
- After 90 seconds of idle, a screen-saver mode cycles through each node's
  key stats

Read-only by design — every destructive action lives in the iPhone app.

## Requirements

- tvOS 16.0+
- An Apple TV signed into the same Apple ID as the iPhone running ProxRemote
- A Proxmox VE 7.x or 8.x server reachable from both devices

## Pairing security

The pairing channel is end-to-end encrypted. A passive observer on your local
network cannot read the transmitted credentials. The 6-digit code displayed on
the TV protects against an active attacker submitting a tampered key during
the brief pairing window (max 3 attempts, 60-second TTL on the listener).

See [SECURITY.md](SECURITY.md) for the full protocol.

## Privacy

See [PRIVACY.md](PRIVACY.md). Short version: this app does not collect,
transmit, or share any data with anyone other than the Proxmox server you
configure.

## Support

Open an issue: <https://github.com/forever54321/proxremote-tv/issues>

Or email: proxremote@saedzakari.com

## License

© 2026 Saed Zakari. All rights reserved.
