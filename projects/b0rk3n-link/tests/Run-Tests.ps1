[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'lib\Link.psm1') -Force
$script:passed = 0
function Assert-True([bool]$Condition, [string]$Message) {
    if (!$Condition) { throw "FAIL: $Message" }
    $script:passed++
    Write-Host "PASS: $Message"
}
function Assert-Throws([scriptblock]$Action, [string]$Message) {
    $threw = $false
    try { & $Action | Out-Null } catch { $threw = $true }
    Assert-True $threw $Message
}
foreach ($file in Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object { $_.Extension -in @('.ps1', '.psm1') -and $_.FullName -notmatch '[\\/]\.local[\\/]' }) {
    $tokens = $null
    $errors = $null
    $null = [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
    $detail = ''
    if ($errors.Count) { $detail = ': ' + ($errors.Message -join ', ') }
    Assert-True ($errors.Count -eq 0) ("PowerShell parses: " + $file.Name + $detail)
}
foreach ($name in @('100.64.0.1', '100.127.255.254', 'pc.tail12345.ts.net')) {
    Assert-True (Test-LinkHost $name) "Accept private Tailscale host: $name"
}
$injectedHost = 'pc.tail12345.ts.net' + [char]10 + 'full address:s:evil'
foreach ($name in @('', 'localhost', '127.0.0.1', '192.168.1.2', '8.8.8.8', '100.63.255.255', '100.128.0.0', 'pc.ts.net.evil.com', '-pc.tail12345.ts.net', $injectedHost, 'pc.tail12345.ts.net/extra', '::1')) {
    Assert-True (!(Test-LinkHost $name)) "Reject untrusted host: $($name.Replace([string][char]10, '[newline]'))"
}
Assert-True (Test-LinkAiUrl 'https://pc.tail12345.ts.net/') 'Accept private HTTPS AI URL'
foreach ($url in @('http://pc.tail12345.ts.net/', 'https://evil.com/', 'https://pc.tail12345.ts.net:8443/', 'https://user:pass@pc.tail12345.ts.net/', 'https://pc.tail12345.ts.net/?key=test', 'file:///C:/Windows', 'https://pc.tail12345.ts.net/path', 'javascript:alert(1)')) {
    Assert-True (!(Test-LinkAiUrl $url)) "Reject unsafe AI URL: $url"
}
$rdp = New-LinkRdpContent -ServerHost '100.64.0.1'
Assert-True ($rdp.Contains('authentication level:i:2')) 'RDP retains server authentication warnings'
Assert-True ($rdp.Contains('enablecredsspsupport:i:1')) 'RDP uses Network Level Authentication'
Assert-True ($rdp.Contains('redirectclipboard:i:0')) 'Clipboard off for normal desktop sessions'
Assert-True ($rdp.Contains('drivestoredirect:s:' + [Environment]::NewLine)) 'No local drive redirected'
Assert-True (!$rdp.Contains('password')) 'RDP file never stores a password'
$transfer = New-LinkRdpContent -ServerHost '100.64.0.1' -FileTransfer
Assert-True ($transfer.Contains('redirectclipboard:i:1')) 'File transfer explicitly enables clipboard'
Assert-Throws { New-LinkRdpContent -ServerHost '8.8.8.8' } 'RDP rejects public address'
$injectedUser = 'a' + [char]10 + 'redirectclipboard:i:1'
Assert-Throws { New-LinkRdpContent -ServerHost '100.64.0.1' -Username $injectedUser } 'RDP rejects configuration injection'
$temp = Join-Path ([IO.Path]::GetTempPath()) ('b0rk3n-link-tests-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp | Out-Null
try {
    $path = Join-Path $temp 'client.json'
    Save-LinkJson -Value @{ serverHost = 'pc.tail12345.ts.net'; aiUrl = 'https://pc.tail12345.ts.net/'; username = '' } -Path $path
    $config = Read-LinkClientConfig -Path $path
    Assert-True ($config.serverHost -eq 'pc.tail12345.ts.net') 'Client config round-trips'
    Save-LinkJson -Value @{ serverHost = 'pc.tail12345.ts.net'; aiUrl = 'https://evil.com/'; username = '' } -Path $path
    Assert-Throws { Read-LinkClientConfig -Path $path } 'Imported config rejects external URL'
    Save-LinkJson -Value @{ serverHost = 'pc.tail12345.ts.net'; aiUrl = 'https://pc.tail12345.ts.net/'; username = $injectedUser } -Path $path
    Assert-Throws { Read-LinkClientConfig -Path $path } 'Imported config rejects newline injection'
    Set-Content -LiteralPath $path -Value 'not JSON'
    Assert-Throws { Read-LinkClientConfig -Path $path } 'Malformed config fails closed'
    Assert-Throws { Read-LinkClientConfig -Path (Join-Path $temp 'missing.json') } 'Missing config reports setup requirement'
} finally {
    Get-ChildItem -LiteralPath $temp -File | Remove-Item
    Remove-Item -LiteralPath $temp
}
$listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
$listener.Start()
$port = $listener.LocalEndpoint.Port
try { Assert-True (Test-LinkTcp '127.0.0.1' $port) 'Connection check detects listening service' } finally { $listener.Stop() }
Assert-True (!(Test-LinkTcp '127.0.0.1' $port -TimeoutMs 250)) 'Connection check detects stopped service'
Write-Host "All $script:passed checks passed. No desktop, registry, firewall, or Tailscale settings changed."
