[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\lib\Link.psm1') -Force
try { $tailscale = Get-LinkTailscale } catch {
    Write-Host 'Installing the official Tailscale client. Approve the Windows administrator prompt.'
    $installer = Join-Path $PSScriptRoot '..\tools\Install-Tailscale.ps1'
    $arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $installer + '"'
    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden -Wait -PassThru
    if ($process.ExitCode -ne 0) { throw 'Tailscale installation failed or was cancelled.' }
    $tailscale = Get-LinkTailscale
}
$status = Invoke-LinkTailscale -Arguments @('status', '--json') | ConvertFrom-Json
if ($status.BackendState -ne 'Running') {
    Write-Host 'Sign in to Tailscale with the SAME account used on your desktop.'
    $app = Join-Path (Split-Path $tailscale -Parent) 'tailscale-ipn.exe'
    Start-Process -FilePath $app
    $null = Read-Host 'When Tailscale shows Connected, press Enter here'
    $null = Get-LinkTailscaleStatus
}
$configFile = Join-Path (Get-LinkStateDirectory) 'client.json'
if (!(Test-Path -LiteralPath $configFile)) { & (Join-Path $PSScriptRoot 'Setup.ps1') }
$null = Read-LinkClientConfig
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Desktop')) 'B0RK3N Link.lnk'))
$shortcut.TargetPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$shortcut.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $PSScriptRoot 'Launch.ps1') + '"'
$shortcut.WorkingDirectory = Split-Path $PSScriptRoot -Parent
$shortcut.Description = 'Connect to your desktop AI, applications, and files'
$shortcut.Save()
& (Join-Path $PSScriptRoot 'Launch.ps1')
