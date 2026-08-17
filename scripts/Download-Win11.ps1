<#
    Download-Win11.ps1  --  fetch a Windows 11 ISO inside WinPE

    Called by Automate.ps1. Can also be run standalone for testing:
        .\Download-Win11.ps1 -Config (& .\Settings.ps1) -Destination 'D:\' -LogFile 'X:\dl.log'

    Two ways to get the ISO:
      * Fido  (default): resolves the official Microsoft retail link.
      * DirectIsoUrl   : if set in the config, that URL is used verbatim.

    Download transport tries, in order: curl.exe -> BITS -> Invoke-WebRequest,
    so it works across the different WinPE builds people end up with.
#>
param(
    [Parameter(Mandatory)] $Config,
    [Parameter(Mandatory)] [string] $Destination,
    [string] $LogFile = 'X:\winpe-auto.log'
)

$ErrorActionPreference = 'Stop'

function Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = "{0} [{1}] (dl) {2}" -f (Get-Date -Format 'HH:mm:ss'), $Level, $Message
    Write-Host $line
    try { Add-Content -Path $LogFile -Value $line -ErrorAction SilentlyContinue } catch {}
}

# -------------------------------------------------------------------------
# Resolve the destination folder & make sure it is writable
# -------------------------------------------------------------------------
function Resolve-Destination {
    param([string]$Dest, $Cfg)

    if ($Dest -eq 'AUTO') {
        Log 'DownloadDestination = AUTO: picking largest writable fixed volume...'
        $vol = Get-Volume -ErrorAction SilentlyContinue |
               Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' -and $_.SizeRemaining -gt 10GB } |
               Sort-Object SizeRemaining -Descending |
               Select-Object -First 1
        if (-not $vol) { throw 'AUTO could not find a fixed volume with >10 GB free.' }
        $Dest = "$($vol.DriveLetter):\"
        Log "AUTO selected $Dest ($([math]::Round($vol.SizeRemaining/1GB,1)) GB free)."
    }

    if (-not (Test-Path $Dest)) {
        New-Item -ItemType Directory -Path $Dest -Force | Out-Null
    }

    # verify writable
    $probe = Join-Path $Dest '.winpe_write_test'
    try {
        Set-Content -Path $probe -Value 'ok' -ErrorAction Stop
        Remove-Item $probe -Force -ErrorAction SilentlyContinue
    } catch {
        throw "Destination '$Dest' is not writable: $_"
    }
    return $Dest
}

# -------------------------------------------------------------------------
# Get the ISO URL (Fido or direct)
# -------------------------------------------------------------------------
function Get-IsoUrl {
    param($Cfg)

    if ($Cfg.DirectIsoUrl -and $Cfg.DirectIsoUrl.Trim()) {
        Log "Using DirectIsoUrl from config."
        return $Cfg.DirectIsoUrl.Trim()
    }

    if (-not $Cfg.UseFido) {
        throw 'No DirectIsoUrl set and UseFido = $false. Nothing to download.'
    }

    Log 'Resolving official Windows 11 link with Fido...'
    $fido = 'X:\Fido.ps1'
    if (-not (Test-Path $fido)) {
        # Not baked into the image? pull the latest at runtime.
        Log 'Fido.ps1 not found in image; downloading it from GitHub...'
        $fidoUrl = 'https://github.com/pbatard/Fido/raw/master/Fido.ps1'
        Invoke-Fetch -Url $fidoUrl -OutFile $fido
    }

    # -GetUrl makes Fido print the resolved URL to stdout without downloading.
    $url = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $fido `
                -Win 11 -Ed $Cfg.Win11Edition -Lang $Cfg.Win11Lang -Arch $Cfg.Win11Arch -GetUrl 2>&1

    $url = ($url | Where-Object { $_ -match '^https?://' } | Select-Object -Last 1)
    if (-not $url) { throw "Fido did not return a URL. Output: $url" }
    Log "Fido resolved: $url"
    return $url.Trim()
}

# -------------------------------------------------------------------------
# Download transport with fallbacks
# -------------------------------------------------------------------------
function Invoke-Fetch {
    param([string]$Url, [string]$OutFile)

    # 1) curl.exe (fast, resumable, present in most modern WinPE builds)
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($curl) {
        Log 'Downloading with curl.exe...'
        & curl.exe -L --fail --retry 5 --retry-delay 5 -C - -o $OutFile $Url
        if ($LASTEXITCODE -eq 0 -and (Test-Path $OutFile)) { return }
        Log 'curl.exe failed; trying next method.' 'WARN'
    }

    # 2) BITS (if the service is available in this WinPE build)
    if (Get-Command Start-BitsTransfer -ErrorAction SilentlyContinue) {
        try {
            Log 'Downloading with BITS...'
            Start-BitsTransfer -Source $Url -Destination $OutFile -ErrorAction Stop
            if (Test-Path $OutFile) { return }
        } catch { Log "BITS failed: $_" 'WARN' }
    }

    # 3) Invoke-WebRequest (always available with WinPE_PowerShell)
    Log 'Downloading with Invoke-WebRequest...'
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing
}

# =========================================================================
# main
# =========================================================================
try {
    $dest    = Resolve-Destination -Dest $Destination -Cfg $Config
    $outFile = Join-Path $dest $Config.IsoFileName
    Log "Target file: $outFile"

    $url = Get-IsoUrl -Cfg $Config

    Log 'Starting download (this can take a while for a multi-GB ISO)...'
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Invoke-Fetch -Url $url -OutFile $outFile
    $sw.Stop()

    if (-not (Test-Path $outFile)) { throw 'Download reported success but file is missing.' }
    $sizeGB = [math]::Round((Get-Item $outFile).Length / 1GB, 2)
    Log ("Download complete: {0} ({1} GB) in {2:n0} min." -f $outFile, $sizeGB, $sw.Elapsed.TotalMinutes)
    exit 0
}
catch {
    Log "Download failed: $_" 'ERROR'
    exit 1
}
