# Reclaimer LAN server scripts

PowerShell scripts for running a [Project Reclaimer](https://projectreclaimer.dev) dedicated server for Halo 3 and Halo 3: ODST on a LAN. Project Reclaimer is a community project that runs the Halo MCC games on dedicated servers. The scripts download the executables, set up a server folder, write the config and start the server.

Two modes are supported:

- **Campaign co-op**: Halo 3 or ODST on Legendary, with extra enemy health and damage per added player.
- **Multiplayer**: a 60-game playlist that players vote on between games.

## Requirements

- Windows with PowerShell 5.1 or later.
- Halo: The Master Chief Collection installed, with Halo 3 and ODST. The first run copies the game files it needs from that install. The server folder is git-ignored so those files are never redistributed.
- Internet access for `update-binaries.ps1` (GitHub releases).

The scripts look for MCC at `D:\SteamLibrary\steamapps\common\Halo The Master Chief Collection`. If yours is elsewhere, set the `RECLAIMER_MCC_DIR` environment variable or pass `-MccDir`.

## Quick start

```powershell
.\update-binaries.ps1      # download the Project Reclaimer executables
.\start-campaign.ps1       # or .\start-multiplayer.ps1
```

When the server starts it prints a line like `LAN players: Direct Connect to 192.168.1.20:12345`. Players on the LAN use Direct Connect in the Project Reclaimer client with that address. The server is hidden: it isn't listed publicly, and UPnP and port forwarding are off.

The campaign server uses port 12345 and multiplayer 12346 (set in `reclaimer.config.json`), so both can run at once.

## Scripts

### `update-binaries.ps1`

Downloads the latest client, dedicated server, customization editor and RCON client from the Project Reclaimer GitHub releases. Each file is checked against the SHA-256 that GitHub publishes. Files that are already current are skipped.

| Parameter | Purpose |
|---|---|
| `-Dir` | Where to put the executables (default: this folder) |
| `-RemoveOld` | Delete older versions after downloading a newer one |

The other scripts use the newest `*-vX.Y.Z.exe` in this folder.

### `start-campaign.ps1`

Starts campaign co-op. It asks which mission to start on, from the list of Halo 3 and ODST missions. Pass `-Mission <number>` to skip the menu.

Settings (in `reclaimer.config.json`):

- Difficulty: Legendary
- Friendly fire and voice chat: off
- Enemy scaling: per extra player, from the config file
- Sprint: on
- Skulls: Cowbell, Grunt Birthday Party and IWHBYD
- Custom characters (Halo 3 only; ODST uses each player's trooper)
- Up to 16 players

| Parameter | Default |
|---|---|
| `-Name` | `Legendary Co-op` |
| `-Port` | config (`12345`) |
| `-Mission` | prompt |
| `-ServerDir` | `.\campaign-server` |
| `-MccDir` | `$env:RECLAIMER_MCC_DIR`, or the Steam path above |

### `start-multiplayer.ps1`

Starts a multiplayer playlist: One in the Chamber, Gun Game, Slayer, King of the Hill, Infection and Juggernaut on the ten smallest Halo 3 maps (Heretic, Guardian, Construct, Epitaph, Citadel, Cold Storage, Assembly, Snowbound, The Pit, Narrows).

- Before each game, players vote between three games drawn at random from the playlist. The game just played sits out the next ballot.
- Each game is one round, so a new vote follows every round.
- Friendly fire and voice chat are off. Up to 16 players.

| Parameter | Default |
|---|---|
| `-Name` | `LAN Multiplayer` |
| `-Port` | config (`12346`) |
| `-VoteSeconds` | config (`20`) |
| `-ServerDir` | `.\campaign-server` |
| `-MccDir` | `$env:RECLAIMER_MCC_DIR`, or the Steam path above |

The config goes in `multiplayer.toml` and the playlist in `playlists\lan-multiplayer.playlist.json`, both inside the server folder.

### `start-rcon.ps1`

Opens the RCON desktop client to administer a running server. The client takes no command-line arguments, so the script copies the RCON password to the clipboard and prints the host and port to enter (`127.0.0.1`, port `12345`). RCON listens on this PC only.

The password is generated on the first run of either start script and saved to `campaign-server\rcon-password.txt`.

## Docker

`compose.yaml` runs both servers in one container (campaign co-op on UDP 12345, multiplayer playlist on UDP 12346) from the Linux dedicated server build. The image contains none of Project Reclaimer's software: each time the container starts, `update-binary.sh` downloads the newest dedicated server from their GitHub release, checks its SHA-256 and caches it in the `cache` volume (like `update-binaries.ps1`). If GitHub can't be reached it uses the cached copy. It holds no game files: your MCC folder is mounted read-only at `/server/game` and used in place, so nothing is copied.

```sh
cp .env.example .env       # set MCC_DIR (and MISSION, ports, names if you like)
docker compose up -d --build
docker compose logs -f
```

Players Direct Connect to `<docker host LAN IP>:12345` (co-op) or `:12346` (multiplayer). The `config` folder is mounted into the container at `/etc/reclaimer` (a folder, so editors that replace the file on save still work) and `entrypoint.sh` regenerates `dedicated.toml` from it on every start, so `docker compose restart` applies edits. With no config mounted, the container uses the copy of `config/reclaimer.config.json` baked in at build time. `.env` covers the MCC path, optional overrides and the RCON password.

- Update the server: `docker compose restart` (it checks for a new release on every start). Pin a release with `RECLAIMER_VERSION=v0.10.7`, or set `UPDATE_ON_START=false` to use the cached copy. Rebuild the image only to change the scripts: `docker compose up -d --build`.
- Change the mission: set `MISSION` in `.env` and run `docker compose up -d`.
- RCON listens on TCP at each game port, published on the Docker host's `127.0.0.1` only. The password is in the volume at `/server/rcon-password.txt` (`docker compose exec reclaimer cat /server/rcon-password.txt`), or set `RCON_PASSWORD`.
- Server commands: `docker compose exec reclaimer dedicated status`.
- The container has a healthcheck (`dedicated status`) and waits and retries, instead of exiting, while `dedicated check` fails (for example a missing MCC mount), as the official image does. Extra server settings go in `.env` as `RECLAIMER_DEDICATED_*` variables (admins, `max_players`, `welcome`, ...); see the project's host guide.
- The container needs UDP 12345/12346 reachable from the LAN. UPnP is off.

## Configuration

Settings live in one place, `config/reclaimer.config.json`, read by both the PowerShell scripts and the Docker image: ports, names, missions, difficulty, enemy scaling, skulls, multiplayer maps and modes, vote time, player limit and the other host settings. Edit that file only. The platform files hold just their own plumbing (finding the binary, the MCC path, starting the process, writing the TOML from those values).

Command-line parameters (`-Port`, `-Name`, `-Mission`, `-VoteSeconds`) and the Docker `.env` variables override the file. The one catch: Compose publishes ports from `.env`, not the JSON, so if you change a port in the JSON also set `CAMPAIGN_PORT` / `MULTIPLAYER_PORT` in `.env`; the container refuses to start on a mismatch and says so.

## Layout

```
update-binaries.ps1     download/verify executables
start-campaign.ps1      campaign co-op server
start-multiplayer.ps1   multiplayer playlist server
start-rcon.ps1          RCON client launcher
config/reclaimer.config.json   shared settings (scripts and Docker)
lib.ps1                 helpers for the PowerShell scripts
Dockerfile, compose.yaml, entrypoint.sh, .env.example   Docker version of both servers
campaign-server/        generated server folder (git-ignored)
*.exe                   downloaded binaries (git-ignored)
```

## Notes

- The first run of each mode runs `dedicated init` to copy game files from MCC. This can take a while. The multiplayer script copies only the maps it is missing.
- The scripts regenerate their config on every start, so edit `reclaimer.config.json` rather than the generated `.toml` files. `start-campaign.ps1` keeps a one-time backup of the original as `dedicated.toml.bak`.
- Each script runs `dedicated check` before starting and stops if the config has problems.
