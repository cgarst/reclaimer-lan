# reclaimer-lan

[Project Reclaimer](https://projectreclaimer.dev) dedicated servers for Halo 3 and Halo 3: ODST in one container: campaign co-op (UDP 12345) and a voted multiplayer playlist (UDP 12346).

- **No Project Reclaimer software or game files in the image.** The dedicated server is downloaded from the project's GitHub release each time the container starts (SHA-256 checked, cached in the `/cache` volume). Mount your own Halo: The Master Chief Collection folder read-only at `/server/game`.
- Settings live in one JSON file (`/etc/reclaimer/reclaimer.config.json`; a default is built in) shared with the PowerShell scripts in the repo.
- linux/amd64. Tags: `latest`, `1.0`.

```sh
docker run -d --name reclaimer-lan --restart unless-stopped \
  -v "/path/to/Halo The Master Chief Collection:/server/game:ro" \
  -v reclaimer-server:/server -v reclaimer-cache:/cache \
  -p 12345:12345/udp -p 12346:12346/udp \
  -p 127.0.0.1:12345:12345/tcp -p 127.0.0.1:12346:12346/tcp \
  cgarst/reclaimer-lan:1.0
```

Environment: `MISSION`, `CAMPAIGN_PORT`, `MULTIPLAYER_PORT`, `CAMPAIGN_NAME`, `MULTIPLAYER_NAME`, `VOTE_SECONDS`, `RCON_PASSWORD`, `RECLAIMER_VERSION`, `UPDATE_ON_START`, plus `RECLAIMER_DEDICATED_*` overrides.

Source, compose file and docs: https://github.com/cgarst/reclaimer-lan (MPL 2.0).
