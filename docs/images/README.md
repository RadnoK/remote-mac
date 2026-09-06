# Images

Assets referenced by the top-level `README.md`.

| File | What it is |
|---|---|
| `banner.png` | Header banner: app icon, name and tagline. |
| `menu-bar-panel.png` | The menu bar panel — machines by name with status dots and the icon footer. |
| `settings-devices.png` | Settings → Machines: the device list with Tailscale badges and the per-device Machine / Display / Connection sections. |
| `settings-general.png` | Settings → General: terminal picker, fallback SSH user, launch at login, language. |

Screenshots are taken on a Retina display, so they are 2× the point size.
Blur any IP addresses and usernames before committing — the panel and the
Machines tab both show them.

The app icon itself lives in `Resources/AppIcon.appiconset/`, not here;
`Scripts/make-icon.sh` turns it into `AppIcon.icns` at build time.
