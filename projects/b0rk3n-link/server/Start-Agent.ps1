[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\lib\Link.psm1') -Force
$stateDir = Get-LinkStateDirectory
$configFile = Join-Path $stateDir 'server.json'
if (!(Test-Path -LiteralPath $configFile)) { throw 'Desktop configuration missing. Run server\Setup.ps1 first.' }
$config = Get-Content -LiteralPath $configFile -Raw | ConvertFrom-Json
$logs = Join-Path $stateDir 'logs'
New-Item -ItemType Directory -Path $logs -Force | Out-Null
$logFile = Join-Path $logs 'supervisor.log'
function Write-AgentLog([string]$Message) { ('{0:u} {1}' -f (Get-Date), $Message) | Add-Content -LiteralPath $logFile }
$mutex = New-Object Threading.Mutex($false, 'Local\B0RK3N-Link-Agent')
$ownsMutex = $false
$waitress = $null
$ollamaProcess = $null
try {
    $ownsMutex = $mutex.WaitOne(0)
    if (!$ownsMutex) { Write-AgentLog 'Another B0RK3N Link supervisor is already running.'; return }
    if ($config.PSObject.Properties['mode'] -and $config.mode -eq 'existingService') {
        $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Start the existing AI as your ordinary Windows user, or use the limited-privilege startup task.' }
        Write-AgentLog 'Starting the existing AI through its own launcher.'
        & $config.startScript -NoBrowser
        if (!(Test-LinkTcp '127.0.0.1' $config.port)) { throw 'The existing AI did not open its configured port.' }
        Write-AgentLog 'Existing AI listener ready.'
        while ($true) {
            Start-Sleep -Seconds 30
            if (!(Test-LinkTcp '127.0.0.1' $config.port)) { throw 'The existing AI stopped; Task Scheduler may restart its launcher.' }
        }
    }
    if (Test-LinkTcp '127.0.0.1' $config.port) { throw "Port $($config.port) is already in use. Stop the other web server first." }
    if (!(Test-LinkTcp '127.0.0.1' 11434)) {
        $ollama = Get-Command ollama.exe -ErrorAction SilentlyContinue
        $ollamaPath = $null
        if ($ollama) { $ollamaPath = $ollama.Source }
        if (!$ollamaPath) {
            $candidate = Join-Path $env:LOCALAPPDATA 'Programs\Ollama\ollama.exe'
            if (Test-Path -LiteralPath $candidate) { $ollamaPath = $candidate }
        }
        if (!$ollamaPath) { throw 'Ollama was not found on this desktop. Restore its existing installation.' }
        $env:OLLAMA_HOST = '127.0.0.1:11434'
        $ollamaProcess = Start-Process -FilePath $ollamaPath -ArgumentList 'serve' -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $logs 'ollama.out.log') -RedirectStandardError (Join-Path $logs 'ollama.err.log')
        $ready = $false
        for ($i = 0; $i -lt 30; $i++) {
            if (Test-LinkTcp '127.0.0.1' 11434 -TimeoutMs 300) { $ready = $true; break }
            if ($ollamaProcess.HasExited) { throw 'Ollama exited during startup. Check .local\logs\ollama.err.log.' }
            Start-Sleep -Seconds 1
        }
        if (!$ready) { throw 'Ollama did not become ready within 30 seconds.' }
    }
    $env:FLASK_DEBUG = '0'
    $arguments = @('-m', 'waitress', ("--listen=127.0.0.1:$($config.port)"), '--threads=8', $config.wsgiApp)
    Write-AgentLog "Starting the existing agent with Waitress on loopback port $($config.port)."
    $waitress = Start-Process -FilePath $config.python -ArgumentList $arguments -WorkingDirectory $config.agentFolder -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $logs 'agent.out.log') -RedirectStandardError (Join-Path $logs 'agent.err.log')
    $ready = $false
    for ($i = 0; $i -lt 30; $i++) {
        if ($waitress.HasExited) { throw 'The agent exited during startup. Check .local\logs\agent.err.log and your -WsgiApp setting.' }
        if (Test-LinkTcp '127.0.0.1' $config.port -TimeoutMs 300) { $ready = $true; break }
        Start-Sleep -Seconds 1
    }
    if (!$ready) { throw 'The agent did not become ready within 30 seconds.' }
    Write-AgentLog 'Agent listener ready. Tailscale Serve supplies the private HTTPS endpoint.'
    $waitress.WaitForExit()
    throw "Agent process exited with code $($waitress.ExitCode)."
} catch {
    Write-AgentLog $_.Exception.Message
    Write-Error $_ -ErrorAction Continue
    exit 1
} finally {
    # Stop only processes created by this supervisor.
    if ($waitress -and !$waitress.HasExited) { Stop-Process -Id $waitress.Id -ErrorAction SilentlyContinue }
    if ($ollamaProcess -and !$ollamaProcess.HasExited) { Stop-Process -Id $ollamaProcess.Id -ErrorAction SilentlyContinue }
    if ($ownsMutex) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
