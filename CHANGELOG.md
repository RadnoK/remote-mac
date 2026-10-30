# Changelog

All notable changes to RemoteMac are documented here.

## Unreleased

### Added

- Shared monitor switch — set each Mac's monitor input in Settings → Machines
  and a button in its row switches the monitor to it over DDC. Needs `m1ddc`
  on every Mac on the monitor.

## 1.1.1 — 2026-10-30

### Fixed

- Clicking a Mac in the menu now works on macOS 27 (it did nothing before).

## 1.1.0 — 2026-10-21

### Added

- No password prompt — reuses the password Screen Sharing remembered in your
  Keychain.
- Automatic connection type (opt-in, needs Accessibility) — High Performance
  on the same local network, Standard elsewhere, overridable per Mac.

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
