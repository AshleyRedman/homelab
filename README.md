# homelab

Docker Compose config for the services running on the Raspberry Pi 5.

| Service        | Folder                | URL                 |
| -------------- | --------------------- | ------------------- |
| Jellyfin       | `apps/jellyfin`       | `http://<pi>:8096`  |
| Audiobookshelf | `apps/audiobookshelf` | `http://<pi>:13378` |
| Home Assistant | `apps/home_assistant` | `http://<pi>:8123`  |

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

`homelab.sh` runs a Compose command across every service, or just one:

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

### Start Docker after the UNAS share is mounted

Without this, Jellyfin and Audiobookshelf fail at boot with
`open /mnt/media: no such device`. Docker starts before the NFS mount is ready
and doesn't retry.

```bash
sudo mkdir -p /etc/systemd/system/docker.service.d
sudo cp host/systemd/docker.service.d/wait-for-media.conf /etc/systemd/system/docker.service.d/
sudo systemctl daemon-reload
```

`network-online.target` only waits for the network if a wait-online service is
enabled. Check it with:

```bash
systemctl is-enabled NetworkManager-wait-online.service
```

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
