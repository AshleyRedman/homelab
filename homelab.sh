#!/usr/bin/env bash
# Run a Docker Compose command across every service in apps/, or just one.
#
# Usage: ./homelab.sh <command> [service]
#
#   up        start services, applying any config changes
#   down      stop and remove containers (data is kept)
#   restart   down, then up
#   update    pull latest images, recreate what changed, prune old images
#   ps        show container status
#   logs      follow logs (service required)
#
# Services: the folder names in apps/, e.g. ./homelab.sh restart jellyfin
set -euo pipefail

apps_dir="$(cd "$(dirname "$0")/apps" && pwd)"

usage() {
    sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
}

compose() {
    local service="$1"
    shift
    docker compose -f "$apps_dir/$service/compose.yml" "$@"
}

cmd="${1:-}"
target="${2:-}"

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
