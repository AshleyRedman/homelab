#!/usr/bin/env bash
# Link host config from this repo into the system, then reload what uses it.
# Safe to re-run: do it after cloning, and after pulling changes to host/.
#
# Usage: sudo ./host/install.sh
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Run with sudo: sudo $0" >&2
    exit 1
fi

host_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(dirname "$host_dir")"
env_file="$repo_dir/.env"

# .env is used by apps/caddy. Checked here because this runs on every deploy.
if ! grep -qE '^TS_HOSTNAME=.+' "$env_file" 2>/dev/null; then
    echo "$env_file is missing or has no TS_HOSTNAME. Copy .env.example to .env and fill it in." >&2
    exit 1
fi

if grep -q 'your-tailnet' "$env_file"; then
    echo "$env_file still has the placeholder TS_HOSTNAME from .env.example. Set the real one." >&2
    exit 1
fi

# Point $2 at $host_dir/$1. An existing real file is removed if identical,
# otherwise kept as <file>.pre-homelab.
link() {
    local src="$host_dir/$1" dest="$2"
    mkdir -p "$(dirname "$dest")"
    if [[ -e "$dest" && ! -L "$dest" ]]; then
        if cmp -s "$src" "$dest"; then
            rm "$dest"
        else
            mv "$dest" "$dest.pre-homelab"
            echo "backed up $dest -> $dest.pre-homelab"
        fi
    fi
    ln -sfn "$src" "$dest"
    echo "linked $dest -> $src"
}

link systemd/docker.service.d/wait-for-media.conf \
    /etc/systemd/system/docker.service.d/wait-for-media.conf
link systemd/docker.service.d/after-tailscale.conf \
    /etc/systemd/system/docker.service.d/after-tailscale.conf
link systemd/systemd-networkd-wait-online.service.d/wait-for-eth0.conf \
    /etc/systemd/system/systemd-networkd-wait-online.service.d/wait-for-eth0.conf

systemctl daemon-reload
systemctl enable --quiet systemd-networkd-wait-online.service
