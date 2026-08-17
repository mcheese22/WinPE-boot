#Requires -RunAsAdministrator
<#
    Build-WinPE.ps1  --  builds the bootable WinPE media for this kit.

    RUN THIS ON A WINDOWS 10/11 PC that has the Windows ADK + the
    "Windows PE add-on" installed. It cannot run inside WinPE or Linux.

    What it does:
      1. Finds the ADK and creates a fresh WinPE working set (copype).
      2. Mounts boot.wim and adds the optional components needed for
         networking + PowerShell + storage cmdlets.
      3. Injects this kit's scripts and replaces startnet.cmd.
      4. Commits the image and writes it to a USB stick (or an ISO).

    Examples:
      # Build straight onto a USB stick that is drive F:
      .\Build-WinPE.ps1 -UsbDrive F:

      # Build an ISO instead (burn/mount later)
      .\Build-WinPE.ps1 -MakeIso -IsoPath C:\winpe.iso

      # Also bake Fido.ps1 into the image (recommended, avoids needing
      # to fetch it at boot):
      .\Build-WinPE.ps1 -UsbDrive F: -IncludeFido
#>
[CmdletBinding(DefaultParameterSetName = 'Usb')]
param(
    [Parameter(ParameterSetName = 'Usb', Mandatory)]
    [string] $UsbDrive,                       # e.g. "F:"

    [Parameter(ParameterSetName = 'Iso', Mandatory)]
    [switch] $MakeIso,
    [Parameter(ParameterSetName = 'Iso')]
    [string] $IsoPath = "$env:USERPROFILE\Desktop\winpe-win11.iso",

    [ValidateSet('amd64','arm64','x86')]
    [string] $Arch = 'amd64',

    [string] $WorkDir = "$env:TEMP\WinPE_$([guid]::NewGuid().ToString('N').Substring(0,8))",

    [switch] $IncludeFido
)

$ErrorActionPreference = 'Stop'
function Say { param($m) Write-Host "[build] $m" -ForegroundColor Cyan }
function Warn { param($m) Write-Host "[build] $m" -ForegroundColor Yellow }

# --- resolve paths -------------------------------------------------------
$KitRoot     = Split-Path -Parent $PSScriptRoot          # ...\WinPE-boot
$ScriptsDir  = Join-Path $KitRoot 'scripts'
$ConfigDir   = Join-Path $KitRoot 'config'

foreach ($f in @(
    (Join-Path $ScriptsDir 'startnet.cmd'),
    (Join-Path $ScriptsDir 'Automate.ps1'),
    (Join-Path $ScriptsDir 'Download-Win11.ps1'),
    (Join-Path $ConfigDir  'Settings.ps1')
)) {
    if (-not (Test-Path $f)) { throw "Kit file missing: $f" }
}

# --- locate the ADK ------------------------------------------------------
$adkRoots = @(
    "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit",
    "$env:ProgramFiles\Windows Kits\10\Assessment and Deployment Kit"
)
$adk = $adkRoots | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $adk) {
    throw "Windows ADK not found. Install the ADK + 'Windows PE add-on' from https://learn.microsoft.com/windows-hardware/get-started/adk-install"
}
$peEnv = Join-Path $adk 'Deployment Tools\DandISetEnv.bat'
$copype = Join-Path $adk 'Windows Preinstallation Environment\copype.cmd'
if (-not (Test-Path $copype)) {
    throw "copype.cmd not found under '$adk'. Is the 'Windows PE add-on' installed?"
}
Say "Using ADK at: $adk"

# Path to the optional-component packages inside the ADK
$ocRoot = Join-Path $adk "Windows Preinstallation Environment\$Arch\WinPE_OCs"

# --- 1) copype -----------------------------------------------------------
Say "Creating WinPE working set at $WorkDir ..."
cmd.exe /c "`"$peEnv`" && copype $Arch `"$WorkDir`"" | Out-Null
$bootWim   = Join-Path $WorkDir 'media\sources\boot.wim'
$mountDir  = Join-Path $WorkDir 'mount'
if (-not (Test-Path $bootWim)) { throw "copype did not produce boot.wim at $bootWim" }

# --- 2) mount + add optional components ----------------------------------
Say "Mounting boot.wim ..."
Mount-WindowsImage -ImagePath $bootWim -Index 1 -Path $mountDir | Out-Null

try {
    # ORDER MATTERS: WMI, then NetFx, then PowerShell, then the cmdlet packs.
    # Each language pack (…_en-us.cab) must follow its base package.
    $ocs = @(
        'WinPE-WMI',
        'WinPE-NetFx',
        'WinPE-Scripting',
        'WinPE-PowerShell',
        'WinPE-StorageWMI',
        'WinPE-DismCmdlets'
    )
    foreach ($oc in $ocs) {
        $base = Join-Path $ocRoot "$oc.cab"
        $lang = Join-Path $ocRoot "en-us\$oc`_en-us.cab"
        if (-not (Test-Path $base)) { Warn "Optional component not found, skipping: $base"; continue }
        Say "Adding $oc ..."
        Add-WindowsPackage -Path $mountDir -PackagePath $base | Out-Null
        if (Test-Path $lang) { Add-WindowsPackage -Path $mountDir -PackagePath $lang | Out-Null }
    }

    # --- 3) inject our files ---------------------------------------------
    Say "Injecting kit scripts ..."
    # startnet.cmd lives in \Windows\System32 and runs automatically.
    Copy-Item (Join-Path $ScriptsDir 'startnet.cmd') (Join-Path $mountDir 'Windows\System32\startnet.cmd') -Force

    # Everything else goes to the RAM-drive root (becomes X:\ at boot).
    Copy-Item (Join-Path $ScriptsDir 'Automate.ps1')        (Join-Path $mountDir 'Automate.ps1') -Force
    Copy-Item (Join-Path $ScriptsDir 'Download-Win11.ps1')  (Join-Path $mountDir 'Download-Win11.ps1') -Force
    Copy-Item (Join-Path $ConfigDir  'Settings.ps1')        (Join-Path $mountDir 'Settings.ps1') -Force

    if ($IncludeFido) {
        $fidoDest = Join-Path $mountDir 'Fido.ps1'
        Say "Downloading Fido.ps1 to bake into the image ..."
        try {
            Invoke-WebRequest -Uri 'https://github.com/pbatard/Fido/raw/master/Fido.ps1' -OutFile $fidoDest -UseBasicParsing
        } catch {
            Warn "Could not fetch Fido.ps1 now ($_). It will be downloaded at boot instead."
        }
    }
}
finally {
    Say "Committing and unmounting image ..."
    Dismount-WindowsImage -Path $mountDir -Save | Out-Null
}

# --- 4) write media ------------------------------------------------------
$makeMedia = Join-Path $adk 'Windows Preinstallation Environment\MakeWinPEMedia.cmd'

if ($PSCmdlet.ParameterSetName -eq 'Usb') {
    Warn "About to FORMAT $UsbDrive and write WinPE to it. All data on it will be lost."
    Read-Host "Press ENTER to continue, or Ctrl+C to abort"
    Say "Writing WinPE to USB $UsbDrive ..."
    cmd.exe /c "`"$peEnv`" && `"$makeMedia`" /UFD /f `"$WorkDir`" $UsbDrive"
    Say "Done. Bootable USB is ready on $UsbDrive."
}
else {
    Say "Building ISO at $IsoPath ..."
    cmd.exe /c "`"$peEnv`" && `"$makeMedia`" /ISO `"$WorkDir`" `"$IsoPath`""
    Say "Done. ISO written to $IsoPath."
}

Say "Working set left at $WorkDir (delete when you're happy with the result)."
Say "Reminder: fill in DiskNumber / VolumeNumber / ShrinkMB in Settings.ps1 before the shrink will run."
