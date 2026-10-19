[CmdletBinding()]
param([string]$ServerConfig, [string]$ServerHost, [string]$AiUrl, [string]$Username = '')
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\lib\Link.psm1') -Force
$null = Get-LinkTailscaleStatus
if ($ServerConfig) {
    $config = Read-LinkClientConfig -Path $ServerConfig
} else {
    if (!$ServerHost) {
        Write-Host 'Use the desktop address printed by server\Setup.ps1.'
        $ServerHost = Read-Host 'Desktop full Tailscale name (example: my-pc.tail12345.ts.net)'
    }
    if (!$AiUrl) { $AiUrl = 'https://' + $ServerHost.TrimEnd('.') + '/' }
    $config = [pscustomobject]@{ serverHost = $ServerHost; aiUrl = $AiUrl; username = $Username }
    $tempPath = Join-Path (Get-LinkStateDirectory) 'client.pending.json'
    try {
        Save-LinkJson -Value $config -Path $tempPath
        $config = Read-LinkClientConfig -Path $tempPath
    } finally { if (Test-Path -LiteralPath $tempPath) { Remove-Item -LiteralPath $tempPath } }
}
Save-LinkJson -Value $config -Path (Join-Path (Get-LinkStateDirectory) 'client.json')
Write-Host 'Laptop configured. Double-click START.cmd to open B0RK3N Link.'
Write-Host 'Your desktop must stay powered on and online. Different Wi-Fi networks are supported.'
