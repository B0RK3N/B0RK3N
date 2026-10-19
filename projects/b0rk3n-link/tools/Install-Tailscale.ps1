[CmdletBinding()]
param([switch]$DownloadOnly)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\lib\Link.psm1') -Force
if (!$DownloadOnly) { Assert-LinkAdministrator }
$directory = Join-Path (Get-LinkStateDirectory) 'downloads'
New-Item -ItemType Directory -Path $directory -Force | Out-Null
$installer = Join-Path $directory 'tailscale-setup.exe'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Write-Host 'Downloading Tailscale from its official package server...'
Invoke-WebRequest -UseBasicParsing -Uri 'https://pkgs.tailscale.com/stable/tailscale-setup-latest.exe' -OutFile $installer
$signature = Get-AuthenticodeSignature -LiteralPath $installer
if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch '(?i)Tailscale') {
    throw 'Installer signature verification failed. The downloaded file will not be run.'
}
Write-Host 'Verified official Tailscale installer signature.'
if ($DownloadOnly) { Write-Host "Ready to install: $installer"; return }
$process = Start-Process -FilePath $installer -ArgumentList '/quiet' -Wait -PassThru -WindowStyle Hidden
if ($process.ExitCode -notin @(0, 3010)) { throw "Tailscale installation failed: $($process.ExitCode)" }
Write-Host 'Installed. Open Tailscale and sign in with the same account on both computers.'
if ($process.ExitCode -eq 3010) { Write-Host 'Windows reports that a restart is required.' }
