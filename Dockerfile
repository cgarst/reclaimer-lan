# Project Reclaimer dedicated server (campaign co-op + multiplayer playlist in one container).
# This image contains none of Project Reclaimer's software or any game files. At container start
# update-binary.sh downloads the dedicated server from the project's GitHub release, checks its
# SHA-256 and caches it in the /cache volume; your own MCC install is mounted at /server/game for the game files.
#
#   docker compose up -d --build       # the server updates itself on every container start
#   RECLAIMER_VERSION=v0.10.7          # in .env to pin a release
FROM debian:12-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl jq tar tini \
 && rm -rf /var/lib/apt/lists/*

RUN useradd --uid 1000 --create-home --shell /usr/sbin/nologin reclaimer \
 && mkdir -p /server /cache \
 && chown reclaimer:reclaimer /server /cache

COPY --chmod=0755 entrypoint.sh update-binary.sh /usr/local/bin/
# Default settings, used when no config is mounted at /etc/reclaimer.
COPY config/reclaimer.config.json /usr/share/reclaimer/default.config.json
# `docker compose exec reclaimer dedicated status` etc. against the generated config.
RUN printf '#!/bin/sh\ncd /server && exec /cache/bin/current/project-reclaimer dedicated --config /server/dedicated.toml "$@"\n' \
      > /usr/local/bin/dedicated \
 && chmod 0755 /usr/local/bin/dedicated

USER reclaimer
# Profile and caches go in the cache volume, not the container layer.
ENV RECLAIMER_CACHE_DIR=/cache HOME=/cache/home XDG_DATA_HOME=/cache/xdg
WORKDIR /server
VOLUME ["/server", "/cache"]
EXPOSE 12345/udp 12346/udp 49175/tcp 49175/udp
STOPSIGNAL SIGINT
# Healthy while the servers keep their live status fresh (the official image checks the same).
HEALTHCHECK --interval=30s --timeout=10s --start-period=180s --retries=3 CMD ["dedicated", "status"]
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
