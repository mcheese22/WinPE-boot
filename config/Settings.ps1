# =====================================================================
#  Settings.ps1  --  SINGLE SOURCE OF CONFIGURATION FOR THE WINPE KIT
# =====================================================================
#  Edit the values below, then run build\Build-WinPE.ps1 on a Windows
#  PC to bake these settings into your bootable USB.
#
#  Everything the automation does is driven by this file. It is copied
#  into the WinPE image and read at boot by Automate.ps1.
# =====================================================================

# ---------------------------------------------------------------------
# 1) DISK / VOLUME / SHRINK  (diskpart)
# ---------------------------------------------------------------------
# These map directly to diskpart commands:
#     select disk   <DiskNumber>
#     select volume <VolumeNumber>
#     shrink desired=<ShrinkMB>
#
# HOW TO FIND THESE NUMBERS:
#   Boot the USB once, let it drop to the command prompt, and run:
#       diskpart
#       list disk        (note the Disk ### of your target drive)
#       list volume      (note the Volume ### you want to shrink)
#       exit
#   Then set the numbers below and re-run, OR set $Interactive = $true
#   below to have the script print the lists and pause on first boot.
#
#   *** LEAVE AS $null UNTIL YOU KNOW YOUR NUMBERS. The script will       ***
#   *** refuse to shrink anything while these are $null (safety guard).   ***

$Config = @{

    # ---- diskpart targets -------------------------------------------
    DiskNumber   = $null      # e.g. 0
    VolumeNumber = $null      # e.g. 3   (the volume to shrink)
    ShrinkMB     = $null      # e.g. 30720  (= 30 GB. diskpart uses MB)

    # ---- safety -----------------------------------------------------
    # When $true, the script lists disks/volumes and WAITS for you to
    # confirm before it shrinks anything. Recommended for the first run.
    Interactive  = $true

    # If $true, the script only PRINTS the diskpart script it would run
    # and does NOT actually shrink. Great for a dry run.
    DryRun       = $false

    # ---- new partition in the freed space (optional) ----------------
    # After the shrink you have unallocated space. If you want the
    # downloaded ISO to live there, let the script create + format it.
    CreateNewPartition = $true
    NewPartitionLetter = "W"        # drive letter to assign
    NewPartitionLabel  = "WIN11DL"
    NewPartitionFS     = "NTFS"     # NTFS or FAT32

    # ---------------------------------------------------------------------
    # 2) WINDOWS 11 DOWNLOAD
    # ---------------------------------------------------------------------
    # Where to save the downloaded ISO.
    #   "NEW"  -> the new partition created above (<NewPartitionLetter>:\)
    #   "AUTO" -> the largest writable fixed volume with enough free space
    #   or an explicit path like "D:\ISO"
    DownloadDestination = "NEW"

    IsoFileName = "Windows11.iso"

    # ---- how to get the ISO -----------------------------------------
    # Method A (default): Fido resolves the official Microsoft link.
    UseFido      = $true
    Win11Edition = "Pro"        # Home / Pro (Fido -Ed value)
    Win11Lang    = "English"    # Fido -Lang value (e.g. "English International")
    Win11Arch    = "x64"        # x64 / arm64

    # Method B (override): if you already have a direct .iso URL, put it
    # here and it will be used INSTEAD of Fido. Leave "" to use Fido.
    DirectIsoUrl = ""

    # ---------------------------------------------------------------------
    # 3) BEHAVIOUR
    # ---------------------------------------------------------------------
    NetworkTimeoutSec = 120      # how long to wait for an IP address
    LogFile           = "X:\winpe-auto.log"
    RebootWhenDone    = $false   # $true to auto-reboot after the download
}

# Return the config so callers can do: $cfg = & Settings.ps1
$Config
