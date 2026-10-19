[CmdletBinding()]
param([switch]$Diagnose)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\lib\Link.psm1') -Force

if ($Diagnose) {
    try {
        $config = Read-LinkClientConfig
        $null = Get-LinkTailscaleStatus
        [pscustomobject]@{ configured = $true; aiPortReachable = (Test-LinkTcp $config.serverHost 443); desktopPortReachable = (Test-LinkTcp $config.serverHost 3389) } | ConvertTo-Json
    } catch { [pscustomobject]@{ configured = $false; message = $_.Exception.Message } | ConvertTo-Json; exit 1 }
    exit 0
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
$script:config = $null
$form = New-Object Windows.Forms.Form
$form.Text = 'B0RK3N Link'
$form.ClientSize = New-Object Drawing.Size(680, 520)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.BackColor = [Drawing.Color]::FromArgb(14, 20, 29)
$form.ForeColor = [Drawing.Color]::FromArgb(233, 241, 247)
$form.Font = New-Object Drawing.Font('Segoe UI', 10)

function Add-LinkText([string]$Text, [int]$X, [int]$Y, [int]$Width, [int]$Height, [int]$Size) {
    $label = New-Object Windows.Forms.Label
    $label.Text = $Text
    $label.Location = New-Object Drawing.Point($X, $Y)
    $label.Size = New-Object Drawing.Size($Width, $Height)
    $label.Font = New-Object Drawing.Font('Segoe UI', $Size)
    $form.Controls.Add($label)
    return $label
}
$null = Add-LinkText 'B0RK3N / LINK' 32 26 600 34 21
$null = Add-LinkText 'Your desktop. Wherever you are.' 34 68 600 30 12
$statusLabel = Add-LinkText 'Ready for desktop setup.' 34 118 610 64 10
$statusLabel.ForeColor = [Drawing.Color]::FromArgb(111, 225, 208)

function Add-LinkButton([string]$Text, [int]$Y, [scriptblock]$Action) {
    $button = New-Object Windows.Forms.Button
    $button.Text = $Text
    $button.Location = New-Object Drawing.Point(32, $Y)
    $button.Size = New-Object Drawing.Size(616, 54)
    $button.FlatStyle = 'Flat'
    $button.FlatAppearance.BorderColor = [Drawing.Color]::FromArgb(50, 78, 92)
    $button.BackColor = [Drawing.Color]::FromArgb(24, 36, 49)
    $button.TextAlign = 'MiddleLeft'
    $button.Padding = New-Object Windows.Forms.Padding(14, 0, 0, 0)
    $button.Add_Click($Action)
    $form.Controls.Add($button)
}
function Require-LinkDesktop {
    $script:config = Read-LinkClientConfig
    $null = Get-LinkTailscaleStatus
}
function Show-LinkError($ErrorRecord) {
    [Windows.Forms.MessageBox]::Show($ErrorRecord.Exception.Message, 'B0RK3N Link', 'OK', 'Information') | Out-Null
}
Add-LinkButton '01   Open AI agent' 196 {
    try {
        Require-LinkDesktop
        if (!(Test-LinkTcp $script:config.serverHost 443)) { throw 'AI connection unavailable. Check desktop power, Tailscale, and desktop setup.' }
        Start-Process -FilePath $script:config.aiUrl
    } catch { Show-LinkError $_ }
}
Add-LinkButton '02   Full desktop and applications' 260 {
    try { Require-LinkDesktop; Open-LinkDesktop -Config $script:config } catch { Show-LinkError $_ }
}
Add-LinkButton '03   File transfer session' 324 {
    try {
        Require-LinkDesktop
        [Windows.Forms.MessageBox]::Show('This session enables clipboard sharing. In the remote desktop, open File Explorer. Copy a file on one computer and paste it on the other. Windows policy and file-size limits can apply. No whole drive is shared.', 'File transfer', 'OK', 'Information') | Out-Null
        Open-LinkDesktop -Config $script:config -FileTransfer
    } catch { Show-LinkError $_ }
}
Add-LinkButton '04   Check connection' 388 {
    try {
        Require-LinkDesktop
        $ai = Test-LinkTcp $script:config.serverHost 443
        $rdp = Test-LinkTcp $script:config.serverHost 3389
        $statusLabel.Text = "Tailscale connected | AI port: $ai | Remote Desktop port: $rdp" + [Environment]::NewLine + $script:config.serverHost
    } catch { $statusLabel.Text = $_.Exception.Message }
}
$null = Add-LinkText 'Private connection / Desktop powered on / No model needed on laptop' 34 467 610 28 9
try {
    $script:config = Read-LinkClientConfig
    $statusLabel.Text = 'Configured desktop:' + [Environment]::NewLine + $script:config.serverHost
} catch { $statusLabel.Text = $_.Exception.Message }
[Windows.Forms.Application]::Run($form)
