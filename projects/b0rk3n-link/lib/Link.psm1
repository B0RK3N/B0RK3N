Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-LinkRoot { Split-Path $PSScriptRoot -Parent }
function Get-LinkStateDirectory {
    $path = Join-Path (Get-LinkRoot) '.local'
    if (!(Test-Path -LiteralPath $path)) { New-Item -ItemType Directory -Path $path -Force | Out-Null }
    return $path
}
function Save-LinkJson {
    param([Parameter(Mandatory)]$Value, [Parameter(Mandatory)][string]$Path)
    $parent = Split-Path $Path -Parent
    if (!(Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
}
function Test-LinkHost {
    param([AllowEmptyString()][string]$HostName)
    if ([string]::IsNullOrWhiteSpace($HostName)) { return $false }
    $address = $null
    if ([Net.IPAddress]::TryParse($HostName, [ref]$address)) {
        $bytes = $address.GetAddressBytes()
        return ($bytes.Length -eq 4 -and $bytes[0] -eq 100 -and $bytes[1] -ge 64 -and $bytes[1] -le 127)
    }
    return ($HostName.Length -le 253 -and $HostName -cmatch '^[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.ts\.net$')
}
function Test-LinkAiUrl {
    param([AllowEmptyString()][string]$Url)
    $uri = $null
    if (![Uri]::TryCreate($Url, [UriKind]::Absolute, [ref]$uri)) { return $false }
    return ($uri.Scheme -eq 'https' -and $uri.Port -eq 443 -and
        $uri.UserInfo -eq '' -and $uri.Query -eq '' -and $uri.Fragment -eq '' -and
        $uri.AbsolutePath -eq '/' -and $uri.Host -like '*.ts.net' -and
        (Test-LinkHost $uri.Host))
}
function Read-LinkClientConfig {
    param([string]$Path = (Join-Path (Get-LinkStateDirectory) 'client.json'))
    if (!(Test-Path -LiteralPath $Path)) { throw 'No desktop configured. Run SETUP-LAPTOP.cmd after desktop setup.' }
    $config = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    if (!(Test-LinkHost $config.serverHost)) { throw 'The desktop address must be a Tailscale IP or complete name ending in .ts.net.' }
    if (!(Test-LinkAiUrl $config.aiUrl)) { throw 'The AI URL must be an HTTPS Tailscale name on port 443.' }
    if ($config.username -match '[\r\n]') { throw 'Invalid Windows username.' }
    return $config
}
function Get-LinkTailscale {
    $command = Get-Command tailscale.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    $candidate = Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'
    if (Test-Path -LiteralPath $candidate) { return $candidate }
    throw 'Tailscale is not installed. Run tools\Install-Tailscale.ps1 in an Administrator terminal, then sign in.'
}
function Invoke-LinkTailscale {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $exe = Get-LinkTailscale
    $output = & $exe @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw ($output -join [Environment]::NewLine) }
    return ($output -join [Environment]::NewLine)
}
function Get-LinkTailscaleStatus {
    $status = Invoke-LinkTailscale -Arguments @('status', '--json') | ConvertFrom-Json
    if ($status.BackendState -ne 'Running') { throw 'Tailscale is not connected. Open Tailscale, sign in, then retry.' }
    return $status
}
function Assert-LinkAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (!$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Open PowerShell as Administrator on this computer and run this script again.'
    }
}
function Test-LinkTcp {
    param([Parameter(Mandatory)][string]$HostName, [Parameter(Mandatory)][int]$Port, [int]$TimeoutMs = 1800)
    $client = New-Object Net.Sockets.TcpClient
    try {
        $pending = $client.BeginConnect($HostName, $Port, $null, $null)
        if (!$pending.AsyncWaitHandle.WaitOne($TimeoutMs)) { return $false }
        $client.EndConnect($pending)
        return $true
    } catch { return $false } finally { $client.Dispose() }
}
function New-LinkRdpContent {
    param([Parameter(Mandatory)][string]$ServerHost, [string]$Username = '', [switch]$FileTransfer)
    if (!(Test-LinkHost $ServerHost)) { throw 'Invalid Tailscale desktop address.' }
    if ($Username -match '[\r\n]') { throw 'Invalid Windows username.' }
    $clipboard = 0
    if ($FileTransfer) { $clipboard = 1 }
    # No password is persisted; full local drives are never redirected automatically.
    $lines = @(
        'screen mode id:i:2', 'use multimon:i:0', "full address:s:$ServerHost",
        "username:s:$Username", 'prompt for credentials:i:1',
        'authentication level:i:2', 'enablecredsspsupport:i:1',
        "redirectclipboard:i:$clipboard", 'drivestoredirect:s:',
        'redirectprinters:i:0', 'redirectcomports:i:0', 'redirectsmartcards:i:0',
        'audiomode:i:0', 'autoreconnection enabled:i:1', 'connection type:i:7',
        'networkautodetect:i:1', 'bandwidthautodetect:i:1'
    )
    return ([string]::Join([Environment]::NewLine, $lines) + [Environment]::NewLine)
}
function Open-LinkDesktop {
    param([Parameter(Mandatory)]$Config, [switch]$FileTransfer)
    $rdp = Join-Path (Get-LinkStateDirectory) 'desktop.rdp'
    New-LinkRdpContent -ServerHost $Config.serverHost -Username $Config.username -FileTransfer:$FileTransfer |
        Set-Content -LiteralPath $rdp -Encoding Unicode
    Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\mstsc.exe') -ArgumentList ('"' + $rdp + '"')
}
Export-ModuleMember -Function *-Link*
