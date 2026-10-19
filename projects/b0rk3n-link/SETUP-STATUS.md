# Setup handoff — 19 October 2026

The source is prepared. The actual remote connection is **not active yet**.

| Item | State |
| --- | --- |
| Desktop-server / laptop-client design | Prepared |
| Native laptop launcher and setup scripts | Prepared |
| Private HTTPS, RDP, startup, and removal scripts | Prepared |
| Unit and syntax checks | 47 checks passed on a hosted Windows runner |
| Existing desktop Flask entry point | Not inspected; app:app is a configurable default |
| Tailscale installed and signed in on laptop | Not completed |
| Tailscale installed and signed in on desktop | Not completed |
| Desktop RDP and AI startup configuration | Not applied |
| Cross-network AI message, desktop, file transfer | Not tested |

The laptop environment disconnected while local files were being written, so its local folder may be incomplete. Download the committed project to get the authoritative copy.

When both computers are available, follow README.md: install/sign in to Tailscale on both, run desktop setup once, import its generated configuration on the laptop, then launch START.cmd. The desktop must stay on and awake.

No agent memory, models, passwords, tokens, personal files, or generated private configuration were included in the published source.

Validation: [Windows checks — passed](https://github.com/B0RK3N/B0RK3N/actions/runs/39209676719). This validates source parsing, configuration boundaries, RDP settings, and TCP checks; it does not validate the actual desktop installation or remote connection.
