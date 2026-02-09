<#
.SYNOPSIS
    Uninstall OpenClawd Windows service

.DESCRIPTION
    Gracefully stops and removes the OpenClawd Windows service for a specific profile.

.PARAMETER Profile
    The profile name to uninstall (required)

.EXAMPLE
    .\uninstall-openclawd-service.ps1 -Profile peflaptopbot
#>

#Requires -Version 5.1
#Requires -RunAsAdministrator

param(
    [Parameter(Mandatory = $true)]
    [string]$Profile
)

$ErrorActionPreference = "Stop"

$ServiceName = "openclawd-$Profile"
$NssmDir = Join-Path $env:ProgramData "nssm"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  OpenClawd Service Uninstaller        " -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Find NSSM
$nssm = $null
$nssmPaths = @(
    (Join-Path $NssmDir "nssm.exe"),
    (Join-Path $NssmDir "nssm-2.24\win64\nssm.exe"),
    "C:\tools\nssm\nssm.exe",
    (Get-Command nssm -ErrorAction SilentlyContinue)?.Source
)

foreach ($path in $nssmPaths) {
    if ($path -and (Test-Path $path)) {
        $nssm = $path
        break
    }
}

if (-not $nssm) {
    Write-Host "NSSM not found. Cannot uninstall service." -ForegroundColor Red
    Write-Host ""
    Write-Host "Try removing manually with sc.exe:" -ForegroundColor Yellow
    Write-Host "  sc.exe stop $ServiceName" -ForegroundColor Gray
    Write-Host "  sc.exe delete $ServiceName" -ForegroundColor Gray
    exit 1
}

# Check if service exists
$service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if (-not $service) {
    Write-Host "Service '$ServiceName' not found." -ForegroundColor Yellow
    Write-Host ""

    # List any openclawd services
    $otherServices = Get-Service -Name "openclawd-*" -ErrorAction SilentlyContinue
    if ($otherServices) {
        Write-Host "Available OpenClawd services:" -ForegroundColor Yellow
        $otherServices | ForEach-Object {
            Write-Host "  - $($_.Name) [$($_.Status)]" -ForegroundColor White
        }
    }
    exit 0
}

Write-Host "Service: $ServiceName" -ForegroundColor White
Write-Host "Status:  $($service.Status)" -ForegroundColor White
Write-Host ""

# Confirm
$confirm = Read-Host "Remove this service? (y/N)"
if ($confirm -ne 'y') {
    Write-Host "Cancelled." -ForegroundColor Gray
    exit 0
}

# Stop if running
if ($service.Status -eq 'Running') {
    Write-Host "Stopping service..." -ForegroundColor Cyan
    & $nssm stop $ServiceName

    # Wait for stop
    $timeout = 30
    $waited = 0
    while ($waited -lt $timeout) {
        $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if ($service.Status -ne 'Running') { break }
        Start-Sleep -Seconds 1
        $waited++
    }

    if ($service.Status -eq 'Running') {
        Write-Host "Service didn't stop gracefully, forcing..." -ForegroundColor Yellow
        Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
    }
}

# Remove service
Write-Host "Removing service..." -ForegroundColor Cyan
& $nssm remove $ServiceName confirm

Start-Sleep -Seconds 1

# Verify removal
$service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if (-not $service) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  Service Removed Successfully!        " -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
} else {
    Write-Host ""
    Write-Host "Service may not have been fully removed." -ForegroundColor Yellow
    Write-Host "Try restarting Windows or removing manually:" -ForegroundColor Gray
    Write-Host "  sc.exe delete $ServiceName" -ForegroundColor Gray
    Write-Host ""
}
