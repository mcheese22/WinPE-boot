@echo off
rem =====================================================================
rem  startnet.cmd -- runs automatically when WinPE boots.
rem  Replaces the default startnet.cmd inside \Windows\System32 of the
rem  WinPE image (Build-WinPE.ps1 does this for you).
rem =====================================================================

rem --- Bring up hardware + networking (DHCP) ---------------------------
echo [WinPE] Initializing (wpeinit)...
wpeinit

rem --- Hand off to the PowerShell orchestrator -------------------------
rem  All kit files are copied to the root of the WinPE RAM drive (X:\).
echo [WinPE] Launching automation...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File X:\Automate.ps1

rem --- If the automation exits, leave the user at a prompt -------------
echo.
echo [WinPE] Automation finished. You are now at the WinPE command prompt.
echo         Log file: X:\winpe-auto.log
cmd.exe
