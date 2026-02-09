# OpenClawd Orchestrator - Shared Functions Library
# This file contains common functions used by the orchestrator

#Requires -Version 5.1

# ============================================================================
# Configuration
# ============================================================================

$script:ClawdbotHome = Join-Path $env:USERPROFILE ".clawdbot"
$script:ProfilesDir = Join-Path $script:ClawdbotHome "profiles"
$script:LogsDir = Join-Path $script:ClawdbotHome "logs"
$script:PidsDir = Join-Path $script:ClawdbotHome "pids"
$script:ConfigFile = Join-Path $script:ClawdbotHome "clawdbot.json"

$script:DefaultHealthInterval = if ($env:OPENCLAWD_HEALTH_INTERVAL) { [int]$env:OPENCLAWD_HEALTH_INTERVAL } else { 30 }
$script:DefaultProfile = if ($env:OPENCLAWD_PROFILE) { $env:OPENCLAWD_PROFILE } else { "peflaptopbot" }
$script:LogLevel = if ($env:OPENCLAWD_LOG_LEVEL) { $env:OPENCLAWD_LOG_LEVEL } else { "info" }

$script:TelegramApiBase = "https://api.telegram.org/bot"

# ============================================================================
# Directory Management
# ============================================================================

function Initialize-ClawdbotDirectories {
    $dirs = @($script:ClawdbotHome, $script:ProfilesDir, $script:LogsDir, $script:PidsDir)
    foreach ($dir in $dirs) {
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }
}

function Get-ProfileLogDir {
    param([string]$ProfileName)
    $logDir = Join-Path $script:LogsDir $ProfileName
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    return $logDir
}

# ============================================================================
# Logging
# ============================================================================

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("debug", "info", "warn", "error")]
        [string]$Level = "info",
        [string]$ProfileName = $null,
        [string]$LogFile = $null
    )

    $levels = @{ "debug" = 0; "info" = 1; "warn" = 2; "error" = 3 }
    $currentLevel = $levels[$script:LogLevel.ToLower()]
    $msgLevel = $levels[$Level.ToLower()]

    if ($msgLevel -lt $currentLevel) { return }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $levelTag = $Level.ToUpper().PadRight(5)
    $logEntry = "[$timestamp] [$levelTag] $Message"

    # Console output with colors
    $color = switch ($Level) {
        "debug" { "Gray" }
        "info"  { "White" }
        "warn"  { "Yellow" }
        "error" { "Red" }
    }
    Write-Host $logEntry -ForegroundColor $color

    # File output
    if ($ProfileName -or $LogFile) {
        $targetFile = if ($LogFile) {
            $LogFile
        } else {
            Join-Path (Get-ProfileLogDir $ProfileName) "orchestrator.log"
        }
        Add-Content -Path $targetFile -Value $logEntry -Encoding UTF8
    }
}

# ============================================================================
# Profile Management
# ============================================================================

function Get-ProfilePath {
    param([string]$ProfileName)
    return Join-Path $script:ProfilesDir "$ProfileName.json"
}

function Test-ProfileExists {
    param([string]$ProfileName)
    return Test-Path (Get-ProfilePath $ProfileName)
}

function Get-Profile {
    param([string]$ProfileName)

    $profilePath = Get-ProfilePath $ProfileName
    if (-not (Test-Path $profilePath)) {
        throw "Profile '$ProfileName' not found at $profilePath"
    }

    $profile = Get-Content $profilePath -Raw | ConvertFrom-Json
    return $profile
}

function Get-AllProfiles {
    $profiles = @()
    if (Test-Path $script:ProfilesDir) {
        Get-ChildItem -Path $script:ProfilesDir -Filter "*.json" | ForEach-Object {
            $name = $_.BaseName
            try {
                $profile = Get-Content $_.FullName -Raw | ConvertFrom-Json
                $profiles += [PSCustomObject]@{
                    Name = $name
                    DisplayName = if ($profile.displayName) { $profile.displayName } else { $name }
                    Port = if ($profile.port) { $profile.port } else { 18790 }
                    Path = $_.FullName
                }
            } catch {
                Write-Log "Failed to parse profile: $name" -Level warn
            }
        }
    }
    return $profiles
}

function New-Profile {
    param(
        [string]$Name,
        [string]$DisplayName,
        [string]$BotToken,
        [int]$Port = 18790,
        [hashtable]$AdditionalSettings = @{}
    )

    $profile = @{
        name = $Name
        displayName = $DisplayName
        port = $Port
        botToken = $BotToken
        telegram = @{
            dmPolicy = "open"
            groupPolicy = "open"
            # SECURITY: allowFrom = @("*") allows ALL users. Restrict to specific Telegram user IDs in production.
            allowFrom = @("*")
            groups = @{
                "*" = @{
                    requireMention = $false
                    enabled = $true
                }
            }
            replyToMode = "first"
            streamMode = "partial"
        }
        agents = @{
            defaults = @{
                model = @{
                    primary = "anthropic/claude-opus-4-5"
                }
            }
        }
    }

    # Merge additional settings
    foreach ($key in $AdditionalSettings.Keys) {
        $profile[$key] = $AdditionalSettings[$key]
    }

    $profilePath = Get-ProfilePath $Name
    $profile | ConvertTo-Json -Depth 10 | Set-Content -Path $profilePath -Encoding UTF8

    return $profile
}

# ============================================================================
# Config Generation
# ============================================================================

function New-ClawdbotConfig {
    param(
        [PSCustomObject]$Profile,
        [string]$TunnelUrl
    )

    $webhookUrl = "$TunnelUrl/telegram-webhook"
    Write-Log "Webhook URL: $webhookUrl" -Level debug

    # Generate a stable gateway token based on profile name (or use env var)
    $gatewayToken = if ($env:CLAWDBOT_GATEWAY_TOKEN) {
        $env:CLAWDBOT_GATEWAY_TOKEN
    } else {
        # Create a deterministic token from profile name for consistency
        $bytes = [System.Text.Encoding]::UTF8.GetBytes("openclawd-$($Profile.name)-gateway-token")
        $hash = [System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
        [System.BitConverter]::ToString($hash).Replace("-", "").ToLower()
    }

    $config = @{
        gateway = @{
            port = $Profile.port
            mode = "local"
            auth = @{
                token = $gatewayToken
            }
        }
        channels = @{
            telegram = @{
                enabled = $true
                botToken = $Profile.botToken
                webhookUrl = $webhookUrl
                dmPolicy = if ($Profile.telegram.dmPolicy) { $Profile.telegram.dmPolicy } else { "open" }
                groupPolicy = if ($Profile.telegram.groupPolicy) { $Profile.telegram.groupPolicy } else { "open" }
                # SECURITY: Restrict allowFrom to specific Telegram user IDs in production instead of "*"
                allowFrom = @(if ($Profile.telegram.allowFrom) { $Profile.telegram.allowFrom } else { "*" })
                streamMode = if ($Profile.telegram.streamMode) { $Profile.telegram.streamMode } else { "partial" }
                replyToMode = "first"
            }
        }
        agents = if ($Profile.agents) { $Profile.agents } else { @{
            defaults = @{
                model = @{
                    primary = "anthropic/claude-opus-4-5"
                }
            }
        } }
        plugins = @{
            entries = @{
                telegram = @{
                    enabled = $true
                }
            }
        }
    }

    # Audio transcription configuration (OpenAI Whisper for STT)
    # Note: TTS is not supported by openclaw config schema
    # Requires OPENAI_API_KEY environment variable (passed via env, not config)
    if ($env:OPENAI_API_KEY) {
        Write-Log "Configuring audio transcription with OpenAI Whisper" -Level info
        $config.tools = @{
            media = @{
                # Speech-to-text (audio transcription via Whisper)
                audio = @{
                    enabled = $true
                    models = @(
                        @{ provider = "openai"; model = "whisper-1" }
                    )
                }
            }
        }
        # Note: OPENAI_API_KEY is passed via environment variable, not config
        # The openclaw runtime reads it from process.env automatically
    }

    $config | ConvertTo-Json -Depth 10 | Set-Content -Path $script:ConfigFile -Encoding UTF8

    return $config
}

# ============================================================================
# Telegram API Helpers
# ============================================================================

function Invoke-TelegramApi {
    param(
        [string]$BotToken,
        [string]$Method,
        [hashtable]$Parameters = @{}
    )

    $url = "$script:TelegramApiBase$BotToken/$Method"

    try {
        if ($Parameters.Count -gt 0) {
            $response = Invoke-RestMethod -Uri $url -Method Post -Body $Parameters -ErrorAction Stop
        } else {
            $response = Invoke-RestMethod -Uri $url -Method Get -ErrorAction Stop
        }
        return $response
    } catch {
        $errorMsg = $_.Exception.Message
        if ($_.Exception.Response) {
            try {
                $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                $errorBody = $reader.ReadToEnd()
                $errorMsg = "$errorMsg - $errorBody"
            } catch {}
        }
        throw "Telegram API error: $errorMsg"
    }
}

function Set-TelegramWebhook {
    param(
        [string]$BotToken,
        [string]$WebhookUrl
    )

    $result = Invoke-TelegramApi -BotToken $BotToken -Method "setWebhook" -Parameters @{
        url = $WebhookUrl
    }

    return $result.ok
}

function Remove-TelegramWebhook {
    param([string]$BotToken)

    $result = Invoke-TelegramApi -BotToken $BotToken -Method "deleteWebhook"
    return $result.ok
}

function Get-TelegramWebhookInfo {
    param([string]$BotToken)

    $result = Invoke-TelegramApi -BotToken $BotToken -Method "getWebhookInfo"
    return $result.result
}

# ============================================================================
# Process Management
# ============================================================================

function Get-PidFilePath {
    param(
        [string]$ProfileName,
        [ValidateSet("tunnel", "gateway", "health")]
        [string]$ProcessType
    )
    return Join-Path $script:PidsDir "$ProfileName-$ProcessType.pid"
}

function Save-ProcessId {
    param(
        [string]$ProfileName,
        [string]$ProcessType,
        [int]$ProcessId
    )
    $pidFile = Get-PidFilePath -ProfileName $ProfileName -ProcessType $ProcessType
    Set-Content -Path $pidFile -Value $ProcessId -Encoding UTF8
}

function Get-SavedProcessId {
    param(
        [string]$ProfileName,
        [string]$ProcessType
    )
    $pidFile = Get-PidFilePath -ProfileName $ProfileName -ProcessType $ProcessType
    if (Test-Path $pidFile) {
        $savedPid = Get-Content $pidFile -Raw
        return [int]$savedPid.Trim()
    }
    return $null
}

function Remove-PidFile {
    param(
        [string]$ProfileName,
        [string]$ProcessType
    )
    $pidFile = Get-PidFilePath -ProfileName $ProfileName -ProcessType $ProcessType
    if (Test-Path $pidFile) {
        Remove-Item $pidFile -Force
    }
}

function Test-ProcessRunning {
    param([int]$ProcessId)

    if ($null -eq $ProcessId -or $ProcessId -eq 0) { return $false }

    try {
        $process = Get-Process -Id $ProcessId -ErrorAction Stop
        return (-not $process.HasExited)
    } catch {
        return $false
    }
}

function Stop-ProcessGracefully {
    param(
        [int]$ProcessId,
        [int]$TimeoutSeconds = 10
    )

    if (-not (Test-ProcessRunning $ProcessId)) { return $true }

    try {
        $process = Get-Process -Id $ProcessId -ErrorAction Stop

        # Try graceful stop first
        $process.CloseMainWindow() | Out-Null

        # Wait for graceful exit
        $waited = 0
        while ((Test-ProcessRunning $ProcessId) -and $waited -lt $TimeoutSeconds) {
            Start-Sleep -Seconds 1
            $waited++
        }

        # Force kill if still running
        if (Test-ProcessRunning $ProcessId) {
            Stop-Process -Id $ProcessId -Force -ErrorAction Stop
        }

        return $true
    } catch {
        return $false
    }
}

# ============================================================================
# Tunnel URL Parsing
# ============================================================================

function Wait-ForTunnelUrl {
    param(
        [string]$LogFile,
        [int]$TimeoutSeconds = 60
    )

    $pattern = "https://[a-zA-Z0-9-]+\.trycloudflare\.com"
    $startTime = Get-Date

    while (((Get-Date) - $startTime).TotalSeconds -lt $TimeoutSeconds) {
        if (Test-Path $LogFile) {
            $content = Get-Content $LogFile -Raw -ErrorAction SilentlyContinue
            if ($content -match $pattern) {
                return $Matches[0]
            }
        }
        Start-Sleep -Milliseconds 500
    }

    return $null
}

# ============================================================================
# Health Check Helpers
# ============================================================================

function Test-TunnelHealth {
    param([string]$TunnelUrl)

    try {
        $response = Invoke-WebRequest -Uri $TunnelUrl -Method GET -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
        # 200 or 405 (Method Not Allowed) are both acceptable - means tunnel is alive
        return $response.StatusCode -in @(200, 405)
    } catch {
        # 405 might come as exception too
        if ($_.Exception.Response.StatusCode -eq 405) {
            return $true
        }
        return $false
    }
}

function Get-SavedTunnelUrl {
    param([string]$ProfileName)

    $tunnelUrlFile = Join-Path $script:PidsDir "$ProfileName-tunnel.url"
    if (Test-Path $tunnelUrlFile) {
        return (Get-Content $tunnelUrlFile -Raw).Trim()
    }
    return $null
}

function Save-TunnelUrl {
    param(
        [string]$ProfileName,
        [string]$TunnelUrl
    )
    $tunnelUrlFile = Join-Path $script:PidsDir "$ProfileName-tunnel.url"
    Set-Content -Path $tunnelUrlFile -Value $TunnelUrl -Encoding UTF8
}

function Remove-TunnelUrlFile {
    param([string]$ProfileName)
    $tunnelUrlFile = Join-Path $script:PidsDir "$ProfileName-tunnel.url"
    if (Test-Path $tunnelUrlFile) {
        Remove-Item $tunnelUrlFile -Force
    }
}

function Get-TunnelLogErrors {
    <#
    .SYNOPSIS
        Checks tunnel log for recent errors that indicate connection problems

    .DESCRIPTION
        Parses the tunnel log file for error patterns like:
        - "Serve tunnel error"
        - "control stream encountered a failure"
        - "connection refused"
        - "context deadline exceeded"

        Returns error info if recent errors found (within last 2 minutes)
    #>
    param(
        [string]$ProfileName,
        [int]$LookbackSeconds = 120
    )

    $logDir = Get-ProfileLogDir $ProfileName
    $tunnelLogFile = Join-Path $logDir "tunnel.log"

    if (-not (Test-Path $tunnelLogFile)) {
        return $null
    }

    # Error patterns that indicate tunnel problems
    $errorPatterns = @(
        "ERR.*Serve tunnel error",
        "ERR.*control stream encountered a failure",
        "ERR.*connection refused",
        "ERR.*context deadline exceeded",
        "ERR.*tunnel.*failed",
        "ERR.*Unable to establish connection"
    )

    $cutoffTime = (Get-Date).AddSeconds(-$LookbackSeconds)
    $recentErrors = @()

    try {
        # Read last 100 lines of tunnel log
        $logLines = Get-Content $tunnelLogFile -Tail 100 -ErrorAction SilentlyContinue

        foreach ($line in $logLines) {
            # Parse timestamp from cloudflared log format: 2026-02-04T00:21:29Z
            if ($line -match '^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z)') {
                try {
                    $lineTime = [DateTime]::Parse($Matches[1])
                    if ($lineTime -ge $cutoffTime) {
                        foreach ($pattern in $errorPatterns) {
                            if ($line -match $pattern) {
                                $recentErrors += @{
                                    Time = $lineTime
                                    Message = $line
                                }
                                break
                            }
                        }
                    }
                } catch {
                    # Ignore timestamp parse errors
                }
            }
        }
    } catch {
        # Log read error - return null
        return $null
    }

    if ($recentErrors.Count -gt 0) {
        return @{
            HasErrors = $true
            ErrorCount = $recentErrors.Count
            Errors = $recentErrors
            LastError = $recentErrors[-1]
        }
    }

    return @{
        HasErrors = $false
        ErrorCount = 0
        Errors = @()
        LastError = $null
    }
}

function Test-TunnelLogHealthy {
    <#
    .SYNOPSIS
        Quick check if tunnel log shows recent activity without errors

    .DESCRIPTION
        Returns true if tunnel is healthy (no recent errors or has recent successful connections)
    #>
    param(
        [string]$ProfileName,
        [int]$LookbackSeconds = 120
    )

    $errorInfo = Get-TunnelLogErrors -ProfileName $ProfileName -LookbackSeconds $LookbackSeconds

    if ($null -eq $errorInfo) {
        # Can't read log, assume ok
        return $true
    }

    # Check for errors
    if ($errorInfo.HasErrors -and $errorInfo.ErrorCount -ge 2) {
        # Multiple recent errors - likely a problem
        return $false
    }

    return $true
}

# ============================================================================
# Status Helpers
# ============================================================================

function Get-OrchestratorStatus {
    param([string]$ProfileName)

    $tunnelPid = Get-SavedProcessId -ProfileName $ProfileName -ProcessType "tunnel"
    $gatewayPid = Get-SavedProcessId -ProfileName $ProfileName -ProcessType "gateway"
    $healthPid = Get-SavedProcessId -ProfileName $ProfileName -ProcessType "health"
    $tunnelUrl = Get-SavedTunnelUrl -ProfileName $ProfileName

    $status = [PSCustomObject]@{
        ProfileName = $ProfileName
        TunnelPid = $tunnelPid
        TunnelRunning = Test-ProcessRunning $tunnelPid
        GatewayPid = $gatewayPid
        GatewayRunning = Test-ProcessRunning $gatewayPid
        HealthPid = $healthPid
        HealthRunning = Test-ProcessRunning $healthPid
        TunnelUrl = $tunnelUrl
        IsRunning = $false
    }

    $status.IsRunning = $status.TunnelRunning -and $status.GatewayRunning

    return $status
}

# ============================================================================
# Available Functions (dot-sourced, all functions available)
# ============================================================================
# Directory Management: Initialize-ClawdbotDirectories, Get-ProfileLogDir
# Logging: Write-Log
# Profile Management: Get-ProfilePath, Test-ProfileExists, Get-Profile, Get-AllProfiles, New-Profile
# Config Generation: New-ClawdbotConfig
# Telegram API: Invoke-TelegramApi, Set-TelegramWebhook, Remove-TelegramWebhook, Get-TelegramWebhookInfo
# Process Management: Get-PidFilePath, Save-ProcessId, Get-SavedProcessId, Remove-PidFile, Test-ProcessRunning, Stop-ProcessGracefully
# Tunnel: Wait-ForTunnelUrl, Test-TunnelHealth, Get-SavedTunnelUrl, Save-TunnelUrl, Remove-TunnelUrlFile, Get-TunnelLogErrors, Test-TunnelLogHealthy
# Status: Get-OrchestratorStatus
