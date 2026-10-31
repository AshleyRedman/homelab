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

if ! grep -qE '^TS_HOSTNAME=.+' "$env_file" 2>/dev/null; then
    echo "$env_file is missing or has no TS_HOSTNAME. Copy .env.example to .env and fill it in." >&2
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

# --- systemd ---------------------------------------------------------------

link systemd/docker.service.d/wait-for-media.conf \
    /etc/systemd/system/docker.service.d/wait-for-media.conf
link systemd/systemd-networkd-wait-online.service.d/wait-for-eth0.conf \
    /etc/systemd/system/systemd-networkd-wait-online.service.d/wait-for-eth0.conf

systemctl daemon-reload
systemctl enable --quiet systemd-networkd-wait-online.service

# --- caddy -----------------------------------------------------------------

# Caddy runs as the caddy user, so it needs to read the repo inside the home
# directory. Adding it to the repo owner's group covers the default 750 home.
repo_group="$(stat -c %G "$host_dir")"
caddy_restart=reload
if ! id -nG caddy | tr ' ' '\n' | grep -qx "$repo_group"; then
    usermod -aG "$repo_group" caddy
    echo "added caddy to group $repo_group"
    caddy_restart=restart # new group only applies to a fresh process
fi

if ! sudo -u caddy test -r "$host_dir/caddy/Caddyfile"; then
    echo "caddy user can't read $host_dir/caddy/Caddyfile; leaving /etc/caddy/Caddyfile as is." >&2
    echo "Check permissions on the path, e.g. ls -ld $(dirname "$repo_dir")" >&2
    exit 1
fi

# Check the Caddyfile parses with .env applied before switching Caddy to it.
if ! (set -a && . "$env_file" && caddy adapt --config "$host_dir/caddy/Caddyfile" >/dev/null); then
    echo "Caddyfile is invalid; leaving Caddy as is." >&2
    exit 1
fi

# Load .env into caddy.service (systemd reads it as root, so no permission
# issue). Generated rather than linked because it contains the repo path.
caddy_dropin=/etc/systemd/system/caddy.service.d/homelab-env.conf
mkdir -p "$(dirname "$caddy_dropin")"
printf '[Service]\nEnvironmentFile=%s\n' "$env_file" >"$caddy_dropin"
systemctl daemon-reload

link caddy/Caddyfile /etc/caddy/Caddyfile

# On a bad Caddyfile, reload fails and Caddy keeps serving the previous config.
systemctl "$caddy_restart" caddy
echo "caddy ${caddy_restart}ed"
