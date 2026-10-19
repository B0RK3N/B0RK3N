[CmdletBinding()]
param(
    [string]$AgentFolder = 'C:\B0RK3N-WebAI',
    [ValidatePattern('^[A-Za-z_][A-Za-z0-9_.]*:[A-Za-z_][A-Za-z0-9_]*$')][string]$WsgiApp = 'app:app',
    [ValidateRange(1024, 65535)][int]$AgentPort = 5000,
    [switch]$EnableRemoteDesktop,
    [switch]$RegisterAutoStart
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\lib\Link.psm1') -Force
Assert-LinkAdministrator
$null = Get-LinkTailscale
$status = Get-LinkTailscaleStatus
$serverName = $status.Self.DNSName.TrimEnd('.')
if (!(Test-LinkHost $serverName)) { throw 'Enable MagicDNS in Tailscale first. A full .ts.net name is required for HTTPS.' }
$agent = (Resolve-Path -LiteralPath $AgentFolder).Path
$python = Join-Path $agent '.venv\Scripts\python.exe'
if (!(Test-Path -LiteralPath $python)) { throw "Expected the existing agent virtual environment at $python. Restore the agent on this desktop first." }
$moduleFile = ($WsgiApp.Split(':')[0].Replace('.', '\') + '.py')
$modulePackage = Join-Path ($WsgiApp.Split(':')[0].Replace('.', '\')) '__init__.py'
if (!(Test-Path -LiteralPath (Join-Path $agent $moduleFile)) -and !(Test-Path -LiteralPath (Join-Path $agent $modulePackage))) {
    throw "Cannot find the WSGI module for $WsgiApp. Pass -WsgiApp server:app if your Flask file is server.py, for example."
}
if (Test-LinkTcp '127.0.0.1' $AgentPort) { throw "Port $AgentPort is already in use. Stop the existing agent web server before setup. Ollama can keep running." }
$stateDir = Get-LinkStateDirectory
$stateFile = Join-Path $stateDir 'desktop-state.json'
$serverConfigFile = Join-Path $stateDir 'server.json'
if ((Test-Path -LiteralPath $serverConfigFile) -or (Test-Path -LiteralPath $stateFile)) {
    throw 'Desktop setup or recovery state already exists. Use server\Start-Agent.ps1, or run server\Remove-Setup.ps1 before setting up again.'
}
$serveJson = Invoke-LinkTailscale -Arguments @('serve', 'status', '--json')
$serve = $serveJson | ConvertFrom-Json
if ($serve -and @($serve.PSObject.Properties).Count -gt 0 -and $serveJson -notmatch '^\s*\{\s*\}\s*$') {
    throw 'An existing Tailscale Serve configuration was found. This setup will not overwrite it. Use a separate node or inspect tailscale serve status first.'
}
$terminalKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
$nlaKey = Join-Path $terminalKey 'WinStations\RDP-Tcp'
$firewallState = @()
$saved = [ordered]@{ rdpChanged = $false; oldDeny = $null; oldNla = $null; firewall = @(); serveConfigured = $false; taskRegistered = $false; taskName = 'B0RK3N-Link-Agent' }
if ($EnableRemoteDesktop) {
    $edition = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').EditionID
    if ($edition -notmatch 'Professional|Enterprise|Education|Server') { throw "Windows edition $edition cannot host built-in Remote Desktop. AI access still works: run without -EnableRemoteDesktop." }
    $saved.oldDeny = (Get-ItemProperty -LiteralPath $terminalKey).fDenyTSConnections
    $saved.oldNla = (Get-ItemProperty -LiteralPath $nlaKey).UserAuthentication
    foreach ($name in @('RemoteDesktop-UserMode-In-TCP', 'RemoteDesktop-UserMode-In-UDP')) {
        $rule = Get-NetFirewallRule -Name $name -ErrorAction SilentlyContinue
        if ($rule) { $firewallState += @{ name = $rule.Name; enabled = [string]$rule.Enabled } }
    }
    if (@(Get-NetFirewallRule -Name 'B0RK3N-Link-RDP-*' -ErrorAction SilentlyContinue).Count -gt 0) { throw 'B0RK3N Link firewall rules already exist. Remove the previous setup first.' }
    $saved.firewall = $firewallState
}
if ($RegisterAutoStart -and (Get-ScheduledTask -TaskName $saved.taskName -ErrorAction SilentlyContinue)) {
    throw 'A task named B0RK3N-Link-Agent already exists; it was not overwritten.'
}
# Fail before OS changes if production-server dependencies cannot be installed.
& $python -m pip install --disable-pip-version-check 'waitress>=3.0.2,<4'
if ($LASTEXITCODE -ne 0) { throw 'Could not install Waitress in the existing agent virtual environment.' }
Save-LinkJson -Value $saved -Path $stateFile
try {
    # Private to the tailnet. Funnel is never enabled.
    $serveOutput = Invoke-LinkTailscale -Arguments @('serve', '--bg', '--yes', '--https=443', "http://127.0.0.1:$AgentPort")
    $saved.serveConfigured = $true
    Save-LinkJson -Value $saved -Path $stateFile
    Write-Host $serveOutput
    if ($EnableRemoteDesktop) {
        $localAddresses = @($status.Self.TailscaleIPs)
        if ($localAddresses.Count -eq 0) { throw 'No local Tailscale interface addresses were found.' }
        $saved.rdpChanged = $true
        Save-LinkJson -Value $saved -Path $stateFile
        foreach ($protocol in @('TCP', 'UDP')) {
            New-NetFirewallRule -Name "B0RK3N-Link-RDP-$protocol" -DisplayName "B0RK3N Link RDP ($protocol, Tailscale only)" -Direction Inbound -Action Allow -Protocol $protocol -LocalPort 3389 -LocalAddress $localAddresses -RemoteAddress @('100.64.0.0/10', 'fd7a:115c:a1e0::/48') -Profile Any | Out-Null
        }
        foreach ($rule in $firewallState) { Disable-NetFirewallRule -Name $rule.name | Out-Null }
        Set-ItemProperty -LiteralPath $nlaKey -Name UserAuthentication -Value 1
        Set-ItemProperty -LiteralPath $terminalKey -Name fDenyTSConnections -Value 0
        Start-Service TermService
        Write-Host 'Remote Desktop enabled with Network Level Authentication and Tailscale-scoped rules.'
        Write-Host 'Other custom firewall rules, if any, are not audited by this script.'
    }
    Save-LinkJson -Value ([ordered]@{ agentFolder = $agent; python = $python; wsgiApp = $WsgiApp; port = $AgentPort }) -Path $serverConfigFile
    if ($RegisterAutoStart) {
        $runner = Join-Path $PSScriptRoot 'Start-Agent.ps1'
        $arguments = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $runner + '"'
        $action = New-ScheduledTaskAction -Execute (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -Argument $arguments -WorkingDirectory $agent
        $account = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        $trigger = New-ScheduledTaskTrigger -AtLogOn -User $account
        $principal = New-ScheduledTaskPrincipal -UserId $account -LogonType Interactive -RunLevel Limited
        $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -RestartCount 5 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew
        Register-ScheduledTask -TaskName $saved.taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings | Out-Null
        $saved.taskRegistered = $true
        Save-LinkJson -Value $saved -Path $stateFile
        Start-ScheduledTask -TaskName $saved.taskName
    }
    $clientConfig = [ordered]@{ serverHost = $serverName; aiUrl = "https://$serverName/"; username = '' }
    Save-LinkJson -Value $clientConfig -Path (Join-Path $stateDir 'client.json')
    Write-Host "Desktop configuration complete. AI URL: https://$serverName/"
    Write-Host 'Copy .local\client.json to the laptop and run client\Setup.ps1 -ServerConfig <path>.'
    Write-Host 'Keep the desktop on, connected, and awake. AI startup is after Windows sign-in, not before.'
    Write-Host 'For Tailscale access before Windows sign-in, enable Preferences > Run unattended in Tailscale.'
    if (!$RegisterAutoStart) { Write-Host 'Start the AI with server\Start-Agent.ps1.' }
} catch {
    Write-Warning 'Setup did not complete. Run server\Remove-Setup.ps1 as Administrator to restore recorded settings before retrying.'
    throw
}
