# Security policy

This repo is the config for a personal homelab, public for reference only.
There are no releases; only the latest commit on `main` is supported.

## Reporting a vulnerability

Please report it privately through
[GitHub's private vulnerability reporting](https://github.com/AshleyRedman/homelab/security/advisories/new).

Useful things to include:

- What the problem is and which file or service it affects
- How to reproduce it, or a proof of concept
- What an attacker could do with it

I'll aim to reply within a week. This is a hobby project, so there's no bug
bounty, but I'll credit you in the advisory if you'd like.

## In scope

- Secrets or credentials committed to the repo
- Config in this repo that exposes a service more widely than intended (for
  example, to the internet rather than the LAN or tailnet)
- Problems in `homelab.sh` or `host/` that could be abused on the host

## Out of scope

Vulnerabilities in the upstream software itself (Jellyfin, Home Assistant,
Caddy, etc.). Please report those to the relevant project.
