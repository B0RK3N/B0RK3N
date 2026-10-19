# Setup handoff — 19 October 2026

The owner's Windows desktop is configured for private access to the existing Open WebUI assistant. Laptop pairing and a connection from another network remain to be verified.

| Item | State |
| --- | --- |
| Current desktop assistant | Existing Open WebUI, local tools, Ollama models and conversations retained |
| Tailscale on desktop | Installed and connected; unattended mode enabled |
| Private HTTPS | Tailscale Serve forwards to loopback port 8080; health check and actual AI reply passed |
| Remote Desktop | Enabled with NLA and Tailscale-scoped firewall rules; TCP connection check passed |
| Automatic AI startup | Limited-privilege Windows sign-in task running |
| Desktop availability | Plugged-in sleep and hibernation disabled |
| Source checks | All 48 checks passed locally on Windows |
| Laptop package | Prepared locally with private client configuration; not published |
| Laptop connection from another network | Not yet tested |
| Actual RDP login and file transfer from laptop | Not yet tested |

The ExistingServiceStartScript option supports the current assistant without requiring an obsolete Flask directory. Its PowerShell launcher must support -NoBrowser. The Flask setup remains available.

Private addresses, local paths, credentials, agent memory, model files, and personal data are excluded from this repository. The laptop package and detailed connection instructions remain on the owner's desktop. Download this source for a generic installation; use the private package for the already-configured laptop client.

Keep the desktop on and online. The AI starts after Windows sign-in; unattended Tailscale and RDP provide access to sign in remotely after a reboot.
