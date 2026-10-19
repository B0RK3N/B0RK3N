# B0RK3N Link

**Your desktop runs the AI. Your laptop goes anywhere.**

A Windows toolkit for reaching an existing Flask/Ollama AI agent and desktop applications through a private Tailscale connection. The laptop runs a native launcher; the desktop keeps the models, memory, and processing.

> Setup is not yet complete on the owner's computers. The laptop disconnected during development. The source and automated checks are provided here; Tailscale sign-in, desktop setup, and an actual AI/RDP connection still need to be completed on the two computers.

| Desktop server | Laptop client |
| --- | --- |
| Existing Flask agent and Ollama | Windows PowerShell, browser, built-in RDP |
| Waitress on loopback | Native B0RK3N Link launcher |
| Tailscale Serve private HTTPS | Tailscale signed in to the same account |
| Optional RDP host and sign-in startup task | AI access, full desktop, explicit file-transfer session |

The project wraps the existing agent. It does not contain its original code, models, database, or chat history. The AI retains the tools already implemented in that agent; this toolkit does not grant the AI unrestricted PC control. No Python installation or AI model is needed on the laptop.

## Features

- Open the desktop's AI in the laptop browser across different Wi-Fi networks.
- Use desktop applications and files through Windows Remote Desktop.
- Copy files between devices using an explicit clipboard-sharing RDP session, subject to Windows policies and file-size limits.
- Start the desktop agent after the Windows account signs in, with startup logs and retry handling.
- Check connection ports, reject invalid configuration, and undo recorded desktop settings.

The desktop must remain **powered on, awake, and online**. This project cannot wake a powered-off computer over the internet.

## Desktop setup

Keep this project in a permanent folder. Do not move it after registering startup.

1. On the **desktop**, open Windows PowerShell **as Administrator**, then change to this project folder.
2. Install Tailscale if it is not already installed:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Install-Tailscale.ps1
   ```

   The script downloads the official vendor installer and checks its Authenticode signature before execution.
3. Open Tailscale and sign in. Use the **same account** on both computers. Enable MagicDNS and HTTPS when Tailscale requests it. Initial HTTPS authorization can require following the URL printed by Tailscale and rerunning setup.
4. Stop the old agent web server if it occupies port 5000. Leave Ollama installed and its models in place.
5. Run:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\server\Setup.ps1 -AgentFolder 'C:\B0RK3N-WebAI' -WsgiApp 'app:app' -EnableRemoteDesktop -RegisterAutoStart
   ```

   `app:app` means Flask object `app` in `app.py`. Change `-WsgiApp` if the existing project uses another entry point, such as `server:app`. The default folder and entry point come from the previous project context; the current desktop source has not been inspected. The script checks the module file, and logs import/startup failures.
6. Prevent plugged-in sleep if continuous access is wanted: **Settings > System > Power & battery > Screen, sleep & hibernate timeouts**. The setup script does not change power settings.
7. In Tailscale on the desktop, enable **Preferences > Run unattended** to reach the Windows sign-in screen after reboot. The **AI starts after Windows sign-in**, not before; this toolkit never enables automatic Windows login.
8. Copy the generated `.local\client.json` to the laptop, or note the complete `.ts.net` hostname printed by setup.

RDP hosting needs Windows **Pro, Enterprise, Education, or Server** on the desktop. The laptop may use Windows Home. For AI-only access on a Home desktop, omit `-EnableRemoteDesktop`. Use the desktop Windows account password for RDP; a Windows Hello PIN is not necessarily that password. The account must already have remote-login rights. No account or password is created or changed. A desktop RDP session can lock the physical console; it is not shared-screen gaming.

## Laptop setup

1. Install Tailscale with `tools\Install-Tailscale.ps1` in an Administrator PowerShell window. Sign in to the same account used on the desktop.
2. Import the copied desktop configuration with its actual path:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\client\Setup.ps1 -ServerConfig 'C:\path\to\client.json'
   ```

   Alternatively, double-click **SETUP-LAPTOP.cmd** and enter the desktop's full Tailscale hostname.
3. Double-click **START.cmd** and choose AI, desktop, file transfer, or connection checks.

An ordinary desktop session keeps clipboard forwarding off. The file-transfer session enables clipboard sharing explicitly; open File Explorer on the remote desktop, copy a file on one computer, and paste on the other. Entire local drives are never automatically redirected.

Headless diagnostics:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\client\Launch.ps1 -Diagnose
```

Diagnostics check TCP listeners. A reachable HTTPS port does not prove the Flask backend works. Open the AI and send a message to verify the full path.

## Access and privacy

- The HTTPS endpoint uses **Tailscale Serve**, subject to tailnet access rules. It is not a public website. Funnel and router port forwarding are not enabled.
- Use a tailnet containing only people/devices trusted with the agent. Review sharing and grants before adding others. Tailscale authentication is the remote AI access boundary; the toolkit does not add another application password.
- Waitress and a newly started Ollama server listen on loopback. The Ollama API is not published. A pre-existing Ollama process keeps its own configuration.
- Desktop setup enforces RDP Network Level Authentication. Its TCP/UDP 3389 firewall rules match Tailscale local addresses and remote address ranges. It records and disables the two standard broad RDP user-mode firewall rules. Other custom rules are not audited.
- The launcher retains RDP server identity warnings and never automatically accepts certificate warnings.
- Windows credentials go into the RDP dialog; no password is written into source or configuration.
- Generated configuration, RDP files, installer downloads, and logs are stored in ignored `.local\` directories. The real agent folder, memory, credentials, and model weights are not uploaded.

## Startup and recovery

`-RegisterAutoStart` creates a limited-privilege sign-in task named `B0RK3N-Link-Agent`. The supervisor starts Ollama if no local listener exists, then starts the existing Flask app with Waitress. It refuses to take over an occupied agent port. Startup failures are recorded in `.local\logs\`; Task Scheduler can retry five times at one-minute intervals.

To start manually without the task:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\server\Start-Agent.ps1
```

To undo project desktop settings, run as Administrator:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\server\Remove-Setup.ps1
```

Removal restores recorded RDP/NLA and standard firewall settings, removes project firewall rules and the startup task, and disables the project's HTTPS port. Keep `.local\desktop-state.json` until removal finishes. It retains agent files, installed Waitress, Ollama, Tailscale, models, and logs. Close a manually started supervisor separately. Do not add unrelated Serve routes to this project's HTTPS port before removal.

## Validation

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-Tests.ps1
```

Checks cover PowerShell parsing, private-host and HTTPS restrictions, imported configuration, RDP configuration injection, password/clipboard behavior, and a real temporary TCP listener. They do not alter registry, firewall, services, accounts, or Tailscale. They do not replace deployment testing on the actual computers.

See [SETUP-STATUS.md](SETUP-STATUS.md) for the handoff state.

## Official references

- [Tailscale Windows installation](https://tailscale.com/docs/install/windows)
- [Private HTTPS with Serve](https://tailscale.com/docs/features/tailscale-serve)
- [Serve CLI reference](https://tailscale.com/docs/reference/tailscale-cli/serve)
- [RDP through Tailscale](https://tailscale.com/docs/solutions/access-remote-desktops-using-windows-rdp)
- [Unattended Tailscale](https://tailscale.com/docs/how-to/run-unattended)
- [Waitress documentation](https://docs.pylonsproject.org/projects/waitress/en/stable/)

Built by B0RK3N with AI assistance. [MIT License](LICENSE).
