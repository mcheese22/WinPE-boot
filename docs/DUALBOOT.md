# Automated Dual-Boot Windows 11 (using your Rufus USB)

This is the **recommended** path for the goal: *"boot a USB, have it shrink
a volume and install a second Windows 11 automatically, hands-free."*

You already have the hard part — a **Rufus Windows 11 install USB**. All we
add is one file: **`autounattend.xml`** (in `unattended/`). Drop it on the
root of the USB and Windows Setup runs the whole thing by itself.

---

## The mental model (important!)

- Your Rufus USB boots into **Windows Setup**. That is NOT a "downloader" —
  the ISO on the USB already contains a full copy of Windows 11. Nothing is
  downloaded; it **installs from the USB**.
- There is **no "click download" button**. With `autounattend.xml`,
  **booting the USB is the trigger**. You boot → it shrinks → it installs →
  you get a boot menu with both Windows 11s. That's the "one click."
- Your existing Windows 11 is **not touched**. We only shrink free space and
  install into the new empty partition. Result = **dual boot**.

---

## ⚠️ Do this in a Virtual Machine FIRST

This is genuinely the one advanced/risky step in the whole plan, so please
don't skip it. The only real danger is the **install-target partition
number** — if it's wrong, Setup could format the wrong partition.

1. Install **VirtualBox** or enable **Hyper-V** (both free).
2. Create a VM, install Windows 11 in it normally (this becomes the
   "existing" OS to dual-boot alongside).
3. Attach your ISO + a virtual USB with `autounattend.xml` and boot it.
4. Confirm it shrinks and installs the second OS without harming the first.
5. Only then run it on your real laptop.

A VM mistake costs nothing. A real-laptop mistake costs your data.

---

## Step 1 — Find your numbers

Boot the Rufus USB. At the first Setup screen press **Shift + F10** to open a
command prompt, then:

```
diskpart
list disk        (note your target Disk ### -> usually 0)
list volume      (note the Volume ### of your current Windows / C:)
list partition   (after selecting the disk: "select disk 0" then this)
exit
```

Write down:
- **Disk number** (A)
- **Volume number** to shrink (B)
- How many partitions already exist (the NEW one will be the next number, D)

## Step 2 — Edit `autounattend.xml`

Open `unattended/autounattend.xml` and fill in every `### SET ###` spot:

| Item | Where | What to put |
|------|-------|-------------|
| A. Disk | `SELECT DISK=0` | your disk number |
| B. Volume | `SELECT VOLUME=2` | volume to shrink |
| C. Size | `SHRINK DESIRED=61440` | MB to free (61440 = 60 GB) |
| D. Target | `<PartitionID>5</PartitionID>` | the NEW partition's number |
| E. Edition | `/IMAGE/NAME` → `Windows 11 Pro` | must match your ISO |
| F. Account | `<Name>` / `<Password>` | your login for the new OS |

**Find the edition name** your ISO actually contains:
```
dism /Get-WimInfo /WimFile:X:\sources\install.wim
```
(Replace `X:` with your USB's letter. If you see `install.esd` instead of
`install.wim`, use that filename.)

## Step 3 — Copy it onto the USB

Copy `autounattend.xml` to the **root** of the Rufus USB (same level as
`setup.exe` and the `sources` folder). That's it.

## Step 4 — Boot and walk away

Boot the target machine from the USB. It will shrink, partition, and install
automatically. When it finishes, restarting shows a **boot menu** letting you
choose between your two Windows 11 installs.

---

## Making it repeatable

Once the numbers are dialled in for a given machine, this USB reproduces the
same result every time you boot it there — that's your "repeat the task"
requirement met.

> Note: volume/partition numbers can differ between **different** machines or
> disk layouts. If you'll run this on machines that aren't identical, re-check
> the numbers per machine (Step 1), because a hardcoded partition number that
> was safe on one layout could point somewhere else on another.

## Common questions

- **Two Windows 11 on one disk — allowed?** Yes. Dual-booting two copies of
  Windows 11 is fine; each lives in its own partition and gets its own boot
  entry.
- **Activation?** The generic key in the file lets Setup proceed but does not
  activate. Put in your real key during/after install to activate.
- **No shrink happened / "not enough space"** — the volume may have unmovable
  files at its end. Defragment in the running Windows first, or shrink less.
