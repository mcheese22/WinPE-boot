# Setup & Usage Guide

This kit builds a **WinPE USB** that, when you boot it, will automatically:

1. Bring up networking.
2. Open a command prompt (WinPE always does this).
3. Run `diskpart` to **select a disk, select a volume, and shrink it** by a size you choose.
4. (Optional) create + format a new partition in the freed space.
5. **Download a Windows 11 ISO** into it — hands-free.

> **Important reality check:** A WinPE image can only be *built* on a
> Windows PC with the Microsoft ADK. This repo contains all the scripts;
> you run one build script (`build\Build-WinPE.ps1`) on Windows to turn
> them into your bootable USB.

---

## 1. Prerequisites (on a normal Windows 10/11 PC)

- **Windows ADK** and the **Windows PE add-on**, both installed:
  <https://learn.microsoft.com/windows-hardware/get-started/adk-install>
- A **USB stick** (8 GB+). Building will erase it.
- Administrator rights.
- A **wired/Ethernet** connection on the *target* machine. WinPE has **no Wi‑Fi support**.

## 2. Fill in your settings

Open `config/Settings.ps1` and set the three key values. If you don't
know your disk/volume numbers yet, leave them as `$null` — on first boot
the kit lists all disks/volumes and then stops **without changing
anything**, so you can read the numbers and come back.

| Setting        | Meaning                              | Example  |
|----------------|--------------------------------------|----------|
| `DiskNumber`   | `diskpart` → `select disk`           | `0`      |
| `VolumeNumber` | `diskpart` → `select volume`         | `3`      |
| `ShrinkMB`     | `diskpart` → `shrink desired=` (MB)  | `30720` (30 GB) |

Other useful switches in the same file:

- `Interactive = $true` — pause for an ENTER press before shrinking (recommended first time).
- `DryRun = $true` — print the diskpart script but **don't** shrink (safe test).
- `CreateNewPartition` / `DownloadDestination` — where the ISO lands.
- `UseFido` vs `DirectIsoUrl` — how the ISO is fetched.

## 3. Build the USB

From an **elevated PowerShell** on your Windows PC, inside the repo:

```powershell
# Straight onto a USB stick shown as F:
.\build\Build-WinPE.ps1 -UsbDrive F: -IncludeFido

# ...or make an ISO instead
.\build\Build-WinPE.ps1 -MakeIso -IsoPath C:\winpe.iso -IncludeFido
```

`-IncludeFido` bakes the [Fido](https://github.com/pbatard/Fido) link
resolver into the image so the target machine doesn't have to fetch it at
boot. *(Fido is a third-party open-source PowerShell script that returns
official Microsoft ISO links; content summarized here for compliance.)*

## 4. Boot the target machine

1. Plug in the USB and the Ethernet cable.
2. Boot from the USB (usually F12 / F2 / Del for the boot menu; disable
   Secure Boot if the machine refuses an unsigned WinPE image).
3. Watch it work. Progress is printed on screen and written to
   `X:\winpe-auto.log`.

## 5. First-run to find your numbers (if you left them `$null`)

1. Build + boot once with `DiskNumber/VolumeNumber/ShrinkMB` left `$null`.
2. The screen shows `list disk` and `list volume`. Note your numbers.
3. Either rebuild the USB with the values filled in, **or** edit
   `X:\Settings.ps1` on the fly (the file sits at the root of the WinPE
   RAM drive) and re-run `X:\Automate.ps1`.

---

## How the pieces fit together

```
config/Settings.ps1        <- you edit this (the only config)
scripts/startnet.cmd       -> runs on boot: wpeinit, then Automate.ps1
scripts/Automate.ps1       -> network wait, diskpart shrink, partition, hand off
scripts/Download-Win11.ps1 -> Fido/direct URL + curl/BITS/IWR download
build/Build-WinPE.ps1      -> assembles all of the above into a bootable USB
```

## Safety notes

- The kit **refuses to shrink** while `DiskNumber`, `VolumeNumber`, or
  `ShrinkMB` are unset — so a misconfigured stick can't nuke a drive.
- `shrink` is non-destructive: it only reclaims *free* space at the tail
  of a volume. It never touches your files.
- Creating/formatting the **new** partition only affects the freshly
  freed, unallocated space — not your existing data.
- Always double-check the disk/volume numbers on the *target* machine;
  they can differ from what Windows shows normally.

## Troubleshooting

| Symptom | Likely cause / fix |
|---------|--------------------|
| "No IP address obtained" | Use Ethernet (no Wi‑Fi in WinPE); check the NIC driver. |
| Fido returns no URL | Microsoft occasionally rate-limits/changes endpoints — set `DirectIsoUrl` instead. |
| Shrink fails | Not enough free space, or unmovable files at the end of the volume; defragment in full Windows first, or shrink less. |
| USB won't boot | Enable USB/legacy boot, or disable Secure Boot for unsigned WinPE. |
| PowerShell missing at boot | Rebuild — the `WinPE-PowerShell` optional component didn't get added. |
