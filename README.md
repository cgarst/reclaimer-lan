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

Run one server at a time. Both modes use port 12345 and the same server folder.

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

Settings (edit the script to change them):

- Difficulty: Legendary
- Friendly fire and voice chat: off
- Enemy scaling: +25% health and +25% damage per extra player
- Sprint: on
- Skulls: Cowbell, Grunt Birthday Party and IWHBYD
- Custom characters (Halo 3 only; ODST uses each player's trooper)
- Up to 16 players

| Parameter | Default |
|---|---|
| `-Name` | `Legendary Co-op` |
| `-Port` | `12345` |
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
| `-Port` | `12345` |
| `-VoteSeconds` | `20` |
| `-ServerDir` | `.\campaign-server` |
| `-MccDir` | `$env:RECLAIMER_MCC_DIR`, or the Steam path above |

The config goes in `multiplayer.toml` and the playlist in `playlists\lan-multiplayer.playlist.json`, both inside the server folder.

### `start-rcon.ps1`

Opens the RCON desktop client to administer a running server. The client takes no command-line arguments, so the script copies the RCON password to the clipboard and prints the host and port to enter (`127.0.0.1`, port `12345`). RCON listens on this PC only.

The password is generated on the first run of either start script and saved to `campaign-server\rcon-password.txt`.

## Layout

```
update-binaries.ps1     download/verify executables
start-campaign.ps1      campaign co-op server
start-multiplayer.ps1   multiplayer playlist server
start-rcon.ps1          RCON client launcher
campaign-server/        generated server folder (git-ignored)
*.exe                   downloaded binaries (git-ignored)
```

## Notes

- The first run of each mode runs `dedicated init` to copy game files from MCC. This can take a while. The multiplayer script copies only the maps it is missing.
- The scripts regenerate their config on every start, so edit the scripts rather than the generated `.toml` files. `start-campaign.ps1` keeps a one-time backup of the original as `dedicated.toml.bak`.
- Each script runs `dedicated check` before starting and stops if the config has problems.
