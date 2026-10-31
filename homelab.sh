#!/usr/bin/env bash
# Run a Docker Compose command across every service in apps/, or just one.
#
# Usage: ./homelab.sh <command> [service]
#
#   deploy    git pull, then apply (the one command after pushing changes)
#   apply     apply host config (sudo host/install.sh), then restart all
#   up        start services, applying any config changes
#   down      stop and remove containers (data is kept)
#   restart   down, then up
#   update    pull latest images, recreate what changed, prune old images
#   ps        show container status
#   logs      follow logs (service required)
#
# Services: the folder names in apps/, e.g. ./homelab.sh restart jellyfin
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")" && pwd)"
apps_dir="$repo_dir/apps"

usage() {
    sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
}

compose() {
    local service="$1"
    shift
    docker compose -f "$apps_dir/$service/compose.yml" "$@"
}

cmd="${1:-}"
target="${2:-}"

if [[ "$cmd" == "deploy" ]]; then
    echo "==> git pull"
    git -C "$repo_dir" pull --ff-only
    # Re-exec so the rest runs from the freshly pulled copy of this script.
    exec "$repo_dir/homelab.sh" apply
fi

if [[ "$cmd" == "apply" ]]; then
    echo "==> host config"
    sudo "$repo_dir/host/install.sh"
    cmd=restart
    target=""
fi

if [[ -n "$target" ]]; then
    if [[ ! -f "$apps_dir/$target/compose.yml" ]]; then
        echo "Unknown service: $target" >&2
        echo "Available: $(cd "$apps_dir" && ls -d */ | tr -d / | xargs)" >&2
        exit 1
    fi
    services=("$target")
else
    services=()
    for dir in "$apps_dir"/*/; do
        [[ -f "$dir/compose.yml" ]] && services+=("$(basename "$dir")")
    done
fi

for service in "${services[@]}"; do
    case "$cmd" in
        up)
            echo "==> $service: up"
            compose "$service" up -d --remove-orphans
            ;;
        down)
            echo "==> $service: down"
            compose "$service" down
            ;;
        restart)
            echo "==> $service: restart"
            compose "$service" down
            compose "$service" up -d --remove-orphans
            ;;
        update)
            echo "==> $service: update"
            compose "$service" pull
            compose "$service" up -d --remove-orphans
            ;;
        ps)
            echo "==> $service"
            compose "$service" ps
            ;;
        logs)
            [[ -n "$target" ]] || { echo "logs needs a service" >&2; exit 1; }
            compose "$service" logs -f --tail=100
            ;;
        *)
            usage
            ;;
    esac
done

if [[ "$cmd" == "update" ]]; then
    echo "==> pruning unused images"
    docker image prune -f
fi
