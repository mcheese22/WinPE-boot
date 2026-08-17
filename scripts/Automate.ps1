<#
    Automate.ps1  --  WinPE hands-free orchestrator

    Boot flow (called by startnet.cmd):
        1. Load config (X:\Settings.ps1)
        2. Wait for a network address (DHCP)
        3. Optional interactive confirmation (list disks/volumes)
        4. Shrink the chosen volume with diskpart
        5. Optionally create + format a new partition in the freed space
        6. Download the Windows 11 ISO (X:\Download-Win11.ps1)
        7. Optionally reboot

    Nothing here formats or deletes the source volume. The only
    destructive-ish action is `shrink`, which is non-destructive to
    existing data (it only reclaims free space at the end of the volume).
#>

$ErrorActionPreference = 'Stop'

# --- locate kit files (root of the WinPE RAM drive) ----------------------
$Root = 'X:\'
$cfg  = & (Join-Path $Root 'Settings.ps1')

# --- logging -------------------------------------------------------------
$script:LogPath = $cfg.LogFile
function Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = "{0} [{1}] {2}" -f (Get-Date -Format 'HH:mm:ss'), $Level, $Message
    Write-Host $line
    try { Add-Content -Path $script:LogPath -Value $line -ErrorAction SilentlyContinue } catch {}
}

function Fail {
    param([string]$Message)
    Log $Message 'ERROR'
    Log 'Automation stopped. Dropping to command prompt so you can inspect.' 'ERROR'
    exit 1
}

Log '=============================================='
Log 'WinPE Windows 11 auto-downloader starting'
Log '=============================================='

# =========================================================================
# STEP 1  --  wait for networking
# =========================================================================
function Wait-Network {
    param([int]$TimeoutSec)
    Log "Waiting up to $TimeoutSec s for a network address..."
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        try {
            $ips = Get-CimInstance Win32_NetworkAdapterConfiguration -ErrorAction SilentlyContinue |
                   Where-Object { $_.IPEnabled -and $_.IPAddress } |
                   ForEach-Object { $_.IPAddress } |
                   Where-Object { $_ -and $_ -ne '0.0.0.0' -and $_ -notlike '169.254.*' -and $_ -notlike '*:*' }
            if ($ips) {
                Log ("Network is up. IP(s): {0}" -f ($ips -join ', '))
                return $true
            }
        } catch {}
        Start-Sleep -Seconds 3
    }
    return $false
}

if (-not (Wait-Network -TimeoutSec $cfg.NetworkTimeoutSec)) {
    Log 'No IP address obtained. Continuing anyway - the download step will retry.' 'WARN'
    Log 'Note: WinPE has NO Wi-Fi support. Use a wired/Ethernet connection.' 'WARN'
}

# =========================================================================
# STEP 2  --  show disks/volumes and (optionally) confirm
# =========================================================================
function Invoke-DiskPart {
    param([string[]]$Commands)
    $tmp = [System.IO.Path]::GetTempFileName()
    Set-Content -Path $tmp -Value ($Commands -join "`r`n") -Encoding ASCII
    $out = & diskpart.exe /s $tmp 2>&1
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    return $out
}

Log 'Current disks:'
(Invoke-DiskPart @('list disk'))        | ForEach-Object { Log "  $_" }
Log 'Current volumes:'
(Invoke-DiskPart @('list volume'))      | ForEach-Object { Log "  $_" }

# Safety guard: refuse to shrink until the user has set real numbers.
if ($null -eq $cfg.DiskNumber -or $null -eq $cfg.VolumeNumber -or $null -eq $cfg.ShrinkMB) {
    Log 'DiskNumber / VolumeNumber / ShrinkMB are not set in Settings.ps1.' 'WARN'
    Log 'Nothing will be shrunk. Note the numbers above, put them in the' 'WARN'
    Log 'config, rebuild the USB (or edit X:\Settings.ps1), and boot again.' 'WARN'
    Fail 'Configuration incomplete - aborting before any disk change.'
}

if ($cfg.Interactive) {
    Log ("About to: select disk {0}, select volume {1}, shrink desired={2} MB" -f `
         $cfg.DiskNumber, $cfg.VolumeNumber, $cfg.ShrinkMB)
    Write-Host ''
    Write-Host '>>> Press ENTER to proceed, or close/reset the machine to abort. <<<' -ForegroundColor Yellow
    [void][System.Console]::ReadLine()
}

# =========================================================================
# STEP 3  --  shrink the target volume
# =========================================================================
$shrinkScript = @(
    "select disk $($cfg.DiskNumber)",
    "select volume $($cfg.VolumeNumber)",
    "shrink desired=$($cfg.ShrinkMB)"
)

if ($cfg.DryRun) {
    Log 'DryRun = $true. The diskpart script below would run:' 'WARN'
    $shrinkScript | ForEach-Object { Log "    $_" 'WARN' }
} else {
    Log ("Shrinking volume {0} by {1} MB..." -f $cfg.VolumeNumber, $cfg.ShrinkMB)
    $res = Invoke-DiskPart $shrinkScript
    $res | ForEach-Object { Log "  $_" }
    if ($res -match 'successfully shrunk|reduced the size') {
        Log 'Shrink completed successfully.'
    } else {
        Fail 'diskpart did not report a successful shrink. See log above.'
    }
}

# =========================================================================
# STEP 4  --  optionally create + format a new partition in freed space
# =========================================================================
$downloadDest = $cfg.DownloadDestination

if ($cfg.CreateNewPartition -and -not $cfg.DryRun) {
    Log ("Creating a new {0} partition ({1}:) in the freed space..." -f `
         $cfg.NewPartitionFS, $cfg.NewPartitionLetter)
    $createScript = @(
        "select disk $($cfg.DiskNumber)",
        "create partition primary",
        "format fs=$($cfg.NewPartitionFS) label=`"$($cfg.NewPartitionLabel)`" quick",
        "assign letter=$($cfg.NewPartitionLetter)"
    )
    $res = Invoke-DiskPart $createScript
    $res | ForEach-Object { Log "  $_" }
    Start-Sleep -Seconds 2
}

if ($downloadDest -eq 'NEW') {
    $downloadDest = "$($cfg.NewPartitionLetter):\"
}

# =========================================================================
# STEP 5  --  download Windows 11
# =========================================================================
Log 'Handing off to the Windows 11 downloader...'
& (Join-Path $Root 'Download-Win11.ps1') -Config $cfg -Destination $downloadDest -LogFile $script:LogPath

if ($LASTEXITCODE -ne 0) {
    Fail 'Windows 11 download failed. See log above.'
}

Log '=============================================='
Log 'ALL DONE.'
Log '=============================================='

if ($cfg.RebootWhenDone -and -not $cfg.DryRun) {
    Log 'Rebooting in 10 seconds (RebootWhenDone = $true)...'
    Start-Sleep -Seconds 10
    wpeutil reboot
}

exit 0
