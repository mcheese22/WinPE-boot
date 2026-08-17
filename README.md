# WinPE-boot

Automate a **hands-free, dual-boot Windows 11 install** from a USB: boot it,
walk away, and come back to a machine that shrank a volume and installed a
second Windows 11 alongside the existing one.

## 👉 Recommended path: automated dual boot (`autounattend.xml`)

If you already have a **Rufus Windows 11 USB** and want to *install* a second
Windows 11 (dual boot), this is your path — **you don't need to build WinPE
or download anything.** The ISO on your USB already contains Windows.

1. Take the file **[`unattended/autounattend.xml`](unattended/autounattend.xml)**.
2. Fill in your disk/volume/shrink-size/partition/edition (all marked `### SET ###`).
3. Copy it to the **root of your Rufus USB**.
4. Boot the USB — Windows Setup reads the file and does everything: shrink →
   new partition → install second Windows 11. Result = **dual boot menu**.

📖 Full walkthrough: **[docs/DUALBOOT.md](docs/DUALBOOT.md)** — includes the
important "test in a VM first" safety step.

> There is no literal "download" button — **booting the USB *is* the trigger**.
> That's the one-click, repeatable flow.

---

## Alternative path: WinPE that *downloads* a fresh ISO

Only needed if you do **not** have an ISO and want the USB to fetch one from
the internet at boot (requires wired Ethernet — WinPE has no Wi-Fi). This is
the original kit below.

A hands-free **WinPE** kit that boots from USB and automatically:

1. 🌐 brings up networking,
2. 💻 opens the WinPE command prompt,
3. 🧮 runs `diskpart` to **select a disk → select a volume → shrink it** by a size you pick,
4. ➕ (optional) creates + formats a new partition in the freed space,
5. ⬇️ **downloads a Windows 11 ISO** into it — no keyboard required.

> ⚠️ **WinPE images can only be *built* on a Windows PC with the Microsoft
> ADK.** `build/Build-WinPE.ps1` turns the scripts into a bootable USB.
> See **[docs/SETUP.md](docs/SETUP.md)**.

## Layout

| Path | What it is |
|------|------------|
| `config/Settings.ps1` | **The only file you edit.** Disk/volume/shrink size + download options. |
| `scripts/startnet.cmd` | WinPE auto-run entrypoint (`wpeinit` → `Automate.ps1`). |
| `scripts/Automate.ps1` | Orchestrates: network wait, diskpart shrink, partitioning, download. |
| `scripts/Download-Win11.ps1` | Resolves the Win11 ISO link (Fido or direct URL) and downloads it. |
| `build/Build-WinPE.ps1` | Builds the bootable USB/ISO on a Windows + ADK machine. |
| `docs/SETUP.md` | Full step-by-step guide. |

## Quick start

```powershell
# 1. Edit config\Settings.ps1  (set DiskNumber / VolumeNumber / ShrinkMB)
#    ...or leave them $null the first time to just LIST disks safely.

# 2. On a Windows PC with the ADK, from an elevated PowerShell:
.\build\Build-WinPE.ps1 -UsbDrive F: -IncludeFido

# 3. Boot the target machine from the USB (wired Ethernet required).
```

## Safety

- Won't shrink anything until `DiskNumber` / `VolumeNumber` / `ShrinkMB`
  are set — an unconfigured stick is inert.
- `shrink` only reclaims free space; it doesn't touch existing files.
- A `DryRun` switch prints the exact `diskpart` script without running it.

## Notes & credits

- Windows 11 ISO links are resolved via [Fido](https://github.com/pbatard/Fido),
  an open-source script that returns official Microsoft download links.
  You can also supply your own `DirectIsoUrl`.
- WinPE has **no Wi‑Fi support** — use a wired connection on the target.

See **[docs/SETUP.md](docs/SETUP.md)** for the detailed walkthrough,
troubleshooting, and first-run tips.
