<#
.SYNOPSIS
    OpenClawd Orchestrator - CLI for managing Clawdbot with Cloudflare Tunnels

.DESCRIPTION
    Manages the complete lifecycle of a Clawdbot instance including:
    - Cloudflare Tunnel management (auto URL detection)
    - Dynamic config generation
    - Telegram webhook registration
    - Health monitoring with auto-recovery
    - Multi-profile support

.PARAMETER Command
    The command to execute: start, stop, restart, status, health, logs, profiles, create-profile

.PARAMETER Profile
    The profile name to use (default: peflaptopbot or $env:OPENCLAWD_PROFILE)

.EXAMPLE
    .\openclawd.ps1 start peflaptopbot
    .\openclawd.ps1 status
    .\openclawd.ps1 stop peflaptopbot
#>

#Requires -Version 5.1

param(
    [Parameter(Position = 0)]
    [ValidateSet("start", "stop", "restart", "status", "health", "logs", "profiles", "create-profile", "health-monitor")]
    [string]$Command = "status",

    [Parameter(Position = 1)]
    [string]$Profile = $null
)

$ErrorActionPreference = "Stop"

# Import library
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir "openclawd-lib.ps1")

# Initialize
Initialize-ClawdbotDirectories

# Default profile
if (-not $Profile) {
    $Profile = $script:DefaultProfile
}

# ============================================================================
# Command: start
# ============================================================================

function Start-Orchestrator {
    param([string]$ProfileName)

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  OpenClawd Orchestrator - Starting    " -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    # Check if already running
    $status = Get-OrchestratorStatus -ProfileName $ProfileName
    if ($status.IsRunning) {
        Write-Host "Profile '$ProfileName' is already running!" -ForegroundColor Yellow
        Write-Host "Tunnel URL: $($status.TunnelUrl)" -ForegroundColor Green
        Write-Host ""
        Write-Host "Use 'openclawd restart $ProfileName' to restart." -ForegroundColor Gray
        return
    }

    # Load profile
    Write-Log "Loading profile: $ProfileName" -Level info -ProfileName $ProfileName
    if (-not (Test-ProfileExists $ProfileName)) {
        Write-Host "Profile '$ProfileName' not found!" -ForegroundColor Red
        Write-Host ""
        Write-Host "Available profiles:" -ForegroundColor Yellow
        Get-AllProfiles | ForEach-Object { Write-Host "  - $($_.Name)" }
        Write-Host ""
        Write-Host "Create a new profile with: openclawd create-profile" -ForegroundColor Gray
        return
    }

    $profileConfig = Get-Profile $ProfileName
    $logDir = Get-ProfileLogDir $ProfileName
    $port = if ($profileConfig.port) { $profileConfig.port } else { 18790 }
    $displayName = if ($profileConfig.displayName) { $profileConfig.displayName } else { $ProfileName }

    Write-Host "Profile: $ProfileName ($displayName)" -ForegroundColor White
    Write-Host "Port: $port" -ForegroundColor White
    Write-Host ""

    # Step 1: Start cloudflared named tunnel
    Write-Host "[1/6] Starting Cloudflare tunnel..." -ForegroundColor Cyan
    $tunnelLogFile = Join-Path $logDir "tunnel.log"
    $tunnelConfigFile = Join-Path $env:USERPROFILE ".cloudflared\config-$ProfileName.yml"

    # Clear old tunnel log
    if (Test-Path $tunnelLogFile) {
        Clear-Content $tunnelLogFile -ErrorAction SilentlyContinue
    }

    # Check if named tunnel config exists, otherwise fall back to quick tunnel
    if (Test-Path $tunnelConfigFile) {
        Write-Host "  Using named tunnel: $ProfileName.neuralnest.pro" -ForegroundColor Gray
        $tunnelProcess = Start-Process -FilePath "npx.cmd" `
            -ArgumentList "cloudflared", "tunnel", "--config", $tunnelConfigFile, "run" `
            -RedirectStandardError $tunnelLogFile `
            -WindowStyle Hidden `
            -PassThru
        $tunnelUrl = "https://$ProfileName.neuralnest.pro"
    } else {
        Write-Host "  Using quick tunnel (no named tunnel config found)" -ForegroundColor Yellow
        $tunnelProcess = Start-Process -FilePath "cloudflared.cmd" `
            -ArgumentList "tunnel", "--url", "http://localhost:$port" `
            -RedirectStandardError $tunnelLogFile `
            -WindowStyle Hidden `
            -PassThru
        $tunnelUrl = $null
    }

    Save-ProcessId -ProfileName $ProfileName -ProcessType "tunnel" -ProcessId $tunnelProcess.Id
    Write-Log "Started cloudflared with PID $($tunnelProcess.Id)" -Level info -ProfileName $ProfileName

    # Step 2: Wait for tunnel to be ready
    Write-Host "[2/6] Waiting for tunnel..." -ForegroundColor Cyan

    if (-not $tunnelUrl) {
        # Quick tunnel - need to wait for URL
        $tunnelUrl = Wait-ForTunnelUrl -LogFile $tunnelLogFile -TimeoutSeconds 60
        if (-not $tunnelUrl) {
            Write-Host "Failed to get tunnel URL within timeout!" -ForegroundColor Red
            Write-Log "Tunnel URL timeout" -Level error -ProfileName $ProfileName
            Stop-ProcessGracefully -ProcessId $tunnelProcess.Id | Out-Null
            Remove-PidFile -ProfileName $ProfileName -ProcessType "tunnel"
            return
        }
    } else {
        # Named tunnel - wait for connection
        Start-Sleep -Seconds 3
    }

    Save-TunnelUrl -ProfileName $ProfileName -TunnelUrl $tunnelUrl
    Write-Host "  Tunnel URL: $tunnelUrl" -ForegroundColor Green
    Write-Log "Tunnel URL acquired: $tunnelUrl" -Level info -ProfileName $ProfileName

    # Step 3: Generate clawdbot config
    Write-Host "[3/6] Generating clawdbot config..." -ForegroundColor Cyan
    New-ClawdbotConfig -Profile $profileConfig -TunnelUrl $tunnelUrl | Out-Null
    Write-Log "Config generated at $script:ConfigFile" -Level info -ProfileName $ProfileName

    # Step 4: Register webhook with Telegram (with retries for DNS propagation)
    Write-Host "[4/6] Registering Telegram webhook..." -ForegroundColor Cyan
    $webhookUrl = "$tunnelUrl/telegram/webhook"

    $maxRetries = 5
    $retryDelay = 10
    $webhookSet = $false

    for ($i = 1; $i -le $maxRetries; $i++) {
        try {
            $webhookSet = Set-TelegramWebhook -BotToken $profileConfig.botToken -WebhookUrl $webhookUrl
            if ($webhookSet) {
                Write-Host "  Webhook registered: $webhookUrl" -ForegroundColor Green
                Write-Log "Webhook registered: $webhookUrl" -Level info -ProfileName $ProfileName
                break
            } else {
                throw "Webhook registration returned false"
            }
        } catch {
            if ($i -lt $maxRetries) {
                Write-Host "  Attempt $i failed, waiting ${retryDelay}s for DNS propagation..." -ForegroundColor Yellow
                Start-Sleep -Seconds $retryDelay
                $retryDelay = [Math]::Min($retryDelay * 2, 60)  # Exponential backoff, max 60s
            } else {
                Write-Host "  Failed to register webhook after $maxRetries attempts: $_" -ForegroundColor Red
                Write-Log "Webhook registration failed after $maxRetries attempts: $_" -Level error -ProfileName $ProfileName
            }
        }
    }

    # Step 5: Verify webhook
    Write-Host "[5/6] Verifying webhook..." -ForegroundColor Cyan
    try {
        $webhookInfo = Get-TelegramWebhookInfo -BotToken $profileConfig.botToken
        if ($webhookInfo.url -eq $webhookUrl) {
            Write-Host "  Webhook verified!" -ForegroundColor Green
        } else {
            Write-Host "  Webhook URL mismatch: $($webhookInfo.url)" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  Could not verify webhook: $_" -ForegroundColor Yellow
    }

    # Step 6: Start gateway
    Write-Host "[6/6] Starting gateway..." -ForegroundColor Cyan
    $gatewayLogFile = Join-Path $logDir "gateway.log"

    # Clear old gateway log
    if (Test-Path $gatewayLogFile) {
        Clear-Content $gatewayLogFile -ErrorAction SilentlyContinue
    }

    $port = if ($profileConfig.port) { $profileConfig.port } else { 18790 }
    $gatewayProcess = Start-Process -FilePath "npx.cmd" `
        -ArgumentList "clawdbot", "gateway", "--port", "$port", "--bind", "lan", "--verbose", "--allow-unconfigured" `
        -RedirectStandardOutput $gatewayLogFile `
        -RedirectStandardError (Join-Path $logDir "gateway-error.log") `
        -WindowStyle Hidden `
        -PassThru

    Save-ProcessId -ProfileName $ProfileName -ProcessType "gateway" -ProcessId $gatewayProcess.Id
    Write-Log "Started gateway with PID $($gatewayProcess.Id) (port $port, bind lan)" -Level info -ProfileName $ProfileName

    # Give gateway a moment to start
    Start-Sleep -Seconds 2

    # Check if gateway is still running
    if (-not (Test-ProcessRunning $gatewayProcess.Id)) {
        Write-Host "Gateway process died immediately! Check logs:" -ForegroundColor Red
        Write-Host "  $gatewayLogFile" -ForegroundColor Yellow
        Write-Log "Gateway died immediately" -Level error -ProfileName $ProfileName
        return
    }

    Write-Host "  Gateway started (PID: $($gatewayProcess.Id))" -ForegroundColor Green

    # Start health monitor as background job
    Write-Host ""
    Write-Host "Starting health monitor..." -ForegroundColor Cyan

    $healthScript = Join-Path $scriptDir "openclawd.ps1"
    $healthProcess = Start-Process -FilePath "powershell.exe" `
        -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $healthScript, "health-monitor", $ProfileName `
        -WindowStyle Hidden `
        -PassThru

    Save-ProcessId -ProfileName $ProfileName -ProcessType "health" -ProcessId $healthProcess.Id
    Write-Log "Started health monitor with PID $($healthProcess.Id)" -Level info -ProfileName $ProfileName

    # Done!
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  OpenClawd Started Successfully!      " -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Profile:    $ProfileName" -ForegroundColor White
    Write-Host "Tunnel:     $tunnelUrl" -ForegroundColor White
    Write-Host "Webhook:    $webhookUrl" -ForegroundColor White
    Write-Host "Gateway:    http://localhost:$port" -ForegroundColor White
    Write-Host ""
    Write-Host "Logs:       $logDir" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Commands:" -ForegroundColor Yellow
    Write-Host "  .\openclawd.ps1 status $ProfileName   - Check status" -ForegroundColor Gray
    Write-Host "  .\openclawd.ps1 logs $ProfileName     - View logs" -ForegroundColor Gray
    Write-Host "  .\openclawd.ps1 stop $ProfileName     - Stop" -ForegroundColor Gray
    Write-Host ""
}

# ============================================================================
# Command: stop
# ============================================================================

function Stop-Orchestrator {
    param([string]$ProfileName)

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  OpenClawd Orchestrator - Stopping    " -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    $status = Get-OrchestratorStatus -ProfileName $ProfileName

    if (-not $status.TunnelRunning -and -not $status.GatewayRunning -and -not $status.HealthRunning) {
        Write-Host "Profile '$ProfileName' is not running." -ForegroundColor Yellow
        return
    }

    Write-Log "Stopping profile: $ProfileName" -Level info -ProfileName $ProfileName

    # Step 1: Stop health monitor
    if ($status.HealthRunning) {
        Write-Host "[1/4] Stopping health monitor..." -ForegroundColor Cyan
        Stop-ProcessGracefully -ProcessId $status.HealthPid | Out-Null
        Remove-PidFile -ProfileName $ProfileName -ProcessType "health"
        Write-Host "  Health monitor stopped" -ForegroundColor Green
    } else {
        Write-Host "[1/4] Health monitor not running" -ForegroundColor Gray
    }

    # Step 2: Delete webhook
    Write-Host "[2/4] Deleting Telegram webhook..." -ForegroundColor Cyan
    try {
        if (Test-ProfileExists $ProfileName) {
            $profileConfig = Get-Profile $ProfileName
            $deleted = Remove-TelegramWebhook -BotToken $profileConfig.botToken
            if ($deleted) {
                Write-Host "  Webhook deleted" -ForegroundColor Green
                Write-Log "Webhook deleted" -Level info -ProfileName $ProfileName
            }
        }
    } catch {
        Write-Host "  Could not delete webhook: $_" -ForegroundColor Yellow
    }

    # Step 3: Stop gateway
    if ($status.GatewayRunning) {
        Write-Host "[3/4] Stopping gateway..." -ForegroundColor Cyan
        Stop-ProcessGracefully -ProcessId $status.GatewayPid -TimeoutSeconds 10 | Out-Null
        Remove-PidFile -ProfileName $ProfileName -ProcessType "gateway"
        Write-Host "  Gateway stopped" -ForegroundColor Green
    } else {
        Write-Host "[3/4] Gateway not running" -ForegroundColor Gray
    }

    # Step 4: Stop tunnel
    if ($status.TunnelRunning) {
        Write-Host "[4/4] Stopping cloudflared tunnel..." -ForegroundColor Cyan
        Stop-ProcessGracefully -ProcessId $status.TunnelPid -TimeoutSeconds 5 | Out-Null
        Remove-PidFile -ProfileName $ProfileName -ProcessType "tunnel"
        Remove-TunnelUrlFile -ProfileName $ProfileName
        Write-Host "  Tunnel stopped" -ForegroundColor Green
    } else {
        Write-Host "[4/4] Tunnel not running" -ForegroundColor Gray
    }

    Write-Log "Profile stopped: $ProfileName" -Level info -ProfileName $ProfileName

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  OpenClawd Stopped                    " -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
}

# ============================================================================
# Command: restart
# ============================================================================

function Restart-Orchestrator {
    param([string]$ProfileName)

    Write-Host "Restarting profile: $ProfileName" -ForegroundColor Cyan
    Write-Host ""

    Stop-Orchestrator -ProfileName $ProfileName

    Start-Sleep -Seconds 2

    Start-Orchestrator -ProfileName $ProfileName
}

# ============================================================================
# Command: status
# ============================================================================

function Show-Status {
    param([string]$ProfileName)

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  OpenClawd Status                     " -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    if (-not (Test-ProfileExists $ProfileName)) {
        Write-Host "Profile '$ProfileName' not found!" -ForegroundColor Red
        Write-Host ""
        Show-Profiles
        return
    }

    $status = Get-OrchestratorStatus -ProfileName $ProfileName
    $profileConfig = Get-Profile $ProfileName

    # Profile info
    Write-Host "Profile" -ForegroundColor Yellow
    Write-Host "  Name:         $ProfileName" -ForegroundColor White
    $displayName = if ($profileConfig.displayName) { $profileConfig.displayName } else { $ProfileName }
    $port = if ($profileConfig.port) { $profileConfig.port } else { 18790 }
    Write-Host "  Display Name: $displayName" -ForegroundColor White
    Write-Host "  Port:         $port" -ForegroundColor White
    Write-Host ""

    # Process status
    Write-Host "Processes" -ForegroundColor Yellow

    $tunnelStatus = if ($status.TunnelRunning) { "Running (PID: $($status.TunnelPid))" } else { "Stopped" }
    $tunnelColor = if ($status.TunnelRunning) { "Green" } else { "Red" }
    Write-Host "  Tunnel:       $tunnelStatus" -ForegroundColor $tunnelColor

    $gatewayStatus = if ($status.GatewayRunning) { "Running (PID: $($status.GatewayPid))" } else { "Stopped" }
    $gatewayColor = if ($status.GatewayRunning) { "Green" } else { "Red" }
    Write-Host "  Gateway:      $gatewayStatus" -ForegroundColor $gatewayColor

    $healthStatus = if ($status.HealthRunning) { "Running (PID: $($status.HealthPid))" } else { "Stopped" }
    $healthColor = if ($status.HealthRunning) { "Green" } else { "Gray" }
    Write-Host "  Health:       $healthStatus" -ForegroundColor $healthColor

    Write-Host ""

    # Tunnel URL
    if ($status.TunnelUrl) {
        Write-Host "Tunnel" -ForegroundColor Yellow
        Write-Host "  URL:          $($status.TunnelUrl)" -ForegroundColor Green
        Write-Host "  Webhook:      $($status.TunnelUrl)/telegram-webhook" -ForegroundColor White

        # Check tunnel health
        if ($status.TunnelRunning) {
            $tunnelHealthy = Test-TunnelHealth -TunnelUrl $status.TunnelUrl
            $healthText = if ($tunnelHealthy) { "Healthy" } else { "Unreachable" }
            $healthColor = if ($tunnelHealthy) { "Green" } else { "Red" }
            Write-Host "  Health:       $healthText" -ForegroundColor $healthColor
        }
        Write-Host ""
    }

    # Webhook status
    if ($status.IsRunning) {
        Write-Host "Webhook" -ForegroundColor Yellow
        try {
            $webhookInfo = Get-TelegramWebhookInfo -BotToken $profileConfig.botToken
            $expectedUrl = "$($status.TunnelUrl)/telegram-webhook"
            $urlMatch = $webhookInfo.url -eq $expectedUrl

            Write-Host "  Registered:   $($webhookInfo.url)" -ForegroundColor $(if ($urlMatch) { "Green" } else { "Yellow" })
            if (-not $urlMatch -and $webhookInfo.url) {
                Write-Host "  Expected:     $expectedUrl" -ForegroundColor Gray
            }
            if ($webhookInfo.last_error_message) {
                Write-Host "  Last Error:   $($webhookInfo.last_error_message)" -ForegroundColor Red
                Write-Host "  Error Date:   $([DateTimeOffset]::FromUnixTimeSeconds($webhookInfo.last_error_date).LocalDateTime)" -ForegroundColor Gray
            }
            if ($webhookInfo.pending_update_count -gt 0) {
                Write-Host "  Pending:      $($webhookInfo.pending_update_count) updates" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "  Could not fetch webhook info: $_" -ForegroundColor Yellow
        }
        Write-Host ""
    }

    # Overall status
    $overallStatus = if ($status.IsRunning) { "RUNNING" } else { "STOPPED" }
    $overallColor = if ($status.IsRunning) { "Green" } else { "Red" }
    Write-Host "Overall Status: " -NoNewline
    Write-Host $overallStatus -ForegroundColor $overallColor
    Write-Host ""
}

# ============================================================================
# Command: health
# ============================================================================

function Test-Health {
    param([string]$ProfileName)

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  OpenClawd Health Check               " -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    if (-not (Test-ProfileExists $ProfileName)) {
        Write-Host "Profile '$ProfileName' not found!" -ForegroundColor Red
        return
    }

    $profileConfig = Get-Profile $ProfileName
    $status = Get-OrchestratorStatus -ProfileName $ProfileName
    $tunnelUrl = Get-SavedTunnelUrl -ProfileName $ProfileName

    $checks = @()
    $allPassed = $true

    # -------------------------------------------------------------------------
    # Check 1: Profile Configuration
    # -------------------------------------------------------------------------
    Write-Host "[1/7] Profile Configuration" -ForegroundColor Yellow
    $profileCheck = @{
        Name = "Profile Configuration"
        Passed = $true
        Details = @()
    }

    if ($profileConfig.botToken -and $profileConfig.botToken -match '^\d+:') {
        $profileCheck.Details += "  Bot token: Valid format"
    } else {
        $profileCheck.Passed = $false
        $profileCheck.Details += "  Bot token: INVALID or missing"
    }

    if ($profileConfig.port -gt 0 -and $profileConfig.port -lt 65536) {
        $profileCheck.Details += "  Port: $($profileConfig.port)"
    } else {
        $profileCheck.Passed = $false
        $profileCheck.Details += "  Port: INVALID ($($profileConfig.port))"
    }

    $checks += $profileCheck
    Write-HealthCheck $profileCheck

    # -------------------------------------------------------------------------
    # Check 2: Tunnel Process
    # -------------------------------------------------------------------------
    Write-Host "[2/7] Tunnel Process" -ForegroundColor Yellow
    $tunnelProcCheck = @{
        Name = "Tunnel Process"
        Passed = $status.TunnelRunning
        Details = @()
    }

    if ($status.TunnelRunning) {
        $tunnelProcCheck.Details += "  Process: Running (PID: $($status.TunnelPid))"
    } else {
        $tunnelProcCheck.Details += "  Process: NOT RUNNING"
    }

    $checks += $tunnelProcCheck
    Write-HealthCheck $tunnelProcCheck

    # -------------------------------------------------------------------------
    # Check 3: Tunnel URL Configured
    # -------------------------------------------------------------------------
    Write-Host "[3/7] Tunnel URL Configuration" -ForegroundColor Yellow
    $tunnelUrlCheck = @{
        Name = "Tunnel URL Configuration"
        Passed = $false
        Details = @()
    }

    if ($tunnelUrl) {
        $tunnelUrlCheck.Passed = $true
        $tunnelUrlCheck.Details += "  URL: $tunnelUrl"

        # Check if URL matches expected pattern
        if ($tunnelUrl -match 'https://[a-zA-Z0-9-]+\.trycloudflare\.com') {
            $tunnelUrlCheck.Details += "  Format: Valid Cloudflare tunnel URL"
        } else {
            $tunnelUrlCheck.Passed = $false
            $tunnelUrlCheck.Details += "  Format: UNEXPECTED URL format"
        }
    } else {
        $tunnelUrlCheck.Details += "  URL: NOT CONFIGURED"
    }

    $checks += $tunnelUrlCheck
    Write-HealthCheck $tunnelUrlCheck

    # -------------------------------------------------------------------------
    # Check 4: Tunnel Reachability
    # -------------------------------------------------------------------------
    Write-Host "[4/7] Tunnel Reachability" -ForegroundColor Yellow
    $tunnelReachCheck = @{
        Name = "Tunnel Reachability"
        Passed = $false
        Details = @()
    }

    if ($tunnelUrl) {
        try {
            $response = Invoke-WebRequest -Uri $tunnelUrl -Method GET -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
            $tunnelReachCheck.Passed = $true
            $tunnelReachCheck.Details += "  HTTP GET: $($response.StatusCode) OK"
        } catch {
            if ($_.Exception.Response.StatusCode -eq 405) {
                # Method Not Allowed is OK - means tunnel is working
                $tunnelReachCheck.Passed = $true
                $tunnelReachCheck.Details += "  HTTP GET: 405 (Method Not Allowed - tunnel is alive)"
            } elseif ($_.Exception.Response.StatusCode) {
                $tunnelReachCheck.Details += "  HTTP GET: $($_.Exception.Response.StatusCode)"
                $tunnelReachCheck.Details += "  Note: Non-200 response but tunnel is reachable"
                $tunnelReachCheck.Passed = $true
            } else {
                $tunnelReachCheck.Details += "  HTTP GET: FAILED - $($_.Exception.Message)"
            }
        }

        # Also test webhook endpoint
        $webhookEndpoint = "$tunnelUrl/telegram-webhook"
        try {
            $response = Invoke-WebRequest -Uri $webhookEndpoint -Method GET -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
            $tunnelReachCheck.Details += "  Webhook endpoint: Reachable ($($response.StatusCode))"
        } catch {
            if ($_.Exception.Response.StatusCode) {
                $tunnelReachCheck.Details += "  Webhook endpoint: Reachable ($($_.Exception.Response.StatusCode))"
            } else {
                $tunnelReachCheck.Details += "  Webhook endpoint: UNREACHABLE"
                $tunnelReachCheck.Passed = $false
            }
        }
    } else {
        $tunnelReachCheck.Details += "  Skipped: No tunnel URL configured"
    }

    $checks += $tunnelReachCheck
    Write-HealthCheck $tunnelReachCheck

    # -------------------------------------------------------------------------
    # Check 5: Tunnel Log Errors
    # -------------------------------------------------------------------------
    Write-Host "[5/8] Tunnel Log Errors" -ForegroundColor Yellow
    $tunnelLogCheck = @{
        Name = "Tunnel Log Errors"
        Passed = $true
        Details = @()
    }

    $tunnelLogErrors = Get-TunnelLogErrors -ProfileName $ProfileName -LookbackSeconds 120
    if ($tunnelLogErrors) {
        if ($tunnelLogErrors.HasErrors) {
            $tunnelLogCheck.Passed = $false
            $tunnelLogCheck.Details += "  Recent Errors: $($tunnelLogErrors.ErrorCount) in last 2 minutes"
            if ($tunnelLogErrors.LastError) {
                $lastErrTime = $tunnelLogErrors.LastError.Time.ToString("HH:mm:ss")
                $tunnelLogCheck.Details += "  Last Error Time: $lastErrTime"
                # Extract error message (truncate if too long)
                $errMsg = $tunnelLogErrors.LastError.Message
                if ($errMsg.Length -gt 80) {
                    $errMsg = $errMsg.Substring(0, 77) + "..."
                }
                $tunnelLogCheck.Details += "  Last Error: $errMsg"
            }
            $tunnelLogCheck.Details += "  Note: Errors like 'control stream failure' trigger auto-recovery"
        } else {
            $tunnelLogCheck.Details += "  No recent errors detected"
        }
    } else {
        $tunnelLogCheck.Details += "  Could not read tunnel log"
    }

    $checks += $tunnelLogCheck
    Write-HealthCheck $tunnelLogCheck

    # -------------------------------------------------------------------------
    # Check 6: Gateway Process
    # -------------------------------------------------------------------------
    Write-Host "[6/8] Gateway Process" -ForegroundColor Yellow
    $gatewayCheck = @{
        Name = "Gateway Process"
        Passed = $status.GatewayRunning
        Details = @()
    }

    if ($status.GatewayRunning) {
        $gatewayCheck.Details += "  Process: Running (PID: $($status.GatewayPid))"

        # Check if gateway is listening on port
        $port = if ($profileConfig.port) { $profileConfig.port } else { 18790 }
        try {
            $listening = netstat -ano | Select-String ":$port\s"
            if ($listening) {
                $gatewayCheck.Details += "  Port $port`: Listening"
            } else {
                $gatewayCheck.Details += "  Port $port`: NOT listening (gateway may still be starting)"
            }
        } catch {
            $gatewayCheck.Details += "  Port check: Could not verify"
        }
    } else {
        $gatewayCheck.Details += "  Process: NOT RUNNING"
    }

    $checks += $gatewayCheck
    Write-HealthCheck $gatewayCheck

    # -------------------------------------------------------------------------
    # Check 7: Telegram Webhook
    # -------------------------------------------------------------------------
    Write-Host "[7/8] Telegram Webhook" -ForegroundColor Yellow
    $webhookCheck = @{
        Name = "Telegram Webhook"
        Passed = $false
        Details = @()
    }

    try {
        $webhookInfo = Get-TelegramWebhookInfo -BotToken $profileConfig.botToken
        $expectedUrl = if ($tunnelUrl) { "$tunnelUrl/telegram-webhook" } else { $null }

        if ($webhookInfo.url) {
            $webhookCheck.Details += "  Registered URL: $($webhookInfo.url)"

            if ($expectedUrl -and $webhookInfo.url -eq $expectedUrl) {
                $webhookCheck.Passed = $true
                $webhookCheck.Details += "  URL Match: YES - webhook matches tunnel"
            } elseif ($expectedUrl) {
                $webhookCheck.Details += "  URL Match: NO - expected: $expectedUrl"
                $webhookCheck.Details += "  Action: Run 'openclawd restart $ProfileName' to fix"
            } else {
                $webhookCheck.Details += "  URL Match: Cannot verify (no tunnel URL)"
            }

            if ($webhookInfo.last_error_message) {
                $webhookCheck.Passed = $false
                $errorDate = [DateTimeOffset]::FromUnixTimeSeconds($webhookInfo.last_error_date).LocalDateTime
                $webhookCheck.Details += "  Last Error: $($webhookInfo.last_error_message)"
                $webhookCheck.Details += "  Error Time: $errorDate"
            }

            if ($webhookInfo.pending_update_count -gt 0) {
                $webhookCheck.Details += "  Pending Updates: $($webhookInfo.pending_update_count)"
            }
        } else {
            $webhookCheck.Details += "  Registered URL: NONE"
            $webhookCheck.Details += "  Action: Start the orchestrator to register webhook"
        }
    } catch {
        $webhookCheck.Details += "  API Call: FAILED - $($_.Exception.Message)"
    }

    $checks += $webhookCheck
    Write-HealthCheck $webhookCheck

    # -------------------------------------------------------------------------
    # Check 8: Health Monitor
    # -------------------------------------------------------------------------
    Write-Host "[8/8] Health Monitor" -ForegroundColor Yellow
    $healthMonCheck = @{
        Name = "Health Monitor"
        Passed = $status.HealthRunning
        Details = @()
    }

    if ($status.HealthRunning) {
        $healthMonCheck.Details += "  Process: Running (PID: $($status.HealthPid))"
        $healthMonCheck.Details += "  Check Interval: $($script:DefaultHealthInterval) seconds"
    } else {
        $healthMonCheck.Passed = $false
        $healthMonCheck.Details += "  Process: NOT RUNNING"
        $healthMonCheck.Details += "  Note: Auto-recovery is disabled without health monitor"
    }

    $checks += $healthMonCheck
    Write-HealthCheck $healthMonCheck

    # -------------------------------------------------------------------------
    # Summary
    # -------------------------------------------------------------------------
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Summary                              " -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    $passed = ($checks | Where-Object { $_.Passed }).Count
    $failed = ($checks | Where-Object { -not $_.Passed }).Count
    $total = $checks.Count

    Write-Host "Checks Passed: " -NoNewline
    Write-Host "$passed/$total" -ForegroundColor $(if ($passed -eq $total) { "Green" } else { "Yellow" })

    if ($failed -gt 0) {
        Write-Host ""
        Write-Host "Failed Checks:" -ForegroundColor Red
        $checks | Where-Object { -not $_.Passed } | ForEach-Object {
            Write-Host "  - $($_.Name)" -ForegroundColor Red
        }
    }

    Write-Host ""

    # Overall verdict
    $allPassed = ($failed -eq 0)

    if ($allPassed) {
        Write-Host "HEALTH STATUS: " -NoNewline
        Write-Host "HEALTHY" -ForegroundColor Green
        Write-Host ""
        Write-Host "All systems operational. Bot should be receiving messages." -ForegroundColor Gray
    } elseif ($status.IsRunning -and $passed -ge 6) {
        Write-Host "HEALTH STATUS: " -NoNewline
        Write-Host "DEGRADED" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Bot is running but some checks failed. Review details above." -ForegroundColor Gray
    } else {
        Write-Host "HEALTH STATUS: " -NoNewline
        Write-Host "UNHEALTHY" -ForegroundColor Red
        Write-Host ""
        Write-Host "Bot is not operational. Run 'openclawd start $ProfileName' to start." -ForegroundColor Gray
    }

    Write-Host ""

    # Return result for scripting
    return $allPassed
}

function Write-HealthCheck {
    param([hashtable]$Check)

    $statusIcon = if ($Check.Passed) { "[PASS]" } else { "[FAIL]" }
    $statusColor = if ($Check.Passed) { "Green" } else { "Red" }

    Write-Host "  $statusIcon" -ForegroundColor $statusColor -NoNewline
    Write-Host " $($Check.Name)" -ForegroundColor White

    foreach ($detail in $Check.Details) {
        Write-Host $detail -ForegroundColor Gray
    }
    Write-Host ""
}

# ============================================================================
# Command: logs
# ============================================================================

function Show-Logs {
    param([string]$ProfileName)

    $logDir = Get-ProfileLogDir $ProfileName

    Write-Host ""
    Write-Host "Log directory: $logDir" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Available logs:" -ForegroundColor Yellow

    $logFiles = @("orchestrator.log", "gateway.log", "tunnel.log", "gateway-error.log")
    foreach ($logFile in $logFiles) {
        $fullPath = Join-Path $logDir $logFile
        if (Test-Path $fullPath) {
            $size = (Get-Item $fullPath).Length
            $sizeStr = if ($size -gt 1MB) { "{0:N1} MB" -f ($size / 1MB) }
                       elseif ($size -gt 1KB) { "{0:N1} KB" -f ($size / 1KB) }
                       else { "$size bytes" }
            Write-Host "  - $logFile ($sizeStr)" -ForegroundColor White
        }
    }

    Write-Host ""
    Write-Host "Tailing orchestrator.log (Ctrl+C to exit)..." -ForegroundColor Yellow
    Write-Host "-------------------------------------------" -ForegroundColor Gray

    $orchestratorLog = Join-Path $logDir "orchestrator.log"
    if (Test-Path $orchestratorLog) {
        Get-Content $orchestratorLog -Tail 20 -Wait
    } else {
        Write-Host "No orchestrator log found yet." -ForegroundColor Gray
    }
}

# ============================================================================
# Command: profiles
# ============================================================================

function Show-Profiles {
    Write-Host ""
    Write-Host "Available Profiles" -ForegroundColor Cyan
    Write-Host "------------------" -ForegroundColor Gray

    $profiles = Get-AllProfiles

    if ($profiles.Count -eq 0) {
        Write-Host "No profiles found." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Create a profile with: .\openclawd.ps1 create-profile" -ForegroundColor Gray
        return
    }

    foreach ($p in $profiles) {
        $status = Get-OrchestratorStatus -ProfileName $p.Name
        $statusText = if ($status.IsRunning) { "[Running]" } else { "[Stopped]" }
        $statusColor = if ($status.IsRunning) { "Green" } else { "Gray" }

        Write-Host "  $($p.Name)" -NoNewline -ForegroundColor White
        Write-Host " $statusText" -ForegroundColor $statusColor
        Write-Host "    Display: $($p.DisplayName)" -ForegroundColor Gray
        Write-Host "    Port:    $($p.Port)" -ForegroundColor Gray
        if ($status.TunnelUrl) {
            Write-Host "    Tunnel:  $($status.TunnelUrl)" -ForegroundColor Gray
        }
        Write-Host ""
    }
}

# ============================================================================
# Command: create-profile
# ============================================================================

function New-InteractiveProfile {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Create New Profile                   " -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    # Profile name
    $name = Read-Host "Profile name (e.g., mybot)"
    $name = $name.Trim().ToLower() -replace '[^a-z0-9-]', ''

    if (-not $name) {
        Write-Host "Invalid profile name!" -ForegroundColor Red
        return
    }

    if (Test-ProfileExists $name) {
        Write-Host "Profile '$name' already exists!" -ForegroundColor Red
        return
    }

    # Display name
    $displayName = Read-Host "Display name (e.g., My Bot)"
    if (-not $displayName) { $displayName = $name }

    # Bot token
    $botToken = Read-Host "Bot token (from @BotFather)"
    if (-not $botToken -or $botToken -notmatch '^\d+:') {
        Write-Host "Invalid bot token format!" -ForegroundColor Red
        return
    }

    # Port
    $portInput = Read-Host "Port (default: 18790)"
    $port = if ($portInput) { [int]$portInput } else { 18790 }

    # Create profile
    Write-Host ""
    Write-Host "Creating profile..." -ForegroundColor Cyan

    New-Profile -Name $name -DisplayName $displayName -BotToken $botToken -Port $port

    Write-Host ""
    Write-Host "Profile '$name' created successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Start with: .\openclawd.ps1 start $name" -ForegroundColor Gray
    Write-Host ""
}

# ============================================================================
# Command: health-monitor (internal)
# ============================================================================

function Start-HealthMonitor {
    param([string]$ProfileName)

    $logDir = Get-ProfileLogDir $ProfileName
    $logFile = Join-Path $logDir "orchestrator.log"

    Write-Log "Health monitor started for profile: $ProfileName" -Level info -LogFile $logFile

    $checkInterval = $script:DefaultHealthInterval
    $consecutiveFailures = 0
    $maxFailures = 3

    while ($true) {
        Start-Sleep -Seconds $checkInterval

        try {
            $status = Get-OrchestratorStatus -ProfileName $ProfileName

            # Check if we should exit (everything stopped)
            if (-not $status.TunnelRunning -and -not $status.GatewayRunning) {
                Write-Log "All processes stopped, health monitor exiting" -Level info -LogFile $logFile
                break
            }

            # Check tunnel URL reachability
            $tunnelUrl = Get-SavedTunnelUrl -ProfileName $ProfileName
            if ($tunnelUrl) {
                $tunnelHealthy = Test-TunnelHealth -TunnelUrl $tunnelUrl
                if (-not $tunnelHealthy) {
                    $consecutiveFailures++
                    Write-Log "Tunnel health check failed ($consecutiveFailures/$maxFailures)" -Level warn -LogFile $logFile

                    if ($consecutiveFailures -ge $maxFailures) {
                        Write-Log "Too many tunnel failures, triggering restart" -Level error -LogFile $logFile
                        # Full restart needed - new tunnel URL required
                        Invoke-FullRestart -ProfileName $ProfileName -LogFile $logFile
                        $consecutiveFailures = 0
                    }
                } else {
                    if ($consecutiveFailures -gt 0) {
                        Write-Log "Tunnel recovered" -Level info -LogFile $logFile
                    }
                    $consecutiveFailures = 0
                }
            }

            # Check tunnel log for connection errors (catches issues before URL becomes unreachable)
            $tunnelLogErrors = Get-TunnelLogErrors -ProfileName $ProfileName -LookbackSeconds 60
            if ($tunnelLogErrors -and $tunnelLogErrors.HasErrors) {
                $errorCount = $tunnelLogErrors.ErrorCount
                if ($errorCount -ge 3) {
                    Write-Log "Detected $errorCount tunnel errors in last 60s, triggering restart" -Level warn -LogFile $logFile
                    Invoke-FullRestart -ProfileName $ProfileName -LogFile $logFile
                    $consecutiveFailures = 0
                } elseif ($errorCount -ge 1) {
                    Write-Log "Detected $errorCount tunnel error(s) in last 60s, monitoring..." -Level debug -LogFile $logFile
                }
            }

            # Check gateway
            if (-not $status.GatewayRunning -and $status.TunnelRunning) {
                Write-Log "Gateway not running, attempting restart" -Level warn -LogFile $logFile
                Invoke-GatewayRestart -ProfileName $ProfileName -LogFile $logFile
            }

            # Check webhook (less frequently)
            if ((Get-Date).Second -lt $checkInterval) {
                try {
                    $profileConfig = Get-Profile $ProfileName
                    $webhookInfo = Get-TelegramWebhookInfo -BotToken $profileConfig.botToken
                    $expectedUrl = "$tunnelUrl/telegram-webhook"

                    if ($webhookInfo.url -ne $expectedUrl -and $tunnelUrl) {
                        Write-Log "Webhook mismatch, re-registering" -Level warn -LogFile $logFile
                        Set-TelegramWebhook -BotToken $profileConfig.botToken -WebhookUrl $expectedUrl | Out-Null
                        Write-Log "Webhook re-registered" -Level info -LogFile $logFile
                    }
                } catch {
                    Write-Log "Webhook check failed: $_" -Level warn -LogFile $logFile
                }
            }

        } catch {
            Write-Log "Health monitor error: $_" -Level error -LogFile $logFile
        }
    }

    Write-Log "Health monitor stopped" -Level info -LogFile $logFile
}

function Invoke-GatewayRestart {
    param(
        [string]$ProfileName,
        [string]$LogFile
    )

    try {
        $profileConfig = Get-Profile $ProfileName
        $logDir = Get-ProfileLogDir $ProfileName
        $gatewayLogFile = Join-Path $logDir "gateway.log"
        $port = if ($profileConfig.port) { $profileConfig.port } else { 18790 }

        $gatewayProcess = Start-Process -FilePath "npx.cmd" `
            -ArgumentList "clawdbot", "gateway", "--port", "$port", "--bind", "lan", "--verbose", "--allow-unconfigured" `
            -RedirectStandardOutput $gatewayLogFile `
            -RedirectStandardError (Join-Path $logDir "gateway-error.log") `
            -WindowStyle Hidden `
            -PassThru

        Save-ProcessId -ProfileName $ProfileName -ProcessType "gateway" -ProcessId $gatewayProcess.Id
        Write-Log "Gateway restarted with PID $($gatewayProcess.Id) (port $port, bind lan)" -Level info -LogFile $LogFile
    } catch {
        Write-Log "Failed to restart gateway: $_" -Level error -LogFile $LogFile
    }
}

function Invoke-FullRestart {
    param(
        [string]$ProfileName,
        [string]$LogFile
    )

    Write-Log "Initiating full restart..." -Level info -LogFile $LogFile

    try {
        # Stop everything first
        $status = Get-OrchestratorStatus -ProfileName $ProfileName

        if ($status.GatewayRunning) {
            Stop-ProcessGracefully -ProcessId $status.GatewayPid | Out-Null
            Remove-PidFile -ProfileName $ProfileName -ProcessType "gateway"
        }

        if ($status.TunnelRunning) {
            Stop-ProcessGracefully -ProcessId $status.TunnelPid | Out-Null
            Remove-PidFile -ProfileName $ProfileName -ProcessType "tunnel"
            Remove-TunnelUrlFile -ProfileName $ProfileName
        }

        Start-Sleep -Seconds 2

        # Get profile config
        $profileConfig = Get-Profile $ProfileName
        $logDir = Get-ProfileLogDir $ProfileName
        $port = if ($profileConfig.port) { $profileConfig.port } else { 18790 }

        # Start new tunnel
        $tunnelLogFile = Join-Path $logDir "tunnel.log"
        Clear-Content $tunnelLogFile -ErrorAction SilentlyContinue

        $tunnelProcess = Start-Process -FilePath "cloudflared.cmd" `
            -ArgumentList "tunnel", "--url", "http://localhost:$port" `
            -RedirectStandardError $tunnelLogFile `
            -WindowStyle Hidden `
            -PassThru

        Save-ProcessId -ProfileName $ProfileName -ProcessType "tunnel" -ProcessId $tunnelProcess.Id
        Write-Log "Tunnel restarted with PID $($tunnelProcess.Id)" -Level info -LogFile $LogFile

        # Wait for tunnel URL
        $tunnelUrl = Wait-ForTunnelUrl -LogFile $tunnelLogFile -TimeoutSeconds 60
        if (-not $tunnelUrl) {
            Write-Log "Failed to get new tunnel URL" -Level error -LogFile $LogFile
            return
        }

        Save-TunnelUrl -ProfileName $ProfileName -TunnelUrl $tunnelUrl
        Write-Log "New tunnel URL: $tunnelUrl" -Level info -LogFile $LogFile

        # Update config with new tunnel URL
        Write-Log "Updating clawdbot.json with new tunnel URL..." -Level info -LogFile $LogFile
        New-ClawdbotConfig -Profile $profileConfig -TunnelUrl $tunnelUrl | Out-Null
        Write-Log "Config updated: $script:ConfigFile" -Level info -LogFile $LogFile

        # Register new webhook URL with Telegram
        $webhookUrl = "$tunnelUrl/telegram-webhook"
        Write-Log "Registering new webhook with Telegram..." -Level info -LogFile $LogFile
        Set-TelegramWebhook -BotToken $profileConfig.botToken -WebhookUrl $webhookUrl | Out-Null
        Write-Log "Webhook registered: $webhookUrl" -Level info -LogFile $LogFile

        # Verify webhook was updated
        try {
            $webhookInfo = Get-TelegramWebhookInfo -BotToken $profileConfig.botToken
            if ($webhookInfo.url -eq $webhookUrl) {
                Write-Log "Webhook verified - Telegram will send updates to new URL" -Level info -LogFile $LogFile
            } else {
                Write-Log "WARNING: Webhook URL mismatch after registration! Expected: $webhookUrl, Got: $($webhookInfo.url)" -Level warn -LogFile $LogFile
            }
        } catch {
            Write-Log "Could not verify webhook: $_" -Level warn -LogFile $LogFile
        }

        # Start gateway
        $gatewayLogFile = Join-Path $logDir "gateway.log"
        Clear-Content $gatewayLogFile -ErrorAction SilentlyContinue
        $port = if ($profileConfig.port) { $profileConfig.port } else { 18790 }

        $gatewayProcess = Start-Process -FilePath "npx.cmd" `
            -ArgumentList "clawdbot", "gateway", "--port", "$port", "--bind", "lan", "--verbose", "--allow-unconfigured" `
            -RedirectStandardOutput $gatewayLogFile `
            -RedirectStandardError (Join-Path $logDir "gateway-error.log") `
            -WindowStyle Hidden `
            -PassThru

        Save-ProcessId -ProfileName $ProfileName -ProcessType "gateway" -ProcessId $gatewayProcess.Id
        Write-Log "Gateway restarted with PID $($gatewayProcess.Id) (port $port, bind lan)" -Level info -LogFile $LogFile

        Write-Log "Full restart completed successfully" -Level info -LogFile $LogFile

    } catch {
        Write-Log "Full restart failed: $_" -Level error -LogFile $LogFile
    }
}

# ============================================================================
# Main Entry Point
# ============================================================================

switch ($Command) {
    "start" {
        Start-Orchestrator -ProfileName $Profile
    }
    "stop" {
        Stop-Orchestrator -ProfileName $Profile
    }
    "restart" {
        Restart-Orchestrator -ProfileName $Profile
    }
    "status" {
        Show-Status -ProfileName $Profile
    }
    "health" {
        Test-Health -ProfileName $Profile
    }
    "logs" {
        Show-Logs -ProfileName $Profile
    }
    "profiles" {
        Show-Profiles
    }
    "create-profile" {
        New-InteractiveProfile
    }
    "health-monitor" {
        Start-HealthMonitor -ProfileName $Profile
    }
    default {
        Write-Host "Unknown command: $Command" -ForegroundColor Red
        Write-Host ""
        Write-Host "Usage: .\openclawd.ps1 <command> [profile]" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Commands:" -ForegroundColor Yellow
        Write-Host "  start [profile]     - Start orchestrator with profile" -ForegroundColor White
        Write-Host "  stop [profile]      - Stop orchestrator (deletes webhook)" -ForegroundColor White
        Write-Host "  restart [profile]   - Restart orchestrator" -ForegroundColor White
        Write-Host "  status [profile]    - Show status" -ForegroundColor White
        Write-Host "  health [profile]    - Run comprehensive health check" -ForegroundColor White
        Write-Host "  logs [profile]      - Tail logs" -ForegroundColor White
        Write-Host "  profiles            - List available profiles" -ForegroundColor White
        Write-Host "  create-profile      - Create a new profile interactively" -ForegroundColor White
        Write-Host ""
    }
}
