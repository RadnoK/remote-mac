# Changelog

All notable changes to RemoteMac are documented here.

## 1.0.0 — 2026-09-06

First public release.

### Added

- Automatic discovery of Macs on your Tailscale tailnet, listed by name in
  the menu bar.
- Manual hosts for machines outside your tailnet.
- Per-device settings: display name override, SSH user override, Screen
  Sharing port override, and show/hide.
- Status dots per device: available, sharing off, offline, not found.
- One-click Screen Sharing via macOS's built-in client.
- SSH launch in your terminal of choice — Ghostty, iTerm2, Terminal, or Warp,
  limited to whichever are actually installed.
- Copy IP and open SMB quick actions.
- Spotlight-style quick connect window.
- Background status refresh every 30 seconds.
- English and Polish localization, following system language or a manual
  override.
- Launch at login.
- Sparkle-based auto-updates, signed with EdDSA.
- Right-click menu on the status item (Refresh, Settings, Check for Updates,
  Quit).

### Known limitations

- Screen Sharing reachability is a TCP port check — it confirms the service
  is listening, not that login will succeed.
- Warp cannot be driven programmatically; RemoteMac copies the SSH command to
  the clipboard instead of typing it for you.
- Terminal.app requires an Automation (AppleEvents) permission grant on first
  use.
