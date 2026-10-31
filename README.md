# homelab

Docker Compose config for the services running on the Raspberry Pi 5.

## Deploy changes

```bash
cd ~/homelab && ./homelab.sh deploy
```

That's it. After pushing **any** change to this repo, that one command pulls
it, applies the host config (systemd, asks for your password), then
downs and ups every service. Safe to run any time; each service is only down
for a few seconds.

| Other situations                 | Run on the Pi                                                |
| -------------------------------- | ------------------------------------------------------------ |
| Get newer image versions         | `./homelab.sh update`                                        |
| Edited `.env` on the Pi          | `./homelab.sh apply`                                         |
| Removing a service from the repo | `./homelab.sh down <service>` **before** deleting its folder |

## Services

| Service        | Folder                | LAN               | Tailnet (HTTPS via Caddy)    |
| -------------- | --------------------- | ----------------- | ---------------------------- |
| Jellyfin       | `apps/jellyfin`       | `http://pi:8096`  | `https://<TS_HOSTNAME>:9003` |
| Audiobookshelf | `apps/audiobookshelf` | `http://pi:13378` | `https://<TS_HOSTNAME>:9004` |
| Home Assistant | `apps/home_assistant` | `http://pi:8123`  | `https://<TS_HOSTNAME>:9002` |
| Dozzle         | `apps/dozzle`         | `http://pi:8080`  | `https://<TS_HOSTNAME>:9001` |
| Caddy          | `apps/caddy`          | n/a               | Serves the HTTPS URLs above  |

Caddy's routes are in `apps/caddy/conf/Caddyfile`. It uses host networking and
the host's `tailscaled` socket for the `*.ts.net` certificate. If Tailscale is
updated or restarted and the HTTPS URLs stop working, run
`./homelab.sh restart caddy`.

## Layout

```
apps/<service>/compose.yml   one Compose project per service
host/                        config installed on the Pi itself (outside Docker)
```

## Storage on the Pi

The repo only holds config. Service data lives outside the checkout:

| Path                   | What                                                        |
| ---------------------- | ----------------------------------------------------------- |
| `/mnt/nvme/<service>/` | App config, databases, cache (local NVMe)                   |
| `/mnt/media/`          | UNAS NFS share: `movies`, `shows`, `audiobooks`, `podcasts` |

`/mnt/media` is mounted from `/etc/fstab` with `x-systemd.automount`.

## Usage (on the Pi)

For changes to this repo, use `./homelab.sh deploy` (see the top of this
file). `homelab.sh` also runs individual Compose commands across every
service, or just one:

```bash
./homelab.sh up                # start everything / apply config changes
./homelab.sh down              # stop everything (data is kept)
./homelab.sh restart           # down, then up
./homelab.sh update            # pull latest images, recreate, prune old images
./homelab.sh ps                # status
./homelab.sh restart jellyfin  # any command can target one service
./homelab.sh logs jellyfin     # follow logs
```

Each service is still its own Compose project, so `docker compose` inside
`apps/<service>` works too.

## Host setup

Config for the Pi itself lives in `host/` and is **symlinked** into place, so
the system reads it straight from this checkout:

| Repo file                                                                | Linked at                                                     | Why                                                                                                                                   |
| ------------------------------------------------------------------------ | ------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| `host/systemd/docker.service.d/wait-for-media.conf`                      | `/etc/systemd/system/docker.service.d/`                       | Start Docker after the UNAS share mounts. Without it, Jellyfin and Audiobookshelf fail at boot with `open /mnt/media: no such device` |
| `host/systemd/docker.service.d/after-tailscale.conf`                     | `/etc/systemd/system/docker.service.d/`                       | Start Docker after Tailscale, so Caddy can reach `tailscaled` for certificates                                                        |
| `host/systemd/systemd-networkd-wait-online.service.d/wait-for-eth0.conf` | `/etc/systemd/system/systemd-networkd-wait-online.service.d/` | Make `network-online.target` wait for eth0 (netplan marks it optional, so it otherwise doesn't wait)                                  |

Private values (e.g. the tailnet hostname, used by Caddy) live in a gitignored
`.env` at the repo root. Create it once:

```bash
cp .env.example .env && nano .env
```

Then set up the links. Re-run this after pulling changes to `host/` or `.env`:

```bash
sudo ./host/install.sh
```

It's safe to re-run, and `./homelab.sh deploy` runs it for you. It also checks
`.env` has a real `TS_HOSTNAME`.

Because these are links, moving or deleting `~/homelab` breaks them. Re-run
`install.sh` from the new location.
