[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\lib\Link.psm1') -Force
Assert-LinkAdministrator
$stateDir = Get-LinkStateDirectory
$stateFile = Join-Path $stateDir 'desktop-state.json'
if (!(Test-Path -LiteralPath $stateFile)) { throw 'No recorded desktop setup exists. No settings were changed.' }
$state = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
if ($state.taskRegistered) {
    $task = Get-ScheduledTask -TaskName $state.taskName -ErrorAction SilentlyContinue
    if ($task) {
        Stop-ScheduledTask -TaskName $state.taskName
        Unregister-ScheduledTask -TaskName $state.taskName -Confirm:$false
    }
}
if ($state.serveConfigured) { $null = Invoke-LinkTailscale -Arguments @('serve', '--https=443', 'off') }
if ($state.rdpChanged) {
    $terminalKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
    Set-ItemProperty -LiteralPath $terminalKey -Name fDenyTSConnections -Value $state.oldDeny
    Set-ItemProperty -LiteralPath (Join-Path $terminalKey 'WinStations\RDP-Tcp') -Name UserAuthentication -Value $state.oldNla
    Get-NetFirewallRule -Name 'B0RK3N-Link-RDP-*' -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    foreach ($rule in @($state.firewall)) { Set-NetFirewallRule -Name $rule.name -Enabled $rule.enabled | Out-Null }
}
foreach ($name in @('server.json', 'client.json', 'desktop-state.json')) {
    $path = Join-Path $stateDir $name
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path }
}
Write-Host 'Recorded RDP/firewall settings restored; project startup task and HTTPS endpoint removed.'
Write-Host 'Agent files, Ollama models, Tailscale installation, and logs were retained.'
Write-Host 'Close any manually started server\Start-Agent.ps1 session separately.'
