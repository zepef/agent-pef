<#
.SYNOPSIS
    Install OpenClawd as a Windows service using NSSM

.DESCRIPTION
    Creates a Windows service that runs the OpenClawd orchestrator for a specific profile.
    The service will:
    - Auto-start on Windows boot
    - Auto-restart on crash (via NSSM)
    - Run as the current user

.PARAMETER Profile
    The profile name to install as a service (required)

.PARAMETER NssmPath
    Path to NSSM executable (optional - will auto-download if not found)

.EXAMPLE
    .\install-openclawd-service.ps1 -Profile peflaptopbot
#>

#Requires -Version 5.1
#Requires -RunAsAdministrator

param(
    [Parameter(Mandatory = $true)]
    [string]$Profile,

    [string]$NssmPath = $null
)

$ErrorActionPreference = "Stop"

# Configuration
$ServicePrefix = "openclawd"
$ServiceName = "$ServicePrefix-$Profile"
$NssmUrl = "https://nssm.cc/release/nssm-2.24.zip"
$NssmDir = Join-Path $env:ProgramData "nssm"

# Import library to verify profile exists
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir "openclawd-lib.ps1")

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  OpenClawd Service Installer          " -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Verify profile exists
if (-not (Test-ProfileExists $Profile)) {
    Write-Host "Profile '$Profile' not found!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Available profiles:" -ForegroundColor Yellow
    Get-AllProfiles | ForEach-Object { Write-Host "  - $($_.Name)" }
    Write-Host ""
    Write-Host "Create a profile first: .\openclawd.ps1 create-profile" -ForegroundColor Gray
    exit 1
}

Write-Host "Profile: $Profile" -ForegroundColor White
Write-Host "Service: $ServiceName" -ForegroundColor White
Write-Host ""

# Find or download NSSM
function Get-NssmExecutable {
    # Check if already provided
    if ($NssmPath -and (Test-Path $NssmPath)) {
        return $NssmPath
    }

    # Check common locations
    $commonPaths = @(
        (Join-Path $NssmDir "nssm.exe"),
        (Join-Path $NssmDir "nssm-2.24\win64\nssm.exe"),
        "C:\tools\nssm\nssm.exe",
        (Get-Command nssm -ErrorAction SilentlyContinue)?.Source
    )

    foreach ($path in $commonPaths) {
        if ($path -and (Test-Path $path)) {
            return $path
        }
    }

    # Download NSSM
    Write-Host "NSSM not found, downloading..." -ForegroundColor Yellow

    if (-not (Test-Path $NssmDir)) {
        New-Item -ItemType Directory -Path $NssmDir -Force | Out-Null
    }

    $zipPath = Join-Path $NssmDir "nssm.zip"

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $NssmUrl -OutFile $zipPath -UseBasicParsing

        Expand-Archive -Path $zipPath -DestinationPath $NssmDir -Force
        Remove-Item $zipPath -Force

        $nssmExe = Join-Path $NssmDir "nssm-2.24\win64\nssm.exe"
        if (Test-Path $nssmExe) {
            Write-Host "NSSM downloaded successfully" -ForegroundColor Green
            return $nssmExe
        }
    } catch {
        Write-Host "Failed to download NSSM: $_" -ForegroundColor Red
        Write-Host ""
        Write-Host "Please download NSSM manually from https://nssm.cc/download" -ForegroundColor Yellow
        exit 1
    }

    throw "NSSM not found after download"
}

$nssm = Get-NssmExecutable
Write-Host "Using NSSM: $nssm" -ForegroundColor Gray
Write-Host ""

# Check if service already exists
$existingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($existingService) {
    Write-Host "Service '$ServiceName' already exists." -ForegroundColor Yellow
    $response = Read-Host "Remove and reinstall? (y/N)"
    if ($response -ne 'y') {
        Write-Host "Cancelled." -ForegroundColor Gray
        exit 0
    }

    Write-Host "Removing existing service..." -ForegroundColor Cyan

    # Stop if running
    if ($existingService.Status -eq 'Running') {
        & $nssm stop $ServiceName
        Start-Sleep -Seconds 2
    }

    # Remove
    & $nssm remove $ServiceName confirm
    Start-Sleep -Seconds 1
}

# Build paths
$openclawd = Join-Path $scriptDir "openclawd.ps1"
$logDir = Join-Path $env:USERPROFILE ".clawdbot\logs\$Profile"
$stdoutLog = Join-Path $logDir "service-stdout.log"
$stderrLog = Join-Path $logDir "service-stderr.log"

# Ensure log directory exists
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

Write-Host "Installing service..." -ForegroundColor Cyan

# Install service
& $nssm install $ServiceName powershell.exe
if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to install service!" -ForegroundColor Red
    exit 1
}

# Configure service
Write-Host "Configuring service..." -ForegroundColor Cyan

# Application parameters
& $nssm set $ServiceName AppParameters "-NoProfile -ExecutionPolicy Bypass -File `"$openclawd`" start $Profile"

# Working directory
& $nssm set $ServiceName AppDirectory $scriptDir

# Logging
& $nssm set $ServiceName AppStdout $stdoutLog
& $nssm set $ServiceName AppStderr $stderrLog
& $nssm set $ServiceName AppStdoutCreationDisposition 4
& $nssm set $ServiceName AppStderrCreationDisposition 4
& $nssm set $ServiceName AppRotateFiles 1
& $nssm set $ServiceName AppRotateBytes 10485760

# Startup type
& $nssm set $ServiceName Start SERVICE_AUTO_START

# Restart on failure
& $nssm set $ServiceName AppExit Default Restart
& $nssm set $ServiceName AppRestartDelay 5000

# Description
& $nssm set $ServiceName Description "OpenClawd Telegram Bot Orchestrator - Profile: $Profile"
& $nssm set $ServiceName DisplayName "OpenClawd - $Profile"

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Service Installed Successfully!      " -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Service Name:    $ServiceName" -ForegroundColor White
Write-Host "Display Name:    OpenClawd - $Profile" -ForegroundColor White
Write-Host "Startup Type:    Automatic" -ForegroundColor White
Write-Host ""
Write-Host "Service Logs:" -ForegroundColor Yellow
Write-Host "  Stdout: $stdoutLog" -ForegroundColor Gray
Write-Host "  Stderr: $stderrLog" -ForegroundColor Gray
Write-Host ""
Write-Host "Commands:" -ForegroundColor Yellow
Write-Host "  nssm start $ServiceName    - Start service" -ForegroundColor Gray
Write-Host "  nssm stop $ServiceName     - Stop service" -ForegroundColor Gray
Write-Host "  nssm restart $ServiceName  - Restart service" -ForegroundColor Gray
Write-Host "  nssm status $ServiceName   - Check status" -ForegroundColor Gray
Write-Host ""

# Ask to start now
$startNow = Read-Host "Start service now? (Y/n)"
if ($startNow -ne 'n') {
    Write-Host ""
    Write-Host "Starting service..." -ForegroundColor Cyan
    & $nssm start $ServiceName

    Start-Sleep -Seconds 3

    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($service -and $service.Status -eq 'Running') {
        Write-Host "Service started successfully!" -ForegroundColor Green
    } else {
        Write-Host "Service may have failed to start. Check logs:" -ForegroundColor Yellow
        Write-Host "  $stderrLog" -ForegroundColor Gray
    }
}

Write-Host ""
