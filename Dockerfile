# Project Reclaimer dedicated server (campaign co-op + multiplayer playlist in one container).
# The server binary is downloaded from the project's GitHub release at build time and checked
# against the SHA-256 GitHub publishes for it. No game files are included: mount your own MCC
# install at /mcc and the entrypoint copies what it needs on first start.
#
#   docker compose build --pull --no-cache      # pick up the newest release
#   docker compose build --build-arg RECLAIMER_VERSION=v0.10.7
FROM debian:12-slim

ARG RECLAIMER_VERSION=latest

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl jq \
 && rm -rf /var/lib/apt/lists/*

RUN set -eu; \
    case "$(uname -m)" in \
      x86_64)  arch=x86_64 ;; \
      aarch64) arch=aarch64 ;; \
      *) echo "unsupported architecture $(uname -m)" >&2; exit 1 ;; \
    esac; \
    api=https://api.github.com/repos/ProjectReclaimer/project-reclaimer-releases/releases; \
    if [ "$RECLAIMER_VERSION" = latest ]; then url="$api/latest"; else url="$api/tags/$RECLAIMER_VERSION"; fi; \
    curl -fsSL -H 'Accept: application/vnd.github+json' "$url" -o /tmp/release.json; \
    tag="$(jq -r .tag_name /tmp/release.json)"; \
    name="project-reclaimer-dedicated-${tag}-linux-${arch}.tar.gz"; \
    asset="$(jq -c --arg n "$name" '.assets[] | select(.name == $n)' /tmp/release.json)"; \
    [ -n "$asset" ] || { echo "release $tag has no asset $name" >&2; exit 1; }; \
    expected="$(echo "$asset" | jq -r '.digest | sub("^sha256:"; "")')"; \
    curl -fsSL "$(echo "$asset" | jq -r .browser_download_url)" -o "/tmp/$name"; \
    echo "$expected  /tmp/$name" | sha256sum -c -; \
    mkdir -p /opt/reclaimer; \
    tar -xzf "/tmp/$name" -C /opt/reclaimer --strip-components=1; \
    ln -s /opt/reclaimer/project-reclaimer /usr/local/bin/project-reclaimer; \
    echo "$tag" > /opt/reclaimer/VERSION; \
    rm -rf /tmp/release.json "/tmp/$name"

RUN useradd --uid 1000 --create-home --shell /usr/sbin/nologin reclaimer \
 && mkdir -p /server /cache \
 && chown reclaimer:reclaimer /server /cache

COPY --chmod=0755 entrypoint.sh /usr/local/bin/entrypoint.sh
# Default settings, used when no config is mounted at /etc/reclaimer.
COPY config/reclaimer.config.json /usr/share/reclaimer/default.config.json
# `docker compose exec reclaimer dedicated status` etc. against the generated config.
RUN printf '#!/bin/sh\ncd /server && exec project-reclaimer dedicated --config /server/dedicated.toml "$@"\n' \
      > /usr/local/bin/dedicated \
 && chmod 0755 /usr/local/bin/dedicated

USER reclaimer
ENV RECLAIMER_CACHE_DIR=/cache
WORKDIR /server
VOLUME ["/server", "/cache"]
STOPSIGNAL SIGINT
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
