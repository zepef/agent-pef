#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Uninstalls the peflaptopbot gateway Windows service.

.EXAMPLE
    .\uninstall-gateway-service.ps1
#>

$ErrorActionPreference = "Stop"

$ServiceName = "peflaptopbot"
$NssmPath = "C:\tools\nssm-2.24\win64\nssm.exe"

Write-Host "=== PEF Laptop Bot Gateway Service Uninstaller ===" -ForegroundColor Cyan

if (-not (Test-Path $NssmPath)) {
    Write-Error "NSSM not found at $NssmPath"
    exit 1
}

$existingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if (-not $existingService) {
    Write-Host "Service '$ServiceName' is not installed." -ForegroundColor Yellow
    exit 0
}

Write-Host "`nStopping service..." -ForegroundColor Yellow
& $NssmPath stop $ServiceName 2>$null
Start-Sleep -Seconds 2

Write-Host "Removing service..." -ForegroundColor Yellow
& $NssmPath remove $ServiceName confirm

Write-Host "`nService uninstalled successfully!" -ForegroundColor Green
Write-Host "Log files remain at: $env:USERPROFILE\.clawdbot\logs" -ForegroundColor DarkGray
