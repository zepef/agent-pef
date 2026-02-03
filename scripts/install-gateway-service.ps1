#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Installs peflaptopbot gateway as a Windows service using NSSM.

.DESCRIPTION
    This script downloads NSSM (if needed) and creates a Windows service
    for the clawdbot gateway that auto-restarts on crash and starts on boot.

.EXAMPLE
    .\install-gateway-service.ps1
#>

$ErrorActionPreference = "Stop"

$ServiceName = "peflaptopbot"
$DisplayName = "PEF Laptop Bot Gateway"
$Description = "Clawdbot Telegram gateway for @peflaptopbot"
$GatewayPort = 18790
$NssmPath = "C:\tools\nssm-2.24\win64\nssm.exe"
$LogDir = "$env:USERPROFILE\.clawdbot\logs"

Write-Host "=== PEF Laptop Bot Gateway Service Installer ===" -ForegroundColor Cyan

# Step 1: Download NSSM if not present
if (-not (Test-Path $NssmPath)) {
    Write-Host "`n[1/5] Downloading NSSM..." -ForegroundColor Yellow
    $nssmZip = "$env:TEMP\nssm.zip"
    Invoke-WebRequest -Uri "https://nssm.cc/release/nssm-2.24.zip" -OutFile $nssmZip

    if (-not (Test-Path "C:\tools")) {
        New-Item -ItemType Directory -Path "C:\tools" -Force | Out-Null
    }
    Expand-Archive -Path $nssmZip -DestinationPath "C:\tools" -Force
    Remove-Item $nssmZip -Force
    Write-Host "NSSM installed to C:\tools\nssm-2.24" -ForegroundColor Green
} else {
    Write-Host "`n[1/5] NSSM already installed" -ForegroundColor Green
}

# Step 2: Find clawdbot
Write-Host "`n[2/5] Locating clawdbot..." -ForegroundColor Yellow
$clawdbotCmd = Get-Command clawdbot -ErrorAction SilentlyContinue
if (-not $clawdbotCmd) {
    Write-Error "clawdbot not found in PATH. Please install it first: npm install -g clawdbot"
    exit 1
}
$ClawdbotPath = $clawdbotCmd.Source
Write-Host "Found: $ClawdbotPath" -ForegroundColor Green

# Step 3: Create log directory
Write-Host "`n[3/5] Setting up log directory..." -ForegroundColor Yellow
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}
Write-Host "Logs will be written to: $LogDir" -ForegroundColor Green

# Step 4: Remove existing service if present
Write-Host "`n[4/5] Configuring service..." -ForegroundColor Yellow
$existingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($existingService) {
    Write-Host "Removing existing service..." -ForegroundColor Yellow
    & $NssmPath stop $ServiceName 2>$null
    & $NssmPath remove $ServiceName confirm
    Start-Sleep -Seconds 2
}

# Step 5: Install and configure service
Write-Host "`n[5/5] Installing service..." -ForegroundColor Yellow

# Install the service
& $NssmPath install $ServiceName $ClawdbotPath "gateway --port $GatewayPort"
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to install service"
    exit 1
}

# Configure service properties
& $NssmPath set $ServiceName AppDirectory $env:USERPROFILE
& $NssmPath set $ServiceName DisplayName $DisplayName
& $NssmPath set $ServiceName Description $Description
& $NssmPath set $ServiceName Start SERVICE_AUTO_START
& $NssmPath set $ServiceName AppStdout "$LogDir\gateway.log"
& $NssmPath set $ServiceName AppStderr "$LogDir\gateway-error.log"
& $NssmPath set $ServiceName AppStdoutCreationDisposition 4
& $NssmPath set $ServiceName AppStderrCreationDisposition 4
& $NssmPath set $ServiceName AppRotateFiles 1
& $NssmPath set $ServiceName AppRotateBytes 1048576

# Configure restart on failure
& $NssmPath set $ServiceName AppExit Default Restart
& $NssmPath set $ServiceName AppRestartDelay 5000

Write-Host "`nService installed successfully!" -ForegroundColor Green

# Start the service
Write-Host "`nStarting service..." -ForegroundColor Yellow
& $NssmPath start $ServiceName
Start-Sleep -Seconds 3

# Check status
$svc = Get-Service -Name $ServiceName
Write-Host "`n=== Service Status ===" -ForegroundColor Cyan
Write-Host "Name: $ServiceName"
Write-Host "Status: $($svc.Status)"
Write-Host "Startup: $($svc.StartType)"

Write-Host "`n=== Useful Commands ===" -ForegroundColor Cyan
Write-Host "Check status:  nssm status $ServiceName"
Write-Host "View logs:     Get-Content $LogDir\gateway.log -Tail 50"
Write-Host "Restart:       nssm restart $ServiceName"
Write-Host "Stop:          nssm stop $ServiceName"
Write-Host "Uninstall:     nssm remove $ServiceName confirm"

Write-Host "`nNote: Add C:\tools\nssm-2.24\win64 to your PATH for easier access" -ForegroundColor DarkGray
