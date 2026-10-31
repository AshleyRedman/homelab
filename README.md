# homelab

Docker Compose config for the services running on the Raspberry Pi 5.

## Changed something? Run this on the Pi

```bash
cd ~/homelab && ./homelab.sh deploy
```

That's it. After pushing **any** change to this repo, that one command pulls
it, applies the host config (Caddy and systemd, asks for your password), then
downs and ups every service. Safe to run any time; each service is only down
for a few seconds.

| Other situations                 | Run on the Pi                                                |
| -------------------------------- | ------------------------------------------------------------ |
| Get newer image versions         | `./homelab.sh update`                                        |
| Edited `.env` on the Pi          | `./homelab.sh apply`                                         |
| Removing a service from the repo | `./homelab.sh down <service>` **before** deleting its folder |

## Services

| Service        | Folder                | LAN                     | Tailnet (HTTPS via Caddy)              |
| -------------- | --------------------- | ----------------------- | -------------------------------------- |
| Jellyfin       | `apps/jellyfin`       | `http://pi:8096`        | `https://<TS_HOSTNAME>/jellyfin`       |
| Audiobookshelf | `apps/audiobookshelf` | `http://pi:13378`       | `https://<TS_HOSTNAME>/audiobookshelf` |
| Home Assistant | `apps/home_assistant` | `http://pi:8123`        | `https://<TS_HOSTNAME>:8443`           |
| Dozzle         | `apps/dozzle`         | `http://pi:8080/dozzle` | `https://<TS_HOSTNAME>/dozzle`         |

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
| `host/caddy/Caddyfile`                                                   | `/etc/caddy/Caddyfile`                                        | HTTPS on the tailnet name (Caddy is installed via apt, not Docker)                                                                    |
| `host/systemd/docker.service.d/wait-for-media.conf`                      | `/etc/systemd/system/docker.service.d/`                       | Start Docker after the UNAS share mounts. Without it, Jellyfin and Audiobookshelf fail at boot with `open /mnt/media: no such device` |
| `host/systemd/systemd-networkd-wait-online.service.d/wait-for-eth0.conf` | `/etc/systemd/system/systemd-networkd-wait-online.service.d/` | Make `network-online.target` wait for eth0 (netplan marks it optional, so it otherwise doesn't wait)                                  |

Private values (e.g. the tailnet hostname) live in a gitignored `.env` at the
repo root. Create it once:

```bash
cp .env.example .env && nano .env
```

Then set up the links. Re-run this after pulling changes to `host/` or `.env`:

```bash
sudo ./host/install.sh
```

It's safe to re-run. It reloads systemd and Caddy, gives the `caddy` user
read access to the checkout, and loads `.env` into `caddy.service` via
`/etc/systemd/system/caddy.service.d/homelab-env.conf`. If the Caddyfile is invalid, Caddy keeps serving
its previous config.

Because these are links, moving or deleting `~/homelab` breaks them. Re-run
`install.sh` from the new location.

## One-time migration from `~/<service>` folders

Audiobookshelf and Home Assistant used to keep their data in `./config` and
`./metadata` next to their compose file. They now use `/mnt/nvme/<service>/`.

The old folders are **copied**, not moved, so they stay as a rollback. Do one
service at a time; each is only down for the length of the copy.

```bash
# 0. Backup of everything in the old folders
sudo tar czf /mnt/nvme/pre-homelab-backup.tgz -C /home/pi audiobookshelf home-automation jellyfin

# 1. Audiobookshelf
cd ~/audiobookshelf && docker compose down
sudo mkdir -p /mnt/nvme/audiobookshelf
sudo cp -a ~/audiobookshelf/config ~/audiobookshelf/metadata /mnt/nvme/audiobookshelf/
cd ~/homelab/apps/audiobookshelf && docker compose up -d

# 2. Home Assistant
cd ~/home-automation && docker compose down
sudo mkdir -p /mnt/nvme/homeassistant
sudo cp -a ~/home-automation/config /mnt/nvme/homeassistant/
cd ~/homelab/apps/home_assistant && docker compose up -d

# 3. Jellyfin (data already on /mnt/nvme)
cd ~/jellyfin && docker compose down
cd ~/homelab/apps/jellyfin && docker compose up -d
```

Rollback for a service: `docker compose down` in `~/homelab/apps/<service>`,
then `docker compose up -d` in the old folder.

Once everything has run fine for a week or so, delete the old folders and the
backup tarball.
